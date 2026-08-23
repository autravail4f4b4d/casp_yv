# Runtime, offline, bidirectional access to the built PSIC 2019<->2026
# correspondence artifact (data/psic_2019_to_2026_correspondence.rds,
# produced by scripts/build_psic_correspondence.R).
#
# Public contract:
#   get_psic_correspondence(code, from_version = "2019", to_version = "2026")
#   search_psic_correspondence(query, from_version, to_version, limit = 20)
#
# Both functions return a zero-row tibble (never NULL, never an error) when
# nothing matches -- mirroring the existing MVP convention in
# R/repository.R's `get_classification_entry()`.
#
# DIRECTIONALITY
# --------------
# The artifact is built asymmetrically: every row's "source" side is a
# PSIC 2019 entry and every row's "target" side is a PSIC 2026 entry (the
# direction the build script actually reasoned in). Rather than building a
# second, mirrored copy of every row (or trying to relabel columns in
# place, which would be error-prone), the lookup functions below simply
# search BOTH the source_code and target_code columns and pick whichever
# column matches the caller's requested `from_version`, then present the
# result under caller-facing `from_code`/`from_label`/... and
# `to_code`/`to_label`/... names so callers never have to know which
# physical column the artifact happened to store which side in. This was
# judged simplest-and-correct per the task's own suggestion, and keeps the
# artifact itself a single, non-duplicated table.

CORRESPONDENCE_DATA_PATH <- "data/psic_2019_to_2026_correspondence.rds"

.correspondence_cache <- new.env(parent = emptyenv())

.correspondence_reset_cache <- function() {
  rm(list = ls(.correspondence_cache), envir = .correspondence_cache)
  invisible(NULL)
}

# Same repo-root-vs-tests/testthat path resolution pattern as
# adapter_psic_2026.R's `.psic2026_resolve_default_path()`.
.correspondence_resolve_default_path <- function(rel_path) {
  candidates <- c(rel_path, file.path("..", "..", rel_path))
  for (p in candidates) {
    if (file.exists(p)) return(p)
  }
  rel_path
}

CORRESPONDENCE_MISSING_ARTIFACT_MSG <-
  "PSIC correspondence runtime artifact is missing. Run scripts/build_psic_correspondence.R and redeploy."

#' Load (and memoize) the built correspondence tibble.
#'
#' @param data_path character or NULL. Override for tests; NULL resolves
#'   the default committed artifact path.
#' @return the full correspondence tibble (see R/correspondence/schema.R).
load_psic_correspondence <- function(data_path = NULL) {
  path <- if (is.null(data_path)) .correspondence_resolve_default_path(CORRESPONDENCE_DATA_PATH) else data_path
  cache_key <- paste0("data::", path)
  cached <- .correspondence_cache[[cache_key]]
  if (!is.null(cached)) return(cached)

  if (!file.exists(path)) {
    stop(CORRESPONDENCE_MISSING_ARTIFACT_MSG, call. = FALSE)
  }
  df <- readRDS(path)
  .correspondence_cache[[cache_key]] <- df
  df
}

# Normalizes a raw correspondence-artifact slice (which uses source_*/
# target_* columns) into caller-facing from_*/to_* columns, given which
# physical column ("source" or "target") actually holds `from_version`'s
# side for each row. `side_is_source` is a logical vector, one entry per
# row of `rows`, TRUE when that row's "source_*" columns are the "from"
# side the caller asked for.
.reshape_from_to <- function(rows, side_is_source, from_version, to_version) {
  if (nrow(rows) == 0L) {
    return(tibble::tibble(
      from_system = character(0), from_version = character(0),
      from_code = character(0), from_level = character(0), from_label = character(0),
      to_system = character(0), to_version = character(0),
      to_code = character(0), to_level = character(0), to_label = character(0),
      relation_type = character(0), provenance = character(0),
      confidence = character(0), confidence_score = double(0),
      method = character(0), evidence = character(0),
      review_status = character(0), notes = character(0)
    ))
  }

  pick <- function(source_col, target_col) {
    ifelse(side_is_source, rows[[source_col]], rows[[target_col]])
  }

  tibble::tibble(
    from_system      = pick("source_system", "target_system"),
    from_version     = pick("source_version", "target_version"),
    from_code        = pick("source_code", "target_code"),
    from_level       = pick("source_level", "target_level"),
    from_label       = pick("source_label", "target_label"),
    to_system        = pick("target_system", "source_system"),
    to_version       = pick("target_version", "source_version"),
    to_code          = pick("target_code", "source_code"),
    to_level         = pick("target_level", "source_level"),
    to_label         = pick("target_label", "source_label"),
    relation_type    = rows$relation_type,
    provenance       = rows$provenance,
    confidence       = rows$confidence,
    confidence_score = rows$confidence_score,
    method           = rows$method,
    evidence         = rows$evidence,
    review_status    = rows$review_status,
    notes            = rows$notes
  )
}

#' Bidirectional lookup of PSIC correspondence rows for one code.
#'
#' @param code character(1). The PSIC code to look up, in `from_version`.
#' @param from_version character(1). "2019" or "2026".
#' @param to_version character(1). The other edition. Must differ from
#'   `from_version`.
#' @param data_path character or NULL. Override for tests.
#'
#' @return A tibble with `from_*`/`to_*` columns (see `.reshape_from_to()`)
#'   plus relation_type/provenance/confidence/confidence_score/method/
#'   evidence/review_status/notes. Zero rows (never NULL, never an error)
#'   if `code` has no correspondence rows in the requested direction.
get_psic_correspondence <- function(code, from_version = "2019", to_version = "2026", data_path = NULL) {
  if (identical(from_version, to_version)) {
    stop("from_version and to_version must differ", call. = FALSE)
  }
  df <- load_psic_correspondence(data_path)

  matches_as_source <- df$source_version == from_version & df$target_version == to_version &
    !is.na(df$source_code) & df$source_code == code
  matches_as_target <- df$target_version == from_version & df$source_version == to_version &
    !is.na(df$target_code) & df$target_code == code

  rows <- rbind(df[matches_as_source, , drop = FALSE], df[matches_as_target, , drop = FALSE])
  side_is_source <- c(rep(TRUE, sum(matches_as_source)), rep(FALSE, sum(matches_as_target)))

  .reshape_from_to(rows, side_is_source, from_version, to_version)
}

#' Search correspondence rows by code or label fragment (case-insensitive,
#' literal substring match -- same discipline as the MVP's literal search).
#'
#' @param query character(1). A code fragment or label fragment.
#' @param from_version,to_version character(1) each. Direction to search.
#' @param limit integer(1). Maximum rows returned.
#' @param data_path character or NULL. Override for tests.
#'
#' @return A tibble in the same from_*/to_* shape as `get_psic_correspondence()`,
#'   up to `limit` rows. Zero rows if nothing matches.
search_psic_correspondence <- function(query, from_version = "2019", to_version = "2026",
                                        limit = 20, data_path = NULL) {
  if (identical(from_version, to_version)) {
    stop("from_version and to_version must differ", call. = FALSE)
  }
  df <- load_psic_correspondence(data_path)
  q <- tolower(query)

  text_hit <- function(x) !is.na(x) & grepl(q, tolower(x), fixed = TRUE)

  as_source <- df$source_version == from_version & df$target_version == to_version &
    (text_hit(df$source_code) | text_hit(df$source_label) | text_hit(df$target_code) | text_hit(df$target_label))
  as_target <- df$target_version == from_version & df$source_version == to_version &
    (text_hit(df$source_code) | text_hit(df$source_label) | text_hit(df$target_code) | text_hit(df$target_label))

  rows <- rbind(df[as_source, , drop = FALSE], df[as_target, , drop = FALSE])
  side_is_source <- c(rep(TRUE, sum(as_source)), rep(FALSE, sum(as_target)))

  out <- .reshape_from_to(rows, side_is_source, from_version, to_version)
  if (nrow(out) > limit) out <- out[seq_len(limit), , drop = FALSE]
  out
}
