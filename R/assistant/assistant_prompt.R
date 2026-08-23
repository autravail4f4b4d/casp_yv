# RM assistant prompt content layer.
#
# Owns the immutable, per-process text assets the assistant ships: the compact
# system prompt, the static greeting (spec section 9 -- deliberately NOT model
# generated, so no tokens are spent welcoming anyone), and the panel footer.
#
# Public contract:
#   RM_SYSTEM_PROMPT_PATH        -> character(1) repo-root-relative path
#   rm_system_prompt(path=NULL)  -> character(1) prompt text (memoized)
#   RM_GREETING                  -> character(1) markdown greeting
#   RM_FOOTER_TEXT               -> character(1) footer line
#
# Only immutable text is cached here. Nothing conversational, per-user, or
# mutable belongs in this file's environment.

RM_SYSTEM_PROMPT_PATH <- "prompts/RM_SYSTEM_PROMPT.md"

# In-process memoization of the prompt file. The prompt is immutable for the
# life of the R process, so it is read once, not once per chat turn
# (spec 13.2/13.6).
.rm_prompt_cache <- new.env(parent = emptyenv())

.rm_prompt_reset_cache <- function() {
  rm(list = ls(.rm_prompt_cache), envir = .rm_prompt_cache)
  invisible(NULL)
}

# Resolves a repo-root-relative path regardless of whether the caller's working
# directory is the repository root (app.R, Rscript scripts/*.R) or
# tests/testthat (testthat::test_dir() chdirs there). Mirrors
# .psic2026_resolve_default_path() in R/adapters/adapter_psic_2026.R. Applies
# to the *default* path only -- an explicitly supplied path is used verbatim.
.rm_prompt_resolve_default_path <- function(rel_path) {
  candidates <- c(rel_path, file.path("..", "..", rel_path))
  for (p in candidates) {
    if (file.exists(p)) return(p)
  }
  rel_path
}

#' Load the RM system prompt.
#'
#' @param path character or NULL. NULL (default) resolves
#'   `RM_SYSTEM_PROMPT_PATH` from either the repo root or tests/testthat.
#' @return character(1), the full prompt text.
#'
#' A missing prompt file is a hard configuration error, not a soft degradation:
#' the assistant must never run ungrounded. `create_rm_chat_client()` catches
#' this and reports the assistant as unavailable rather than crashing the app.
rm_system_prompt <- function(path = NULL) {
  resolved <- if (is.null(path)) {
    .rm_prompt_resolve_default_path(RM_SYSTEM_PROMPT_PATH)
  } else {
    path
  }

  cache_key <- paste0("prompt::", resolved)
  cached <- .rm_prompt_cache[[cache_key]]
  if (!is.null(cached)) {
    return(cached)
  }

  if (!file.exists(resolved)) {
    stop(sprintf(
      paste0(
        "RM system prompt file not found at '%s'. Expected the repository ",
        "asset '%s'. The assistant cannot run without its grounding prompt."
      ),
      resolved, RM_SYSTEM_PROMPT_PATH
    ), call. = FALSE)
  }

  txt <- paste(
    readLines(resolved, warn = FALSE, encoding = "UTF-8"),
    collapse = "\n"
  )

  if (!nzchar(trimws(txt))) {
    stop(sprintf(
      "RM system prompt file '%s' is empty.", resolved
    ), call. = FALSE)
  }

  .rm_prompt_cache[[cache_key]] <- txt
  txt
}

# Static greeting (spec 9). Rendered as markdown by shinychat; the
# `suggestion submit` spans are shinychat's starter-suggestion markup.
RM_GREETING <- paste(
  "**Madayaw! I am RM.** I can assist you in finding and understanding",
  "Philippine statistical classifications such as PSOC, PSIC, PSGC, PSCED,",
  "PCOICOP, PCPC, and PSCCS.",
  "",
  "You can describe an occupation, business activity, code, or classification",
  "in English, Filipino/Tagalog, Cebuano/Bisaya, or a mix of these languages.",
  "",
  "If the details are not enough to identify a code with confidence, I may ask",
  "a short follow-up question rather than guess.",
  "",
  "Here are a few things you can ask:",
  "",
  "- <span class='suggestion submit'>Find the PSOC for an occupation</span>",
  "- <span class='suggestion submit'>Help me classify a business under PSIC</span>",
  "- <span class='suggestion submit'>Explain a classification code</span>",
  "- <span class='suggestion submit'>Which classification system should I use?</span>",
  sep = "\n"
)

# Panel footer (spec 9).
RM_FOOTER_TEXT <- paste(
  "RM is an assistant for classification search and interpretation.",
  "Verified codes come from the classification data available in this",
  "application. When details are insufficient, RM may ask a follow-up",
  "question rather than guess."
)
