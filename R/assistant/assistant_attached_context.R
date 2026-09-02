# Attached-context bridge — the verified UI selection, made available to RM.
#
# THE PROBLEM THIS SOLVES
# -----------------------
# The UI can attach a record to the assistant panel ("Ask RM about this
# entry", "Ask RM to explain this relationship"), and the chip for it is
# visible and removable. Until this file existed the chip was inert: a user
# who attached PSOC 1112 and asked "Why is this classified here?" was asking
# about a referent RM had no access to, and the turn was coded as if the
# words "why is this classified here" described somebody's job.
#
# WHAT THIS IS, AND WHAT IT DELIBERATELY IS NOT
# ---------------------------------------------
# It is a BRIDGE, not a retrieval path. Nothing here searches, ranks, or
# decides a classification. Every field RM is allowed to see is re-read from
# the canonical repository at turn time through the same services the
# deterministic app uses, and a descriptor that fails that read yields
# NOTHING rather than a degraded answer.
#
#   * no second classification path -- the only calls made here are
#     `get_classification_entry()` and `get_psic_correspondence()`, the
#     same canonical readers Search and Compare Editions use;
#   * no bypass of `assistant_handle_turn()` -- the bridge is consulted
#     from inside it, and only from inside it;
#   * no bypass of canonical verification -- the descriptor carries
#     IDENTIFIERS ONLY (system, version, code). Labels, levels, statuses
#     and relationship facts are never taken from the descriptor, so a
#     stale or tampered chip cannot put a single word in front of the user
#     that the repository did not just return;
#   * no semantic retrieval, and no change to retrieval authority.
#
# WHY A DESCRIPTOR RATHER THAN THE ROW ITSELF
# -------------------------------------------
# The UI holds a canonical row already, and it would be less code to hand
# that row straight to the model. It is deliberately not done: a row held
# across turns is a snapshot, and the one thing this application must never
# do is present classification facts that were true earlier. Carrying only
# the identifiers forces a fresh canonical read on the turn that uses them,
# which is also what makes "the edition was switched underneath you" fail
# closed instead of silently.
#
# PRECEDENCE (rules 6 and 7 of the milestone brief)
# -------------------------------------------------
# Attached context is the WEAKEST referent in the system. It applies only
# when all of the following hold:
#
#   1. the turn is a short referential/explanation question
#      (`assistant_explanation_requested()`, unchanged);
#   2. there is NO pending clarification -- an outstanding bounded question
#      owns the next reply, whatever is attached to the panel;
#   3. there is NO latest packet -- an answer RM itself just produced is a
#      nearer referent for "this" than a chip attached earlier.
#
# An explicit new coding request is not a referential turn at all, so it
# never reaches this file: it routes and codes exactly as it did before.
#
# PUBLIC CONTRACT
#   assistant_context_descriptor_entry(system, version, code)
#   assistant_context_descriptor_correspondence(from_version, from_code,
#                                               to_version, to_code)
#   assistant_verify_attached_context(descriptor)   -> verified list or NULL
#   assistant_attached_context_packet(verified)     -> coding-service-shaped
#   assistant_render_attached_context(verified)     -> grounding text
#   assistant_attached_context_for_turn(text, pending, latest_packet,
#                                       descriptors)  -> verified or NULL
#   assistant_append_context_turn(turns, text)      -> ellmer turns


ASSISTANT_CONTEXT_KINDS <- c("entry", "correspondence")


# ---- Descriptors -----------------------------------------------------------

#' A classification-entry reference: identifiers only.
#'
#' @param system,version,code character(1) canonical identifiers, exactly as
#'   the repository stores them.
#' @return a descriptor list, or NULL when any identifier is missing.
assistant_context_descriptor_entry <- function(system, version, code) {
  sys <- .assistant_scalar_chr(system)
  ver <- .assistant_scalar_chr(version)
  cd <- .assistant_scalar_chr(code)
  if (is.null(sys) || is.null(ver) || is.null(cd)) return(NULL)
  list(kind = "entry", system = sys, version = ver, code = cd)
}

#' A PSIC edition-correspondence reference: identifiers only.
assistant_context_descriptor_correspondence <- function(from_version, from_code,
                                                        to_version, to_code) {
  fv <- .assistant_scalar_chr(from_version)
  fc <- .assistant_scalar_chr(from_code)
  tv <- .assistant_scalar_chr(to_version)
  tc <- .assistant_scalar_chr(to_code)
  if (is.null(fv) || is.null(tv)) return(NULL)
  # One side may legitimately be absent (a code with no counterpart), but
  # not both -- there would be no relationship to explain.
  if (is.null(fc) && is.null(tc)) return(NULL)
  list(
    kind = "correspondence",
    from_version = fv, from_code = fc,
    to_version = tv, to_code = tc
  )
}


# ---- Canonical verification ------------------------------------------------

#' Re-read an attached descriptor from the canonical repository.
#'
#' EVERY user-visible field in the result comes from this read. The
#' descriptor contributes identifiers and nothing else.
#'
#' @return a verified context list, or NULL when the record cannot be read.
assistant_verify_attached_context <- function(descriptor) {
  if (is.null(descriptor) || !is.list(descriptor)) return(NULL)
  kind <- .assistant_scalar_chr(descriptor$kind)
  if (is.null(kind) || !(kind %in% ASSISTANT_CONTEXT_KINDS)) return(NULL)

  switch(kind,
    entry = .assistant_verify_entry_context(descriptor),
    correspondence = .assistant_verify_correspondence_context(descriptor),
    NULL
  )
}

.assistant_verify_entry_context <- function(d) {
  row <- tryCatch(
    get_classification_entry(d$system, d$version, d$code),
    error = function(e) NULL
  )
  if (is.null(row) || nrow(row) == 0L) return(NULL)
  row <- row[1, , drop = FALSE]

  chr <- function(x) {
    v <- as.character(x[[1L]])
    if (length(v) == 0L || is.na(v)) NA_character_ else v
  }

  list(
    kind = "entry",
    system = chr(row$system),
    version = chr(row$version),
    code = chr(row$code),
    label = chr(row$label),
    level = chr(row$level),
    status = chr(row$status),
    parent_code = if ("parent_code" %in% names(row)) chr(row$parent_code) else NA_character_,
    source = if ("source" %in% names(row)) chr(row$source) else NA_character_
  )
}

.assistant_verify_correspondence_context <- function(d) {
  # Read from whichever side carries a code. `get_psic_correspondence()`
  # matches a code on either side of the pair, so one lookup covers both
  # directions and a no-counterpart relationship still resolves.
  probe <- if (!is.null(d$from_code)) d$from_code else d$to_code
  rows <- tryCatch(
    get_psic_correspondence(probe, from_version = d$from_version,
                            to_version = d$to_version),
    error = function(e) NULL
  )
  if (is.null(rows) || nrow(rows) == 0L) return(NULL)

  # Narrow to the exact pair the user attached where both sides are known;
  # a code the artifact splits into several targets would otherwise be
  # ambiguous, and presenting the wrong half of a split is precisely the
  # error the correspondence rules forbid.
  if (!is.null(d$from_code) && !is.null(d$to_code)) {
    exact <- rows[!is.na(rows$from_code) & rows$from_code == d$from_code &
                    !is.na(rows$to_code) & rows$to_code == d$to_code, , drop = FALSE]
    if (nrow(exact) > 0L) rows <- exact
  }
  if (nrow(rows) != 1L) return(NULL)
  row <- rows[1, , drop = FALSE]

  chr <- function(nm) {
    if (!nm %in% names(row)) return(NA_character_)
    v <- as.character(row[[nm]][[1L]])
    if (length(v) == 0L || is.na(v)) NA_character_ else v
  }

  list(
    kind = "correspondence",
    from_version = chr("from_version"), from_code = chr("from_code"),
    from_label = chr("from_label"), from_level = chr("from_level"),
    to_version = chr("to_version"), to_code = chr("to_code"),
    to_label = chr("to_label"), to_level = chr("to_level"),
    relation_type = chr("relation_type"), confidence = chr("confidence"),
    provenance = chr("provenance")
  )
}


# ---- The packet the guard reads -------------------------------------------

#' Wrap a verified context as a coding-service-shaped packet.
#'
#' WHY A PACKET. The response guard authorises codes from
#' `assistant_allowed_codes(packet)`, and the explanation path in
#' `assistant_handle_turn()` requires a retained packet to exist. Handing
#' the bridge's verified read through the SAME structure means the guard,
#' the renderer and the explanation path all keep working unchanged -- and,
#' critically, that the ONLY codes RM may utter on a context turn are the
#' ones the repository just returned.
#'
#' `request_type` is `"attached_context"` so nothing downstream can mistake
#' this for a coding decision the service made.
assistant_attached_context_packet <- function(verified) {
  if (is.null(verified)) return(NULL)

  codes <- character(0)
  occupation <- NULL
  industry <- NULL

  if (identical(verified$kind, "entry")) {
    codes <- verified$code
    half <- list(
      status = "resolved",
      selected_code = verified$code,
      selected_label = verified$label,
      classification_level = verified$level,
      level_display = verified$level,
      coding_role = NA_character_,
      version = verified$version,
      status_current = verified$status,
      evidence_source = "attached_context"
    )
    # Only the two systems the packet shape names get a half; every other
    # system is still fully authorised through `allowed_codes$context`.
    if (identical(verified$system, "psoc")) occupation <- half
    if (identical(verified$system, "psic")) industry <- half
  } else if (identical(verified$kind, "correspondence")) {
    codes <- c(verified$from_code, verified$to_code)
    codes <- codes[!is.na(codes)]
  }

  list(
    status = "attached_context",
    request_type = "attached_context",
    requested_systems = character(0),
    occupation = occupation,
    industry = industry,
    clarification = list(missing_slot = NA_character_, question = NA_character_,
                         options = list()),
    # `context` is a THIRD slot beside psoc/psic. `assistant_allowed_codes()`
    # unions it, so a PSGC or PSCED record attached from Search authorises
    # its own code without being misfiled as an occupation or an industry.
    allowed_codes = list(psoc = character(0), psic = character(0),
                         context = as.character(codes)),
    current_edition_enforced = TRUE,
    attached_context = verified,
    guidance = paste(
      "This record was selected by the user in the application and re-read",
      "from the classification repository for this turn. State it exactly as",
      "given. Do not offer any other classification code."
    )
  )
}


# ---- Grounding text --------------------------------------------------------

#' Render a verified context as the block RM is grounded with.
#'
#' Deterministic, assembled in R from the canonical read. The model never
#' sees the chip's label text, only this.
assistant_render_attached_context <- function(verified) {
  if (is.null(verified)) return(NA_character_)

  if (identical(verified$kind, "entry")) {
    lines <- c(
      "**Record attached by the user (verified from the classification repository)**",
      "",
      sprintf("- System: %s", toupper(verified$system)),
      sprintf("- Code: %s", verified$code),
      sprintf("- Label: %s", verified$label)
    )
    if (!is.na(verified$level)) lines <- c(lines, sprintf("- Level: %s", verified$level))
    if (!is.na(verified$version)) lines <- c(lines, sprintf("- Edition: %s", verified$version))
    if (!is.na(verified$status)) lines <- c(lines, sprintf("- Status: %s", verified$status))
    if (!is.na(verified$parent_code)) {
      lines <- c(lines, sprintf("- Parent: %s", verified$parent_code))
    }
    lines <- c(
      lines,
      "- Source: Philippine Statistics Authority",
      "",
      paste("When the user says \"this\", they mean this record. Explain it",
            "using only the fields above; do not offer any other code.")
    )
    return(paste(lines, collapse = "\n"))
  }

  if (identical(verified$kind, "correspondence")) {
    side <- function(code, label, version) {
      if (is.na(code)) return("(no counterpart in this edition)")
      sprintf("%s %s — %s", version, code, label)
    }
    lines <- c(
      "**PSIC edition relationship attached by the user (verified from the correspondence artifact)**",
      "",
      sprintf("- From: %s", side(verified$from_code, verified$from_label, verified$from_version)),
      sprintf("- To: %s", side(verified$to_code, verified$to_label, verified$to_version)),
      sprintf("- Relationship: %s", verified$relation_type),
      sprintf("- Confidence: %s", verified$confidence),
      "",
      paste("When the user says \"this relationship\", they mean the pair",
            "above. A correspondence relationship does not by itself justify",
            "redistributing historical statistical values between the two",
            "categories; say so if the user asks about using it that way.",
            "Do not offer any other code.")
    )
    return(paste(lines, collapse = "\n"))
  }

  NA_character_
}


# ---- Selection ------------------------------------------------------------

#' Decide whether the attached context applies to THIS turn, and verify it.
#'
#' Pure apart from the canonical read. Every precedence rule lives here, in
#' one place, so the ordering cannot drift between the execution path and
#' the tests that pin it.
#'
#' @param text character(1). The user's raw message.
#' @param pending The session's pending clarification, or NULL.
#' @param latest_packet The session's retained packet, or NULL.
#' @param descriptors A list of attached descriptors, newest LAST.
#'
#' @return the verified context list, or NULL when the context does not
#'   apply or cannot be verified.
assistant_attached_context_for_turn <- function(text, pending, latest_packet,
                                                descriptors) {
  if (is.null(descriptors) || length(descriptors) == 0L) return(NULL)

  # RULE 7. An outstanding bounded question owns the next reply. A chip
  # attached to the panel must never consume, redirect or widen it.
  if (!is.null(pending)) return(NULL)

  # An answer RM itself just produced is the nearer referent for "this".
  if (!is.null(latest_packet)) return(NULL)

  # RULE 6. Only a short referential question reaches the context at all.
  # A fresh coding request is not one, so it routes and codes untouched.
  if (!assistant_explanation_requested(text)) return(NULL)

  # Newest attachment first: the last thing the user pressed Ask RM from is
  # what they are pointing at.
  for (d in rev(descriptors)) {
    verified <- assistant_verify_attached_context(d)
    if (!is.null(verified)) return(verified)
  }
  NULL
}


# ---- Grounding the provider's history -------------------------------------

#' Append the verified context to the client's turns as an assistant note.
#'
#' Called BEFORE the provider round-trip, so the model reads the record as
#' something already established in the conversation and the user's
#' referential question lands against it.
#'
#' Distinct from `assistant_ground_turns()`, which REPLACES the last
#' assistant turn after the fact; this one adds a turn ahead of time and
#' never rewrites anything the model or the user already said.
assistant_append_context_turn <- function(turns, text) {
  t <- .assistant_scalar_chr(text)
  if (is.null(t) || !nzchar(trimws(t))) return(turns)
  if (is.null(turns)) turns <- list()
  c(turns, list(ellmer::Turn("assistant", t)))
}
