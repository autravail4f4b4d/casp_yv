# W1-D / W2 -- output guard and deterministic result rendering.
#
# THE BACKSTOP. The router removes the bypass and the coding service owns
# the decision, but neither can stop the model from simply TYPING a code.
# That is exactly what happened live: the model produced 1112 for "mayor"
# and then "verified" it with the entry tool, so the digits looked
# authoritative. This guard is the last line: any classification code in
# generated prose must appear in the coding service's allowed_codes, or the
# generated coding text is discarded and replaced with a deterministic
# rendering built from the packet itself.
#
# Per spec 19 the guard NEVER edits individual digits inside prose --
# silently rewriting "1112" to "1111" would leave the surrounding
# explanation arguing for the wrong occupation. It rejects wholesale and
# re-renders from verified facts.

# WHAT THE READER IS TOLD WHEN THERE IS NOTHING VERIFIED TO SHOW
# (UAT2-RM-01).
#
# The guard's fallback is `assistant_render_coding_result(packet)`, and for
# a packet that carries no coding result -- an attached-context explanation
# turn, for instance -- that rendering is legitimately the empty string.
# Appending an empty string ends the turn with a loading indicator and no
# answer, which is indistinguishable from a hang and is exactly what
# browser UAT reported.
#
# So there is one plain sentence for that case. It states the rule from
# CLAUDE.md in the reader's terms -- RM could not verify it from this
# application's classification data -- and points at the deterministic
# search, which always works. No provider error, no code, no stack trace,
# no technical vocabulary: this is a public application.
ASSISTANT_UNVERIFIED_REPLY_TEXT <- paste(
  "I could not verify an answer to that from the classification data",
  "available in this application, so I would rather not guess.",
  "You can search or browse the official classifications directly, or",
  "give me a little more detail and I will try again."
)

# Codes are matched by shape, then filtered to ones that plausibly refer to
# a classification: bare 3-5 digit runs, dotted PSCC commodity codes, and
# 10-digit PSGC codes. Deliberately shape-based so it also catches a code
# the model invented for a system nobody asked about.
.ASSISTANT_GUARD_CODE_PATTERN <-
  "\\b[0-9]{2}\\.[0-9]{2}\\.[0-9]{2}-[0-9]{3}\\b|\\b[0-9]{10}\\b|\\b[0-9]{3,5}\\b"

# Numbers that are years or editions, not codes. Without this the guard
# would reject a perfectly good answer for mentioning "2022".
.assistant_guard_edition_tokens <- function(packet) {
  v <- character(0)
  for (half in list(packet$occupation, packet$industry)) {
    if (!is.null(half) && !is.null(half$version) && !is.na(half$version)) {
      v <- c(v, as.character(half$version))
    }
  }
  unique(c(v, "2012", "2019", "2022", "2026", "2009", "2018", "2020", "2002", "2025", "2017"))
}

#' Extract candidate classification codes from generated prose.
assistant_guard_extract_codes <- function(text, packet = NULL) {
  t <- .assistant_scalar_chr(text)
  if (is.null(t)) return(character(0))
  hits <- regmatches(t, gregexpr(.ASSISTANT_GUARD_CODE_PATTERN, t))[[1L]]
  hits <- unique(trimws(hits))
  hits <- hits[nzchar(hits)]
  if (length(hits) == 0L) return(character(0))
  setdiff(hits, .assistant_guard_edition_tokens(packet))
}

#' Check generated prose against the packet's allowed_codes.
#'
#' @return list(ok, offending_codes, allowed, reason).
assistant_guard_check <- function(text, packet) {
  allowed <- assistant_allowed_codes(packet)
  found <- assistant_guard_extract_codes(text, packet)
  offending <- setdiff(found, allowed)

  # A clarification-required system must contribute no codes at all beyond
  # its supported aggregate, which is already the only thing in `allowed`.
  ok <- length(offending) == 0L
  list(
    ok = ok,
    offending_codes = offending,
    allowed = allowed,
    reason = if (ok) NA_character_ else sprintf(
      "Response contained %d classification code(s) the coding service did not authorise: %s.",
      length(offending), paste(offending, collapse = ", ")
    )
  )
}

# --- deterministic rendering (W2) ------------------------------------------

.assistant_render_half <- function(half, heading, system_label) {
  if (is.null(half)) return(character(0))
  if (identical(half$status, "no_verified_match") ||
      is.null(half$selected_code) || is.na(half$selected_code)) {
    return(c(
      sprintf("**%s — %s**", heading, system_label),
      "",
      "No code from the current edition could be verified for this.",
      ""
    ))
  }
  lines <- c(
    sprintf("**%s — %s**", heading, system_label),
    "",
    sprintf("- Code: %s", half$selected_code),
    sprintf("- Label: %s", half$selected_label)
  )
  if (!is.null(half$level_display) && !is.na(half$level_display)) {
    lines <- c(lines, sprintf("- Level: %s", half$level_display))
  }
  if (!is.null(half$coding_role) && !is.na(half$coding_role)) {
    lines <- c(lines, sprintf("- Coding role: %s", half$coding_role))
  }
  if (!is.null(half$version) && !is.na(half$version)) {
    lines <- c(lines, sprintf("- Edition: %s", half$version))
  }
  if (!is.null(half$status_current) && !is.na(half$status_current)) {
    lines <- c(lines, sprintf("- Status: %s", half$status_current))
  }
  c(lines, "- Source: Philippine Statistics Authority", "")
}

#' Render the coding packet deterministically, with no model involvement.
#'
#' Used both as the guard's fallback and as the authoritative block the
#' model is asked to explain rather than restate.
assistant_render_coding_result <- function(packet) {
  if (is.null(packet)) return("")
  out <- character(0)

  if ("psoc" %in% packet$requested_systems) {
    out <- c(out, .assistant_render_half(packet$occupation,
                                         "Occupation classification", "PSOC"))
  }
  if ("psic" %in% packet$requested_systems) {
    ind <- packet$industry
    if (!is.null(ind) && identical(ind$status, "clarification_required") &&
        is.null(ind$selected_code)) {
      out <- c(out,
               "**Industry classification — PSIC**", "",
               "Not determined yet — see the question below.", "")
    } else {
      out <- c(out, .assistant_render_half(ind, "Industry classification", "PSIC"))
    }
  }

  cl <- packet$clarification
  if (!is.null(cl) && !is.na(cl$missing_slot)) {
    out <- c(out, cl$question, "")
    if (length(cl$options) > 0L) {
      out <- c(out, vapply(cl$options, function(o) sprintf("- %s", o$label), character(1)), "")
    }
  }

  if (identical(packet$status, "no_verified_match") && length(out) == 0L) {
    out <- c("No classification code could be verified from the application's",
             "official data for this description.")
  }
  paste(trimws(paste(out, collapse = "\n")), collapse = "\n")
}

#' Render a BATCH of independently-resolved coding requests (spec 28).
#'
#' One block per request, each labelled with the user's own wording, so a
#' six-line batch produces six independent answers instead of the single
#' collapsed one the live build produced (measured: all six lines returned
#' 3424 ESPORTS PLAYERS AND COACHES). Purely deterministic -- every code,
#' label, level, edition and status comes from the per-item packet, never
#' from generated prose.
#'
#' @param resolved list of `list(label, packet)` for items that resolved.
#' @param unresolved list of `list(label, packet)` still needing an answer.
#'
#' @return character(1) markdown.
assistant_render_batch_results <- function(resolved = list(), unresolved = list()) {
  out <- character(0)

  for (item in resolved) {
    heading <- .assistant_scalar_chr(item$label)
    if (!is.null(heading)) out <- c(out, sprintf("### %s", heading), "")
    out <- c(out, assistant_render_coding_result(item$packet), "")
  }

  if (length(unresolved) > 0L) {
    for (item in unresolved) {
      heading <- .assistant_scalar_chr(item$label)
      if (!is.null(heading)) out <- c(out, sprintf("### %s", heading), "")
      cl <- item$packet$clarification
      if (!is.null(cl) && !is.na(cl$missing_slot)) {
        # Each unresolved item carries its OWN question. None of them is
        # promoted into session pending state unless it is the only one
        # (assistant_turn_finalize_batch), so answering one can never be
        # misread as answering another.
        out <- c(out, cl$question, "")
      } else {
        out <- c(out, assistant_render_coding_result(item$packet), "")
      }
    }
  }

  paste(trimws(paste(out, collapse = "\n")), collapse = "\n")
}

# --- W4: transcript hygiene (spec 25) --------------------------------------
#
# Nothing internal to the application's plumbing may appear in a
# user-visible reply: no markup, no custom elements, no tool names, no raw
# tool payloads. These are matched as ARTEFACTS, not as forbidden English:
# the patterns are anchored on syntax (`<svg`, `shinychat-raw-html`,
# `assistant_something(`) or on the literal registered tool names, so an
# ordinary sentence cannot trip them.
#
# The deterministic renderer cannot produce any of these by construction --
# it emits only markdown built from packet fields -- so this guard exists
# for generated prose, which is the only text on a coding route that this
# application does not author itself.
ASSISTANT_TRANSCRIPT_ARTIFACT_PATTERNS <- c(
  "<\\s*svg", "</\\s*svg", "\\bsvg\\b",
  "shinychat-raw-html", "shiny-tool-request", "shiny-tool-result",
  "\\bassistant_[a-z_]+\\s*\\(",
  "\\btool (request|result|call)\\b",
  "\\{\\s*\"[a-z_]+\"\\s*:"
)

#' Which internal artefacts, if any, does this text contain?
#'
#' @return character vector of the patterns that matched; empty when clean.
assistant_transcript_artifacts <- function(text) {
  t <- .assistant_scalar_chr(text)
  if (is.null(t)) return(character(0))
  low <- tolower(t)
  hits <- vapply(
    ASSISTANT_TRANSCRIPT_ARTIFACT_PATTERNS,
    function(p) grepl(p, low, perl = TRUE),
    logical(1), USE.NAMES = FALSE
  )
  named <- vapply(
    ASSISTANT_INTERNAL_TOOL_NAME_LITERALS,
    function(n) grepl(n, low, fixed = TRUE),
    logical(1), USE.NAMES = FALSE
  )
  c(ASSISTANT_TRANSCRIPT_ARTIFACT_PATTERNS[hits],
    ASSISTANT_INTERNAL_TOOL_NAME_LITERALS[named])
}

#' Apply the guard: return the model's text when it is safe, otherwise the
#' deterministic rendering.
#'
#' @return list(text, used_fallback, check).
assistant_guard_response <- function(text, packet) {
  artifacts <- assistant_transcript_artifacts(text)
  if (length(artifacts) > 0L) {
    message(sprintf(
      "[rm-assistant] response guard rejected a reply carrying internal artefacts: %s",
      paste(artifacts, collapse = ", ")
    ))
    return(list(
      text = assistant_render_coding_result(packet),
      used_fallback = TRUE,
      check = list(ok = FALSE, offending_codes = character(0),
                   allowed = assistant_allowed_codes(packet),
                   reason = "Response contained internal rendering artefacts.")
    ))
  }
  chk <- assistant_guard_check(text, packet)
  if (isTRUE(chk$ok)) {
    return(list(text = as.character(text), used_fallback = FALSE, check = chk))
  }
  message(sprintf("[rm-assistant] response guard rejected a reply: %s", chk$reason))
  list(
    text = assistant_render_coding_result(packet),
    used_fallback = TRUE,
    check = chk
  )
}
