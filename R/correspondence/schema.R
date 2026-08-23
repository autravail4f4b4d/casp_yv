# Canonical correspondence ("crosswalk") schema for PSIC 2019 <-> PSIC
# Revision 5 (2026).
#
# This is a *relationship*-shaped table, deliberately separate from
# `CLASSIFICATION_SCHEMA_COLUMNS` in R/schema.R (which describes a single
# classification edition's own hierarchy). A correspondence row instead
# describes a directed edge between one source-edition entry and one
# target-edition entry (or a one-sided "new"/"discontinued" placeholder
# when there is no counterpart), together with explicit provenance,
# confidence, and human-readable justification.
#
# See docs/CORRESPONDENCE_SOURCES.md for the source audit that determined
# no official PSA PSIC 2019<->Revision 5 crosswalk exists yet, and for the
# scoring thresholds referenced by R/correspondence/scoring.R.

CORRESPONDENCE_SCHEMA_COLUMNS <- c(
  "source_system", "source_version", "source_code", "source_level", "source_label",
  "target_system", "target_version", "target_code", "target_level", "target_label",
  "relation_type", "provenance", "confidence", "confidence_score",
  "method", "evidence", "review_status", "notes"
)

#' Allowed `relation_type` values.
#'
#' Not every value needs to appear in a given built artifact -- these are
#' the vocabulary the schema accepts, not a checklist that must be fully
#' exercised.
CORRESPONDENCE_RELATION_TYPES <- c(
  "unchanged", "renamed", "split", "merged", "reclassified",
  "new", "discontinued", "complex", "possible", "unknown"
)

#' Allowed `provenance` values.
#'
#' "official" must never be produced by this codebase's own deterministic
#' matching logic -- it is reserved for a row whose specific mapping was
#' found named in a genuine PSA-published document during the source audit.
#' See docs/CORRESPONDENCE_SOURCES.md. As of this build, no such document
#' exists, so no row in the shipped artifact carries "official".
CORRESPONDENCE_PROVENANCE_VALUES <- c("official", "derived", "suggested")

#' Allowed `confidence` values (ordinal bucket, not a calibrated probability).
CORRESPONDENCE_CONFIDENCE_VALUES <- c("high", "moderate", "low")

#' Allowed `review_status` values.
CORRESPONDENCE_REVIEW_STATUS_VALUES <- c("auto", "reviewed", "needs_review")

#' Required public statistical-safety warning (spec section 19, verbatim).
#'
#' Reused by the UI/docs so the wording is never re-typed or drifted.
CORRESPONDENCE_STATISTICAL_WARNING <- paste(
  "Classification correspondence identifies related categories across",
  "editions. It does not provide a basis for automatically reallocating",
  "historical statistical values among revised categories."
)

#' Build a canonical correspondence tibble.
#'
#' All columns are coerced to character except `confidence_score` (double),
#' mirroring the discipline in `R/schema.R`'s `new_classification_tibble()`:
#' codes must never silently become numeric.
#'
#' A "discontinued" (1->0) row has no target: `target_code`/`target_label`
#' (and typically `target_system`/`target_version`/`target_level`) may be
#' NA. A "new" (0->1) row symmetrically has no source: `source_code`/
#' `source_label` (and typically `source_system`/`source_version`/
#' `source_level`) may be NA. Every other relation_type requires both
#' sides to be present.
#'
#' @return A tibble with exactly `CORRESPONDENCE_SCHEMA_COLUMNS`.
new_correspondence_tibble <- function(source_system = NA_character_,
                                       source_version = NA_character_,
                                       source_code = NA_character_,
                                       source_level = NA_character_,
                                       source_label = NA_character_,
                                       target_system = NA_character_,
                                       target_version = NA_character_,
                                       target_code = NA_character_,
                                       target_level = NA_character_,
                                       target_label = NA_character_,
                                       relation_type,
                                       provenance,
                                       confidence,
                                       confidence_score = NA_real_,
                                       method = NA_character_,
                                       evidence = NA_character_,
                                       review_status = "auto",
                                       notes = NA_character_) {
  n <- length(relation_type)
  recycle_chr <- function(x, name) {
    if (length(x) == 1L) rep(as.character(x), n)
    else if (length(x) == n) as.character(x)
    else stop(sprintf("Column '%s' has length %d, expected 1 or %d", name, length(x), n), call. = FALSE)
  }
  recycle_dbl <- function(x, name) {
    if (length(x) == 1L) rep(as.double(x), n)
    else if (length(x) == n) as.double(x)
    else stop(sprintf("Column '%s' has length %d, expected 1 or %d", name, length(x), n), call. = FALSE)
  }

  out <- tibble::tibble(
    source_system    = recycle_chr(source_system, "source_system"),
    source_version   = recycle_chr(source_version, "source_version"),
    source_code      = recycle_chr(source_code, "source_code"),
    source_level     = recycle_chr(source_level, "source_level"),
    source_label     = recycle_chr(source_label, "source_label"),
    target_system    = recycle_chr(target_system, "target_system"),
    target_version   = recycle_chr(target_version, "target_version"),
    target_code      = recycle_chr(target_code, "target_code"),
    target_level     = recycle_chr(target_level, "target_level"),
    target_label     = recycle_chr(target_label, "target_label"),
    relation_type    = recycle_chr(relation_type, "relation_type"),
    provenance       = recycle_chr(provenance, "provenance"),
    confidence       = recycle_chr(confidence, "confidence"),
    confidence_score = recycle_dbl(confidence_score, "confidence_score"),
    method           = recycle_chr(method, "method"),
    evidence         = recycle_chr(evidence, "evidence"),
    review_status    = recycle_chr(review_status, "review_status"),
    notes            = recycle_chr(notes, "notes")
  )

  validate_correspondence_tibble(out)
  out
}

#' Validate that a data frame conforms to the canonical correspondence schema.
#'
#' Throws an error naming the defect. Used by the build script and by tests
#' as a shared contract check.
validate_correspondence_tibble <- function(df) {
  missing_cols <- setdiff(CORRESPONDENCE_SCHEMA_COLUMNS, names(df))
  if (length(missing_cols) > 0) {
    stop(sprintf("Correspondence data missing required column(s): %s",
                  paste(missing_cols, collapse = ", ")), call. = FALSE)
  }

  char_cols <- setdiff(CORRESPONDENCE_SCHEMA_COLUMNS, "confidence_score")
  non_char <- char_cols[!vapply(df[char_cols], is.character, logical(1))]
  if (length(non_char) > 0) {
    stop(sprintf("Correspondence column(s) must be character: %s",
                  paste(non_char, collapse = ", ")), call. = FALSE)
  }
  if (!is.double(df$confidence_score) && !is.numeric(df$confidence_score)) {
    stop("Correspondence column 'confidence_score' must be numeric (double)", call. = FALSE)
  }

  # Columns that may never be NA regardless of relation_type.
  always_required <- c(
    "source_system", "source_version", "target_system", "target_version",
    "relation_type", "provenance", "confidence", "review_status"
  )
  # source_system/source_version are still recorded even on a "new" (0->1)
  # row (they name which edition is being compared *against*), so only
  # source_code/source_label are allowed NA there; symmetrically only
  # target_code/target_label are allowed NA on a "discontinued" row.
  is_new <- df$relation_type == "new"
  is_discontinued <- df$relation_type == "discontinued"

  for (col in always_required) {
    if (anyNA(df[[col]])) {
      stop(sprintf("Correspondence column '%s' must not contain NA", col), call. = FALSE)
    }
  }

  bad_source_na <- !is_new & (is.na(df$source_code) | is.na(df$source_level) | is.na(df$source_label))
  if (any(bad_source_na)) {
    stop("Correspondence rows with relation_type != 'new' must have non-NA source_code/source_level/source_label", call. = FALSE)
  }
  bad_target_na <- !is_discontinued & (is.na(df$target_code) | is.na(df$target_level) | is.na(df$target_label))
  if (any(bad_target_na)) {
    stop("Correspondence rows with relation_type != 'discontinued' must have non-NA target_code/target_level/target_label", call. = FALSE)
  }

  bad_relation <- setdiff(unique(df$relation_type), CORRESPONDENCE_RELATION_TYPES)
  if (length(bad_relation) > 0) {
    stop(sprintf("Correspondence relation_type must be one of: %s. Got invalid: %s",
                  paste(CORRESPONDENCE_RELATION_TYPES, collapse = ", "),
                  paste(bad_relation, collapse = ", ")), call. = FALSE)
  }

  bad_provenance <- setdiff(unique(df$provenance), CORRESPONDENCE_PROVENANCE_VALUES)
  if (length(bad_provenance) > 0) {
    stop(sprintf("Correspondence provenance must be one of: %s. Got invalid: %s",
                  paste(CORRESPONDENCE_PROVENANCE_VALUES, collapse = ", "),
                  paste(bad_provenance, collapse = ", ")), call. = FALSE)
  }

  bad_confidence <- setdiff(unique(df$confidence), CORRESPONDENCE_CONFIDENCE_VALUES)
  if (length(bad_confidence) > 0) {
    stop(sprintf("Correspondence confidence must be one of: %s. Got invalid: %s",
                  paste(CORRESPONDENCE_CONFIDENCE_VALUES, collapse = ", "),
                  paste(bad_confidence, collapse = ", ")), call. = FALSE)
  }

  bad_review <- setdiff(unique(df$review_status), CORRESPONDENCE_REVIEW_STATUS_VALUES)
  if (length(bad_review) > 0) {
    stop(sprintf("Correspondence review_status must be one of: %s. Got invalid: %s",
                  paste(CORRESPONDENCE_REVIEW_STATUS_VALUES, collapse = ", "),
                  paste(bad_review, collapse = ", ")), call. = FALSE)
  }

  invisible(TRUE)
}
