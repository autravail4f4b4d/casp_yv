# Canonical classification schema
#
# Every adapter must return a tibble built by `new_classification_tibble()`
# so that downstream repository/search/UI code depends on one stable shape
# regardless of which package or file produced the rows.

CLASSIFICATION_SCHEMA_COLUMNS <- c(
  "system", "version", "level", "code", "label",
  "description", "parent_code", "status", "source", "source_url"
)

#' Build a canonical classification tibble.
#'
#' All columns are coerced to character (never numeric/factor) so that
#' codes with leading zeros are preserved exactly as issued by PSA.
#'
#' @param system character. One of the registry's system ids (e.g. "psic").
#' @param version character. Edition/release identifier (e.g. "2026", "2019").
#' @param level character. Hierarchy level label (e.g. "section", "sub-class").
#' @param code character. Official classification code.
#' @param label character. Human-readable title.
#' @param description character. Optional longer description; NA if unavailable.
#' @param parent_code character. Immediate parent code, or NA at the top level.
#' @param status character. "current" or "archived".
#' @param source character. Issuing authority, normally "Philippine Statistics Authority".
#' @param source_url character. Canonical PSA reference URL for this system/version.
#'
#' @return A tibble with exactly `CLASSIFICATION_SCHEMA_COLUMNS`, all character.
new_classification_tibble <- function(system,
                                       version,
                                       level,
                                       code,
                                       label,
                                       description = NA_character_,
                                       parent_code = NA_character_,
                                       status,
                                       source,
                                       source_url) {
  n <- length(code)
  recycle <- function(x, name) {
    if (length(x) == 1L) rep(x, n)
    else if (length(x) == n) x
    else stop(sprintf("Column '%s' has length %d, expected 1 or %d", name, length(x), n), call. = FALSE)
  }

  out <- tibble::tibble(
    system      = as.character(recycle(system, "system")),
    version     = as.character(recycle(version, "version")),
    level       = as.character(recycle(level, "level")),
    code        = as.character(recycle(code, "code")),
    label       = as.character(recycle(label, "label")),
    description = as.character(recycle(description, "description")),
    parent_code = as.character(recycle(parent_code, "parent_code")),
    status      = as.character(recycle(status, "status")),
    source      = as.character(recycle(source, "source")),
    source_url  = as.character(recycle(source_url, "source_url"))
  )

  validate_classification_tibble(out)
  out
}

#' Validate that a data frame conforms to the canonical classification schema.
#'
#' Throws an error naming the defect. Used by adapters and by tests as a
#' shared contract check.
validate_classification_tibble <- function(df) {
  missing_cols <- setdiff(CLASSIFICATION_SCHEMA_COLUMNS, names(df))
  if (length(missing_cols) > 0) {
    stop(sprintf("Classification data missing required column(s): %s",
                  paste(missing_cols, collapse = ", ")), call. = FALSE)
  }

  non_char <- CLASSIFICATION_SCHEMA_COLUMNS[!vapply(
    df[CLASSIFICATION_SCHEMA_COLUMNS], is.character, logical(1)
  )]
  if (length(non_char) > 0) {
    stop(sprintf("Classification column(s) must be character: %s",
                  paste(non_char, collapse = ", ")), call. = FALSE)
  }

  required_no_na <- c("system", "version", "level", "code", "label", "status", "source")
  for (col in required_no_na) {
    if (anyNA(df[[col]])) {
      stop(sprintf("Classification column '%s' must not contain NA", col), call. = FALSE)
    }
  }

  bad_status <- setdiff(unique(df$status), c("current", "archived"))
  if (length(bad_status) > 0) {
    stop(sprintf("Classification status must be 'current' or 'archived', got: %s",
                  paste(bad_status, collapse = ", ")), call. = FALSE)
  }

  invisible(TRUE)
}
