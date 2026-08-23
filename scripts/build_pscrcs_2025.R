# Build-time normalization pipeline for the Philippine Standard Creative
# Classification System (PSCrCS), 2025.
#
# Source: official PSA workbook, linked from
#   https://psa.gov.ph/classification/pscrcs/
#   https://psa.gov.ph/content/psa-releases-philippine-standard-creative-classification-system
# Kept unmodified at data-raw/PSCrCS_classification.xlsx. This script never
# writes to data-raw/ and never reaches the network; the Shiny app reads only
# the normalized runtime artifacts produced here.
#
# WORKBOOK STRUCTURE (verified by direct inspection, not assumed)
# -----------------------------------------------------------------
# 4 sheets:
#
#   "Metadata"               16 x 2, a label/value block (Title, Originator,
#                            Publication date, Abstract, Process, ...). The
#                            "Process" entry is the authoritative statement of
#                            both the underlying classifications and the
#                            official component counts; it is captured verbatim
#                            into the metadata artifact as evidence.
#
#   "Creative Industries"    318 physical rows = 1 title row + 317 records
#   "Creative Goods and Ser" 410 physical rows = 1 title row + 409 records
#   "Creative Occupations"   115 physical rows = 1 title row + 114 records
#
# Each data sheet has exactly 2 columns and NO header row of its own: physical
# row 1 is a merged-looking *title* row (column 1 holds e.g.
# "Creative Industries\r\n(2019 Updates to the 2009 PSIC)", column 2 is blank).
# read_excel()'s default header handling consumes that title row as the column
# names, which is why a plain read lands on exactly 317/409/114 data rows --
# matching PSA's official counts. This script therefore reads with default
# headers and re-names the two columns positionally rather than skipping rows.
#
#   column 1 = CODE   fixed-width, all-digit strings: 5 chars for industries
#                     (PSIC sub-class), 5 chars for goods/services (CPC
#                     sub-class), 4 chars for occupations (PSOC unit group).
#   column 2 = LABEL  free text, 4-414 characters.
#
# The code/label roles were identified from that width and content profile, not
# guessed: column 1 is 100% fixed-width digits with no spaces, column 2 is
# variable-length prose. Both columns are fully populated (no NA, no blanks) on
# every data row of every sheet.
#
# NO HIERARCHY, NO DOMAIN/CATEGORY COLUMN
# -----------------------------------------------------------------
# The workbook provides two columns and nothing else: there is no parent code,
# no level marker, and no creative-domain / major-category column. Per spec
# section 6 ("Do not manufacture a hierarchy that the source file does not
# provide") this build does NOT synthesize one. Consequently:
#   - `level`       = the component id (a flat, honest partition of the file)
#   - `parent_code` = NA for every record
#   - `major_category` = NA for every record (nothing in the source to fill it)
# If PSA later publishes a PSCrCS file carrying creative-domain groupings, that
# column should be mapped onto `major_category` here.
#
# CODES ARE NOT NEW PSCrCS CODES
# -----------------------------------------------------------------
# PSCrCS does not mint its own code system. Each record's code is the code of
# an underlying classification, and that provenance is part of the statistical
# meaning (spec sections 1.3 / 6). It is carried explicitly:
#
#   creative_industry      -> psic 2019   (2019 Updates to the 2009 PSIC)
#   creative_good_service  -> cpc  2.1    (Central Product Classification 2.1)
#   creative_occupation    -> psoc 2022   (2022 Updates to the 2012 PSOC)
#
# The industry component is 2019 PSIC and MUST NOT be silently re-labelled as
# PSIC 2026 / Revision 5 just because this application also ships PSIC
# Revision 5 (explicit prohibition, spec sections 1.3 and 13).
#
# CANONICAL SCHEMA IS FROZEN
# -----------------------------------------------------------------
# R/schema.R's CLASSIFICATION_SCHEMA_COLUMNS is shared with every other
# classification system and is not widened for this composite one. The five
# composite-provenance fields are appended AFTER the 10 canonical columns, so
# `names(df)[1:10]` is still exactly CLASSIFICATION_SCHEMA_COLUMNS in order.
#
# Run from the repository root:
#   Rscript scripts/build_pscrcs_2025.R

suppressPackageStartupMessages({
  library(readxl)
  library(dplyr)
  library(tibble)
})

RAW_PATH <- "data-raw/PSCrCS_classification.xlsx"
RAW_FILENAME <- basename(RAW_PATH)
OFFICIAL_SOURCE_PAGE <- "https://psa.gov.ph/classification/pscrcs/"
OFFICIAL_RELEASE_URL <- "https://psa.gov.ph/content/psa-releases-philippine-standard-creative-classification-system"
OUT_DATA_PATH <- "data/pscrcs_2025.rds"
OUT_META_PATH <- "data/pscrcs_2025_metadata.rds"

METADATA_SHEET <- "Metadata"

# Component contract. Order here is the canonical component order used by the
# adapter and by the validation report.
COMPONENTS <- list(
  list(
    component      = "creative_industry",
    sheet          = "Creative Industries",
    label          = "Creative Industries",
    source_system  = "psic",
    source_version = "2019",
    source_label   = "2019 Updates to the 2009 PSIC",
    code_width     = 5L,
    official_count = 317L
  ),
  list(
    component      = "creative_good_service",
    sheet          = "Creative Goods and Ser",
    label          = "Creative Goods and Services",
    source_system  = "cpc",
    source_version = "2.1",
    source_label   = "Central Product Classification (CPC) Version 2.1",
    code_width     = 5L,
    official_count = 409L
  ),
  list(
    component      = "creative_occupation",
    sheet          = "Creative Occupations",
    label          = "Creative Occupations",
    source_system  = "psoc",
    source_version = "2022",
    source_label   = "2022 Updates to the 2012 PSOC",
    code_width     = 4L,
    official_count = 114L
  )
)

if (!file.exists(RAW_PATH)) {
  stop(sprintf(
    "Missing raw PSCrCS workbook at '%s'. Download it from %s and place it there; this script does not fetch it.",
    RAW_PATH, OFFICIAL_SOURCE_PAGE
  ), call. = FALSE)
}

sheets <- excel_sheets(RAW_PATH)
expected_sheets <- c(METADATA_SHEET, vapply(COMPONENTS, `[[`, character(1), "sheet"))
missing_sheets <- setdiff(expected_sheets, sheets)
if (length(missing_sheets) > 0) {
  stop(sprintf(
    "PSCrCS workbook is missing expected sheet(s): %s. Found: %s",
    paste(missing_sheets, collapse = ", "), paste(sheets, collapse = ", ")
  ), call. = FALSE)
}

# ---------------------------------------------------------------------------
# Metadata sheet -- captured verbatim as provenance evidence.
# ---------------------------------------------------------------------------
read_metadata_sheet <- function(path) {
  md <- suppressMessages(read_excel(
    path, sheet = METADATA_SHEET, col_types = "text", col_names = FALSE
  ))
  if (ncol(md) < 2) {
    stop("PSCrCS Metadata sheet does not have the expected label/value column pair.", call. = FALSE)
  }
  keys <- trimws(gsub(":$", "", trimws(md[[1]])))
  vals <- md[[2]]
  keep <- !is.na(keys) & nzchar(keys)
  out <- as.list(vals[keep])
  names(out) <- keys[keep]
  out
}

workbook_metadata <- read_metadata_sheet(RAW_PATH)

cat("PSCrCS workbook Metadata sheet\n")
cat("------------------------------\n")
for (k in c("Title", "Originator", "Publication date")) {
  if (!is.null(workbook_metadata[[k]])) {
    cat(sprintf("  %-18s %s\n", paste0(k, ":"), workbook_metadata[[k]]))
  }
}
cat("\n")

# ---------------------------------------------------------------------------
# Data sheets.
# ---------------------------------------------------------------------------
parse_component_sheet <- function(path, spec) {
  # Default header handling deliberately consumes physical row 1 (the sheet's
  # title row) -- see the structure notes in this file's header.
  raw <- suppressMessages(read_excel(path, sheet = spec$sheet, col_types = "text"))

  if (ncol(raw) < 2) {
    stop(sprintf(
      "PSCrCS sheet '%s' has %d column(s); expected at least 2 (code, label).",
      spec$sheet, ncol(raw)
    ), call. = FALSE)
  }

  df <- tibble(
    code  = trimws(raw[[1]]),
    label = trimws(gsub("[\r\n]+", " ", raw[[2]]))
  )
  df$code <- ifelse(is.na(df$code) | !nzchar(df$code), NA_character_, df$code)
  df$label <- ifelse(is.na(df$label) | !nzchar(df$label), NA_character_, df$label)

  # Drop fully-blank trailing rows only; anything half-populated is a defect
  # we must surface rather than quietly discard.
  df <- df[!(is.na(df$code) & is.na(df$label)), , drop = FALSE]

  if (nrow(df) == 0L) {
    stop(sprintf("PSCrCS sheet '%s' parsed to zero rows.", spec$sheet), call. = FALSE)
  }
  if (anyNA(df$code)) {
    stop(sprintf(
      "PSCrCS sheet '%s': %d row(s) have a label but no code -- cannot honestly classify them.",
      spec$sheet, sum(is.na(df$code))
    ), call. = FALSE)
  }
  if (anyNA(df$label)) {
    stop(sprintf(
      "PSCrCS sheet '%s': %d row(s) have a code but no label -- cannot honestly label them.",
      spec$sheet, sum(is.na(df$label))
    ), call. = FALSE)
  }
  if (!is.character(df$code)) {
    stop(sprintf("PSCrCS sheet '%s': code column is not character.", spec$sheet), call. = FALSE)
  }

  # Width check: catches an accidental numeric coercion upstream (which would
  # strip any leading zero) and catches misaligned columns.
  bad_width <- df$code[nchar(df$code) != spec$code_width]
  if (length(bad_width) > 0) {
    stop(sprintf(
      "PSCrCS sheet '%s': %d code(s) are not %d characters wide (e.g. %s). Codes must be preserved verbatim as strings.",
      spec$sheet, length(bad_width), spec$code_width,
      paste(utils::head(bad_width, 5), collapse = ", ")
    ), call. = FALSE)
  }

  dup <- df$code[duplicated(df$code)]
  if (length(dup) > 0) {
    stop(sprintf(
      "PSCrCS sheet '%s': duplicate code(s) within the component: %s",
      spec$sheet, paste(unique(dup), collapse = ", ")
    ), call. = FALSE)
  }

  df$component      <- spec$component
  df$source_system  <- spec$source_system
  df$source_version <- spec$source_version
  df
}

parsed <- lapply(COMPONENTS, function(spec) parse_component_sheet(RAW_PATH, spec))
names(parsed) <- vapply(COMPONENTS, `[[`, character(1), "component")
all_rows <- bind_rows(parsed)

# ---------------------------------------------------------------------------
# Validation report.
# ---------------------------------------------------------------------------
parsed_counts <- lapply(parsed, nrow)
official_counts <- lapply(COMPONENTS, function(s) s$official_count)
names(official_counts) <- names(parsed)

cat("PSCrCS 2025 parsed counts vs. official PSA counts\n")
cat("------------------------------------------------\n")
count_mismatch <- FALSE
for (nm in names(parsed_counts)) {
  p <- parsed_counts[[nm]]
  o <- official_counts[[nm]]
  ok <- identical(as.integer(p), as.integer(o))
  if (!ok) count_mismatch <- TRUE
  cat(sprintf("  %-22s parsed=%-5d official=%-5d [%s]\n",
              nm, p, o, if (ok) "OK" else "MISMATCH"))
}
cat(sprintf("  %-22s parsed=%-5d official=%-5d\n", "TOTAL",
            nrow(all_rows), sum(unlist(official_counts))))

if (count_mismatch) {
  # Follows the convention of scripts/build_psic_2026.R / build_psoc_2022.R:
  # warn loudly and record the discrepancy rather than fabricating or dropping
  # rows to hit a target.
  warning(
    "PSCrCS parsed component counts do not match PSA's official 317/409/114. ",
    "The workbook, not the target, is the thing to investigate (check for an ",
    "extra title row or blank rows). No rows have been added or dropped to force a match.",
    call. = FALSE
  )
}

leading_zero_codes <- sum(grepl("^0", all_rows$code))
cat(sprintf("\nCodes beginning with '0' (leading-zero preservation check): %d\n", leading_zero_codes))
cat(sprintf("Code column type: %s\n", class(all_rows$code)[1]))
if (leading_zero_codes == 0L) {
  cat("  NOTE: this workbook happens to contain no leading-zero codes. Codes are\n")
  cat("        still read and stored as text (col_types = \"text\") and their exact\n")
  cat("        widths are asserted, so a future leading-zero code would survive.\n")
}

dup_within <- sum(duplicated(all_rows[, c("component", "code")]))
dup_across <- sum(duplicated(all_rows$code))
cat(sprintf("\nDuplicate (component, code) pairs: %d  [must be 0]\n", dup_within))
cat(sprintf("Codes reused across components:    %d\n", dup_across))
if (dup_within > 0) {
  stop("PSCrCS: duplicate (component, code) pairs found -- refusing to save.", call. = FALSE)
}
if (dup_across > 0) {
  overlap <- unique(all_rows$code[duplicated(all_rows$code)])
  cat(sprintf("  Expected and legitimate: PSIC and CPC are independent code systems,\n"))
  cat(sprintf("  so the same digit string can exist in both. Overlapping codes: %s\n",
              paste(overlap, collapse = ", ")))
}

cat("\nComponent provenance\n")
cat("--------------------\n")
for (spec in COMPONENTS) {
  cat(sprintf("  %-22s <- %s %s (%s)\n",
              spec$component, toupper(spec$source_system), spec$source_version, spec$source_label))
}

# ---------------------------------------------------------------------------
# Canonical tibble (10 frozen columns) + appended composite provenance.
# ---------------------------------------------------------------------------
source("R/schema.R")

canonical <- new_classification_tibble(
  system      = "pscrcs",
  version     = "2025",
  # No hierarchy exists in the source file, so `level` carries the component
  # partition rather than a manufactured depth. See header notes.
  level       = all_rows$component,
  code        = all_rows$code,
  label       = all_rows$label,
  description = NA_character_,
  parent_code = NA_character_,
  status      = "current",
  source      = "Philippine Statistics Authority",
  source_url  = OFFICIAL_SOURCE_PAGE
)

stopifnot(identical(names(canonical), CLASSIFICATION_SCHEMA_COLUMNS))

PSCRCS_EXTRA_COLUMNS <- c(
  "component", "major_category", "source_system", "source_version", "source_code"
)

canonical <- bind_cols(
  canonical,
  tibble(
    component      = all_rows$component,
    # Nothing in the source workbook carries a creative domain / major
    # category. Left NA rather than invented (spec section 6).
    major_category = NA_character_,
    source_system  = all_rows$source_system,
    source_version = all_rows$source_version,
    # The code as issued by the underlying classification. Identical to `code`
    # because PSCrCS reuses the underlying codes verbatim; kept as a distinct
    # field so downstream consumers never have to infer that.
    source_code    = all_rows$code
  )
)

stopifnot(identical(names(canonical)[seq_along(CLASSIFICATION_SCHEMA_COLUMNS)],
                    CLASSIFICATION_SCHEMA_COLUMNS))
stopifnot(identical(names(canonical)[-seq_along(CLASSIFICATION_SCHEMA_COLUMNS)],
                    PSCRCS_EXTRA_COLUMNS))
validate_classification_tibble(canonical)

# Guard the explicit prohibition at build time, not just in tests.
industry_versions <- unique(canonical$source_version[canonical$component == "creative_industry"])
if (!identical(industry_versions, "2019")) {
  stop(sprintf(
    "PSCrCS creative_industry component must retain 2019 PSIC provenance, got: %s",
    paste(industry_versions, collapse = ", ")
  ), call. = FALSE)
}

sha256 <- digest::digest(file = RAW_PATH, algo = "sha256")

metadata <- list(
  system            = "pscrcs",
  version           = "2025",
  display_version   = "2025 Philippine Standard Creative Classification System (PSCrCS)",
  official_name     = "Philippine Standard Creative Classification System (PSCrCS)",
  status            = "current",
  adopted           = "2025",
  source            = "Philippine Statistics Authority",
  source_url        = OFFICIAL_SOURCE_PAGE,
  release_url       = OFFICIAL_RELEASE_URL,
  # Filename only -- never an absolute local path (spec section 18).
  source_artifact   = RAW_FILENAME,
  retrieval_method  = "manual download by user from the official PSA classification page; this build does not fetch over the network",
  retrieved_at      = as.character(Sys.Date()),
  sha256            = sha256,
  license           = "CC BY 4.0 unless otherwise stated by PSA",
  components        = names(parsed),
  parsed_counts     = parsed_counts,
  official_counts   = official_counts,
  counts_match      = !count_mismatch,
  leading_zero_code_count = leading_zero_codes,
  hierarchy         = "none - the source workbook provides no parent/level structure; `level` carries the component id and `parent_code` is NA for every record",
  major_category_available = FALSE,
  extra_columns     = PSCRCS_EXTRA_COLUMNS,
  underlying_classifications = lapply(COMPONENTS, function(s) list(
    component      = s$component,
    source_system  = s$source_system,
    source_version = s$source_version,
    source_label   = s$source_label
  )),
  workbook_metadata = workbook_metadata
)
names(metadata$underlying_classifications) <- names(parsed)

saveRDS(canonical, OUT_DATA_PATH)
saveRDS(metadata, OUT_META_PATH)

cat(sprintf("\nSaved %d canonical rows (%d columns) to %s\n",
            nrow(canonical), ncol(canonical), OUT_DATA_PATH))
cat(sprintf("Saved metadata to %s (sha256=%s)\n", OUT_META_PATH, sha256))
