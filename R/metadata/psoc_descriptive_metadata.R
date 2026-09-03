# PSOC 2022 descriptive metadata — the explanatory layer.
#
# ---------------------------------------------------------------------------
# WHAT THIS IS, AND THE ONE THING IT IS NOT
#
# This service serves OFFICIAL EXPLANATORY TEXT for a PSOC code that has
# ALREADY been verified against the canonical repository: the definition,
# the lettered tasks, the examples, the exclusions, the historical
# crosswalks. It is what lets "View details" show the reference content a
# user would otherwise have to open the workbook for.
#
# It is NOT a classification authority. It cannot select a code, cannot
# rank, cannot search, and cannot make a code allowable. The required chain
# is, and stays:
#
#     existing coding logic
#         -> canonical verification
#             -> exact descriptive lookup      <- this file
#                 -> display / explanation
#
# NO VERIFIED CANONICAL CODE = NO METADATA. The lookup is exact and keyed;
# there is deliberately no fuzzy match, no prefix match, no "nearest code"
# and no listing interface. A caller that has not already verified a code
# has nothing to pass in.
#
# WHY THERE IS NO SEARCH FUNCTION HERE. The moment this layer could be
# asked "which code matches this text", descriptive prose would be
# influencing code selection -- which is exactly the authority inversion the
# project forbids. The absence of that function is the safeguard, and it is
# asserted by test.
#
# ---------------------------------------------------------------------------
# PUBLIC CONTRACT
#
#   psoc_descriptive_available()                  -> logical(1)
#   psoc_descriptive_source()                     -> provenance list or NULL
#   get_psoc_descriptive_metadata(version, code, level = NULL)
#                                                 -> record list or NULL
#   psoc_descriptive_has_content(record)          -> logical(1)
#
# The runtime artifact is `data/psoc_2022_descriptive.rds`, compiled from
# `data-raw/psoc_2022_structured.json` by
# `scripts/build_psoc_2022_descriptive.R`. The application NEVER reads
# data-raw: that is source, and only the validated artifact is loaded.

PSOC_DESCRIPTIVE_PATH <- file.path("data", "psoc_2022_descriptive.rds")

# The editions this service knows about. PSOC 2022 only for this milestone;
# an unknown edition fails closed rather than falling back to 2022, because
# silently answering for the wrong edition is the classic way a
# classification tool starts lying.
PSOC_DESCRIPTIVE_VERSIONS <- "2022"

# Process-level cache. The artifact is immutable and read-only, so one load
# per R process is safe and is the same pattern the other offline artifacts
# use. Never per-session: this is shared reference data, not user state.
.psoc_descriptive_cache <- new.env(parent = emptyenv())

# Resolves a repo-root-relative artifact path whether the caller's working
# directory is the repo root (app.R, Rscript scripts/*.R) or tests/testthat
# (testthat::test_dir() runs with cwd = tests/testthat). The same resolver
# idiom the PSCC and PSCrCS adapters already use, so all offline artifacts
# behave identically under test.
.psoc_descriptive_resolve_path <- function(rel_path) {
  for (p in c(rel_path, file.path("..", "..", rel_path))) {
    if (file.exists(p)) return(p)
  }
  rel_path
}

#' Load (once) and return the descriptive artifact, or NULL.
#'
#' Fails closed and quietly: a deployment without the artifact keeps every
#' deterministic classification feature working and simply shows no
#' descriptive sections. The absence of official text is never an error
#' state for the user.
.psoc_descriptive_artifact <- function() {
  if (!is.null(.psoc_descriptive_cache$loaded)) {
    return(.psoc_descriptive_cache$artifact)
  }
  .psoc_descriptive_cache$loaded <- TRUE
  .psoc_descriptive_cache$artifact <- NULL

  path <- .psoc_descriptive_resolve_path(PSOC_DESCRIPTIVE_PATH)
  if (!file.exists(path)) {
    message("[psoc-descriptive] artifact not found at ", path,
            "; descriptive sections will be hidden.")
    return(NULL)
  }
  art <- tryCatch(readRDS(path), error = function(e) {
    message("[psoc-descriptive] could not read ", path, ": ", conditionMessage(e))
    NULL
  })
  if (is.null(art)) return(NULL)

  # Structural gate. A file that is present but not the artifact this code
  # expects is treated as absent, not trusted.
  ok <- is.list(art) &&
    identical(art$system, "psoc") &&
    identical(art$version, "2022") &&
    is.list(art$records) &&
    length(art$records) > 0L &&
    !is.null(names(art$records))
  if (!ok) {
    message("[psoc-descriptive] artifact at ", path, " is not the expected shape.")
    return(NULL)
  }

  .psoc_descriptive_cache$artifact <- art
  art
}

#' Is descriptive metadata available in this deployment?
psoc_descriptive_available <- function() {
  !is.null(.psoc_descriptive_artifact())
}

#' Provenance for the descriptive text, or NULL.
#'
#' Carried so a surface can state where the official wording came from
#' without reaching into data-raw or hard-coding a filename.
psoc_descriptive_source <- function() {
  art <- .psoc_descriptive_artifact()
  if (is.null(art)) return(NULL)
  art$source
}

#' Exact descriptive lookup for an ALREADY-VERIFIED PSOC code.
#'
#' @param version character(1). Canonical edition identifier. Only "2022" is
#'   served; anything else returns NULL.
#' @param code character(1). A canonical PSOC code the CALLER has already
#'   verified against the repository. This function does not verify it and
#'   must never be used as if it did -- it answers "what does the official
#'   reference say about this code", not "is this code real".
#' @param level character(1) or NULL. When supplied, the canonical level the
#'   caller expects. A disagreement returns NULL rather than the record: if
#'   the caller and the artifact disagree about what this code IS, the safe
#'   answer is to show nothing.
#'
#' @return The descriptive record, or NULL. Never errors.
get_psoc_descriptive_metadata <- function(version, code, level = NULL) {
  art <- .psoc_descriptive_artifact()
  if (is.null(art)) return(NULL)

  v <- .psoc_desc_scalar(version)
  cd <- .psoc_desc_scalar(code)
  if (is.null(v) || is.null(cd)) return(NULL)
  if (!v %in% PSOC_DESCRIPTIVE_VERSIONS) return(NULL)

  rec <- art$records[[cd]]
  if (is.null(rec)) return(NULL)

  if (!is.null(level)) {
    lv <- .psoc_desc_scalar(level)
    if (is.null(lv) || !identical(lv, rec$level)) return(NULL)
  }

  rec
}

#' Does a record carry any renderable official content?
#'
#' A record can exist and still have nothing to show -- the workbook does
#' not describe every group. Callers use this to decide whether to render a
#' descriptive region at all, rather than drawing an empty shell.
psoc_descriptive_has_content <- function(record) {
  if (is.null(record)) return(FALSE)
  any(
    length(record$definition) > 0L,
    length(record$tasks) > 0L,
    length(record$task_summary) > 0L,
    length(record$examples) > 0L,
    length(record$related_occupations) > 0L,
    length(record$exclusions) > 0L,
    length(record$notes) > 0L,
    !is.null(record$crosswalk$psoc_1992$raw) &&
      !is.na(record$crosswalk$psoc_1992$raw),
    !is.null(record$crosswalk$isco_2008$raw) &&
      !is.na(record$crosswalk$isco_2008$raw)
  )
}

.psoc_desc_scalar <- function(x) {
  if (is.null(x) || length(x) == 0L) return(NULL)
  v <- as.character(x)[[1L]]
  if (is.na(v) || !nzchar(trimws(v))) return(NULL)
  trimws(v)
}
