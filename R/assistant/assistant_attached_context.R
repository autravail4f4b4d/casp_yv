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


ASSISTANT_CONTEXT_KINDS <- c("entry", "correspondence", "coding_pair")

# WHAT A CONTEXTUAL EXPLANATION MAY BE BUILT FROM (UAT-RM-02).
#
# Live UAT produced generalised prose about PSOC 1112 -- duties, scope,
# rationale -- none of which exists in this deployment's runtime data. The
# assistant's standing claim is "reads verified data only", so the fix is
# not better phrasing: it is stating the boundary to the model and saying
# out loud that the descriptive fields are absent.
#
# Permitted, because the repository actually returns them:
ASSISTANT_CONTEXT_VERIFIED_FIELDS <- c(
  "system", "edition", "code", "title", "level", "hierarchy",
  "status", "issuing authority", "source reference"
)
# Withheld, because no runtime artifact carries them yet. Descriptive
# metadata integration is explicitly out of scope for this pass.
ASSISTANT_CONTEXT_ABSENT_FIELDS <- c(
  "definitions", "duties or main tasks", "inclusions or exclusions",
  "examples", "scope notes", "the rationale for the classification"
)

# The instruction appended to every contextual grounding block. Generic by
# construction: no code, system or edition is named in it, so it cannot
# become hard-coded prose about one record.
#' @param descriptive The record's official descriptive metadata, or NULL.
#'   When present, the fields it supplies are no longer "absent" and the
#'   boundary must not claim they are -- a model told the definition is
#'   unavailable while being handed the definition is being given
#'   contradictory instructions.
.assistant_context_boundary <- function(descriptive = NULL) {
  absent <- ASSISTANT_CONTEXT_ABSENT_FIELDS
  if (!is.null(descriptive)) {
    supplied <- character(0)
    if (length(descriptive$definition) > 0L) supplied <- c(supplied, "definitions")
    if (length(descriptive$tasks) > 0L ||
        length(descriptive$task_summary) > 0L) {
      supplied <- c(supplied, "duties or main tasks")
    }
    if (length(descriptive$examples) > 0L) supplied <- c(supplied, "examples")
    if (length(descriptive$exclusions) > 0L) {
      supplied <- c(supplied, "inclusions or exclusions")
    }
    if (length(descriptive$notes) > 0L) supplied <- c(supplied, "scope notes")
    absent <- setdiff(absent, supplied)
  }

  head <- if (is.null(descriptive)) {
    "Only the fields listed above are available for this record. "
  } else {
    paste0(
      "Everything above is official published text for this exact code. ",
      "Quote or paraphrase it faithfully and do not extend it. "
    )
  }

  if (length(absent) == 0L) {
    return(paste0(
      head,
      "Do not add scope, rationale or relationships that the text above ",
      "does not state, and do not offer any other classification code."
    ))
  }

  paste0(
    head,
    "This application does not currently load ",
    paste(absent, collapse = ", "), " for this record. ",
    "Do not supply any of them from general knowledge, and do not infer ",
    "why the classification is structured as it is. If the user asks for ",
    "something in that list, say plainly that it is not available in this ",
    "application and offer the verified fields above instead."
  )
}


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

#' A PSOC + PSIC coding-pair reference: identifiers only.
#'
#' The processor-facing case (UAT-UI-03): two independently selected
#' records reviewed together. It is a PAIR, never a mapping -- the two
#' halves stay separately identified all the way through, because the one
#' thing this review must not imply is that either code follows from the
#' other.
assistant_context_descriptor_coding_pair <- function(psoc_version, psoc_code,
                                                     psic_version, psic_code) {
  ov <- .assistant_scalar_chr(psoc_version)
  oc <- .assistant_scalar_chr(psoc_code)
  iv <- .assistant_scalar_chr(psic_version)
  ic <- .assistant_scalar_chr(psic_code)
  if (is.null(ov) || is.null(oc) || is.null(iv) || is.null(ic)) return(NULL)
  list(
    kind = "coding_pair",
    psoc_version = ov, psoc_code = oc,
    psic_version = iv, psic_code = ic
  )
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
    coding_pair = .assistant_verify_coding_pair_context(descriptor),
    NULL
  )
}

#' The verified ancestor chain for a record, or character(0).
#'
#' Hierarchy is on the permitted-fields list because the repository really
#' does return it. Read through the same `hierarchy_ancestors()` service
#' the Search detail card uses -- not a second traversal.
.assistant_context_hierarchy <- function(system, version, code) {
  eligible <- tryCatch(hierarchy_is_eligible(system, version),
                       error = function(e) FALSE)
  if (!isTRUE(eligible)) return(character(0))
  chain <- tryCatch(hierarchy_ancestors(system, version, code),
                    error = function(e) character(0))
  if (is.null(chain)) character(0) else as.character(chain)
}

.assistant_verify_coding_pair_context <- function(d) {
  # Each half is verified INDEPENDENTLY, through the same single-entry path
  # as any other attached record. If either fails to verify there is no
  # pair to review, and the turn falls through rather than reviewing half
  # of one.
  occ <- .assistant_verify_entry_context(
    list(kind = "entry", system = "psoc", version = d$psoc_version, code = d$psoc_code)
  )
  ind <- .assistant_verify_entry_context(
    list(kind = "entry", system = "psic", version = d$psic_version, code = d$psic_code)
  )
  if (is.null(occ) || is.null(ind)) return(NULL)
  list(kind = "coding_pair", psoc = occ, psic = ind)
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

  out <- list(
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
  out$hierarchy <- .assistant_context_hierarchy(out$system, out$version, out$code)

  # OFFICIAL DESCRIPTIVE METADATA, AFTER canonical verification.
  #
  # The order here is the authority chain and is not incidental: the record
  # above was just re-read from the repository, and only then is the code
  # used to fetch the official description. The descriptive layer never
  # selects, verifies or authorises anything -- `allowed_codes` is still
  # built from the canonical read alone, so text found here can explain a
  # code but can never make one utterable.
  out$descriptive <- get_psoc_descriptive_metadata(
    version = out$version, code = out$code, level = out$level
  )
  out
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
  } else if (identical(verified$kind, "coding_pair")) {
    # Both halves are authorised, and they are filed under their OWN
    # systems rather than lumped together -- the packet must not be the
    # place where the PSOC/PSIC distinction quietly disappears.
    codes <- c(verified$psoc$code, verified$psic$code)
    codes <- codes[!is.na(codes)]
    occupation <- list(
      status = "resolved",
      selected_code = verified$psoc$code, selected_label = verified$psoc$label,
      classification_level = verified$psoc$level,
      level_display = verified$psoc$level, coding_role = NA_character_,
      version = verified$psoc$version, status_current = verified$psoc$status,
      evidence_source = "attached_context"
    )
    industry <- list(
      status = "resolved",
      selected_code = verified$psic$code, selected_label = verified$psic$label,
      classification_level = verified$psic$level,
      level_display = verified$psic$level, coding_role = NA_character_,
      version = verified$psic$version, status_current = verified$psic$status,
      evidence_source = "attached_context"
    )
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
#' The verified field lines for one entry. Shared by the single-record and
#' coding-pair blocks so the two cannot state a record differently.
.assistant_context_entry_lines <- function(v) {
  lines <- c(
    sprintf("- System: %s", toupper(v$system)),
    sprintf("- Code: %s", v$code),
    sprintf("- Title: %s", v$label)
  )
  if (!is.na(v$level)) lines <- c(lines, sprintf("- Level: %s", v$level))
  if (!is.na(v$version)) lines <- c(lines, sprintf("- Edition: %s", v$version))
  if (!is.na(v$status)) lines <- c(lines, sprintf("- Status: %s", v$status))
  if (length(v$hierarchy) > 0L) {
    lines <- c(lines, sprintf("- Hierarchy: %s › %s",
                              paste(v$hierarchy, collapse = " › "), v$code))
  } else if (!is.na(v$parent_code)) {
    lines <- c(lines, sprintf("- Parent: %s", v$parent_code))
  }
  c(lines, "- Issuing authority: Philippine Statistics Authority")
}

#' The official descriptive lines for a verified record, or character(0).
#'
#' Bounded on purpose. RM is not a second Details panel: it gets the
#' definition, a capped slice of the lettered tasks and of the examples,
#' and the exclusions/notes -- enough to judge whether a supplied
#' occupation fits, not the whole reference page. The full text is in View
#' details, which is where the product rule says it belongs, and sending
#' all of it on every turn would also be a standing token cost for content
#' the user can already read.
.ASSISTANT_CONTEXT_MAX_TASKS <- 8L
.ASSISTANT_CONTEXT_MAX_EXAMPLES <- 12L

.assistant_context_descriptive_lines <- function(d) {
  if (is.null(d)) return(character(0))
  out <- character(0)

  if (length(d$definition) > 0L) {
    out <- c(out, "", "*Official definition*", paste(d$definition, collapse = " "))
  }
  if (length(d$tasks) > 0L) {
    n <- min(length(d$tasks), .ASSISTANT_CONTEXT_MAX_TASKS)
    out <- c(out, "", "*Official tasks*",
             vapply(d$tasks[seq_len(n)], function(t) {
               if (is.na(t$label)) paste0("- ", t$text)
               else sprintf("- (%s) %s", t$label, t$text)
             }, character(1)))
    if (length(d$tasks) > n) {
      out <- c(out, sprintf("- ...and %d more, shown in View details.",
                            length(d$tasks) - n))
    }
  }
  if (length(d$task_summary) > 0L) {
    out <- c(out, "", "*Task summary*", paste(d$task_summary, collapse = " "))
  }
  if (length(d$examples) > 0L) {
    n <- min(length(d$examples), .ASSISTANT_CONTEXT_MAX_EXAMPLES)
    out <- c(out, "", "*Official example occupations*",
             paste0("- ", d$examples[seq_len(n)]))
    if (length(d$examples) > n) {
      out <- c(out, sprintf("- ...and %d more, shown in View details.",
                            length(d$examples) - n))
    }
  }
  if (length(d$exclusions) > 0L) {
    out <- c(out, "", "*Official exclusions*", paste0("- ", d$exclusions))
  }
  if (length(d$notes) > 0L) {
    out <- c(out, "", "*Official notes*", paste0("- ", d$notes))
  }
  out
}

#' What RM is FOR on a turn about a verified record (W5).
#'
#' The user can already read the official reference in View details, so
#' repeating it back is the one unhelpful thing RM can do here. This states
#' the job: interpret, distinguish, and ask the question that would settle
#' the coding.
.assistant_context_role <- function(d) {
  base <- paste(
    "The user can already read the full official definition, tasks and",
    "examples in View details. Do NOT simply repeat them. Be useful for",
    "coding instead: say what kind of work this code covers, what would",
    "distinguish it from a neighbouring code, and whether the duties the",
    "user has described actually fit it."
  )
  if (is.null(d)) {
    return(paste(base,
      "No official descriptive text is available for this code, so say that",
      "plainly and work from the verified identity and hierarchy above."))
  }
  paste(base,
    "If a decision needs information the user has not given, ask ONE short",
    "question for it -- the main duties, or the employer and what the",
    "establishment does. An official example may be cited ONLY if it",
    "appears in the list above.")
}

assistant_render_attached_context <- function(verified) {
  if (is.null(verified)) return(NA_character_)

  if (identical(verified$kind, "entry")) {
    lines <- c(
      "**Record attached by the user (verified from the classification repository)**",
      "",
      .assistant_context_entry_lines(verified),
      .assistant_context_descriptive_lines(verified$descriptive),
      "",
      paste("When the user says \"this\", they mean this record. Explain it",
            "using only the fields above; do not offer any other code."),
      "",
      .assistant_context_role(verified$descriptive),
      "",
      .assistant_context_boundary(verified$descriptive)
    )
    return(paste(lines, collapse = "\n"))
  }

  if (identical(verified$kind, "coding_pair")) {
    lines <- c(
      "**Coding pair attached by the user (both halves verified from the classification repository)**",
      "",
      "PSOC describes the OCCUPATION -- the kind of work the person does.",
      "PSIC describes the ESTABLISHMENT's principal economic activity.",
      "They are separate classifications: neither code implies the other,",
      "and this pair is not a mapping between them.",
      "",
      "*Occupation — PSOC*",
      .assistant_context_entry_lines(verified$psoc),
      # The occupation side gets its official description; the industry
      # side does not, because PSIC descriptive metadata is not part of
      # this milestone. Asymmetry is stated rather than hidden, so the
      # model does not treat a richer PSOC half as the stronger evidence.
      .assistant_context_descriptive_lines(verified$psoc$descriptive),
      "",
      "*Industry — PSIC*",
      .assistant_context_entry_lines(verified$psic),
      "",
      if (!is.null(verified$psoc$descriptive)) {
        paste("Official descriptive text is available for the PSOC side only.",
              "That is a difference in what this application has loaded, NOT",
              "evidence that the occupation is better established than the",
              "industry.")
      },
      "",
      paste("Review these two selections for a coding processor. State each",
            "verified identity, edition and status, and say whether either",
            "is archived rather than current. Do NOT state that the pair is",
            "correct, equivalent, consistent or matched -- you have not been",
            "given the establishment or the person, only the two codes."),
      "",
      paste("If more information would be needed to check the pair, ask only",
            "for: the occupation title and main duties, and the employer or",
            "establishment and its principal economic activity."),
      "",
      .assistant_context_boundary(verified$psoc$descriptive)
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
            "Do not offer any other code."),
      "",
      .assistant_context_boundary()
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
