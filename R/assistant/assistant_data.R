# Accessors for the RM Classification Assistant's supplementary knowledge
# artifacts, built by scripts/build_assistant_assets.R.
#
# These artifacts are SUPPLEMENTARY, never authoritative. The canonical
# PSOC/PSIC repository remains the only source of truth for codes and
# titles; anything surfaced from here must still be verified against it
# before being shown to a user.
#
# Public contract:
#   assistant_common_pairings(data_path = NULL) -> tibble or NULL
#   assistant_psic_rules(data_path = NULL)      -> tibble or NULL
#   assistant_synonyms(data_path = NULL)        -> NULL in V1 (no source)
#   assistant_data_status()                     -> named logical list
#
# GRACEFUL DEGRADATION (spec section 21)
# ---------------------------------------------------------------------
# Every accessor returns NULL when its artifact is absent. None of them
# error. A missing artifact must degrade the assistant, not break it: with
# no pairings and no rules the assistant still works against official
# classification search alone.
#
# The calling layer owns the user-facing consequence. In particular, when
# assistant_psic_rules() returns NULL the caller MUST tell the user that
# detailed PSIC rule assistance is unavailable. It must NEVER fall back to
# the model's own recollection of the PSIC rules: unverifiable recalled
# rules presented as PSA guidance is precisely the failure mode these
# artifacts exist to prevent. assistant_data_status() exists so the UI and
# the tool layer can detect and surface that degraded state explicitly.

ASSISTANT_COMMON_PAIRINGS_PATH <- "data/assistant_common_pairings.rds"
ASSISTANT_PSIC_RULES_PATH <- "data/assistant_psic_rules.rds"
ASSISTANT_SYNONYMS_PATH <- "data/assistant_synonyms.rds"

# In-process memoization cache. Read-once-per-R-process is a hard
# requirement (spec 13.6): these accessors sit on the chat turn path and
# must not touch disk per turn.
.assistant_data_cache <- new.env(parent = emptyenv())

#' Reset the in-process artifact cache (test hook).
.assistant_data_reset_cache <- function() {
  rm(list = ls(.assistant_data_cache), envir = .assistant_data_cache)
  invisible(NULL)
}

# Resolves a repo-root-relative artifact path regardless of whether the
# caller's working directory is the repo root (app.R, Rscript scripts/*.R)
# or tests/testthat (testthat::test_dir() chdirs there).
#
# This mirrors .psic2026_resolve_default_path() in
# R/adapters/adapter_psic_2026.R deliberately: a private copy keeps the
# assistant module from reaching into an adapter it does not own. Only the
# *default* path is resolved this way -- an explicitly supplied data_path
# is used exactly as given, with no fallback searching, so tests can point
# at a known-missing path.
.assistant_resolve_default_path <- function(rel_path) {
  candidates <- c(rel_path, file.path("..", "..", rel_path))
  for (p in candidates) {
    if (file.exists(p)) return(p)
  }
  rel_path
}

# Reads an artifact, memoizing by resolved path. Returns NULL (never an
# error) when the file does not exist. A negative result is cached too, so
# a missing artifact costs one stat() per process rather than one per turn.
.assistant_read_rds_or_null <- function(path, cache_prefix) {
  cache_key <- paste0(cache_prefix, "::", path)

  if (exists(cache_key, envir = .assistant_data_cache, inherits = FALSE)) {
    return(get(cache_key, envir = .assistant_data_cache, inherits = FALSE))
  }

  obj <- if (file.exists(path)) {
    tryCatch(
      readRDS(path),
      error = function(e) {
        # A corrupt artifact degrades exactly like a missing one: the
        # assistant keeps working on official search only, and
        # assistant_data_status() will report FALSE.
        warning(sprintf(
          "Assistant artifact at '%s' could not be read (%s); treating it as unavailable.",
          path, conditionMessage(e)
        ), call. = FALSE)
        NULL
      }
    )
  } else {
    NULL
  }

  assign(cache_key, obj, envir = .assistant_data_cache)
  obj
}

#' Common occupation / PSOC / PSIC pairings (CBMS 2024 mapping).
#'
#' Supplementary reference only. Codes are character strings exactly as
#' published: `psic_rev5_code` may hold a single code, alternatives
#' ("96211 / 96220"), or en-dash ranges ("01171-01189"), and is NA for the
#' published "no fixed PSIC" rows (`has_fixed_psic == FALSE`), where the
#' respondent's actual activity must be established before any PSIC can be
#' assigned.
#'
#' @param data_path character or NULL. NULL (default) resolves the
#'   committed artifact path from either the repo root or tests/testthat.
#'
#' @return A tibble with columns occupation, confirmed_psoc,
#'   source_industry, original_psic, psic_rev5_code, psic_rev5_rule,
#'   mapping_confidence, mapping_note, psa_source (all character) and
#'   has_fixed_psic (logical). NULL if the artifact is unavailable.
assistant_common_pairings <- function(data_path = NULL) {
  path <- if (is.null(data_path)) {
    .assistant_resolve_default_path(ASSISTANT_COMMON_PAIRINGS_PATH)
  } else {
    data_path
  }
  .assistant_read_rds_or_null(path, "common_pairings")
}

#' Compacted PSIC classification rules, keyed by topic.
#'
#' A build-time distillation of PSIC_Chatbot_Classification_Rules.md down
#' to the operative decision logic for 12 topics. The full source document
#' is never shipped to the model at runtime.
#'
#' Returns NULL rather than erroring when the artifact is missing. The
#' caller must then tell the user that detailed PSIC rule assistance is
#' unavailable, and must not substitute recalled rules.
#'
#' @param data_path character or NULL. NULL (default) resolves the
#'   committed artifact path from either the repo root or tests/testthat.
#'
#' @return A tibble with character columns topic, title, rule, example
#'   (example may be NA), one row per topic. NULL if unavailable.
assistant_psic_rules <- function(data_path = NULL) {
  path <- if (is.null(data_path)) {
    .assistant_resolve_default_path(ASSISTANT_PSIC_RULES_PATH)
  } else {
    data_path
  }
  .assistant_read_rds_or_null(path, "psic_rules")
}

#' Classification synonyms / colloquial term mappings.
#'
#' NOT AVAILABLE IN V1. No approved synonym source exists in this
#' repository (data-raw/classification_synonyms.csv is absent) and synonym
#' data is not invented, so no artifact is built and this always returns
#' NULL. The accessor exists so the tool layer can probe for the capability
#' uniformly and report it as unavailable rather than guessing.
#'
#' @param data_path character or NULL.
#'
#' @return NULL while no artifact exists; otherwise the stored object.
assistant_synonyms <- function(data_path = NULL) {
  path <- if (is.null(data_path)) {
    .assistant_resolve_default_path(ASSISTANT_SYNONYMS_PATH)
  } else {
    data_path
  }
  .assistant_read_rds_or_null(path, "synonyms")
}

#' Which supplementary assistant artifacts are actually available.
#'
#' Lets the UI and tool layer surface degraded state explicitly instead of
#' silently answering with less knowledge than the user assumes.
#'
#' @return A named list of three logicals: common_pairings, psic_rules,
#'   synonyms. TRUE means the artifact loaded successfully.
assistant_data_status <- function() {
  list(
    common_pairings = !is.null(assistant_common_pairings()),
    psic_rules      = !is.null(assistant_psic_rules()),
    synonyms        = !is.null(assistant_synonyms())
  )
}
