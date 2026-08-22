# Build-time normalization pipeline for PSIC Revision 5 ("2026 PSIC").
#
# Turns PSA's official detailed-structure workbook into a local runtime
# artifact (data/psic_2026.rds + data/psic_2026_metadata.rds) so the running
# app never depends on PSA network availability and never depends on the
# installed `phscs` package having this edition (it currently tops out at
# the 2019 edition).
#
# Run from the repository root:
#   Rscript scripts/build_psic_2026.R

suppressPackageStartupMessages({
  library(readxl)
  library(tibble)
  library(dplyr)
})

RAW_XLSX_PATH   <- "data-raw/PSIC_Revision_5_Detailed_Structure_30July2026.xlsx"
SOURCE_ARTIFACT_URL <- "https://psa.gov.ph/sites/default/files/scd/PSIC_Revision_5_Detailed_Structure_30July2026.xlsx"
SOURCE_URL      <- "https://psa.gov.ph/classification/psic"
OUT_DATA_PATH   <- "data/psic_2026.rds"
OUT_META_PATH   <- "data/psic_2026_metadata.rds"

LEVEL_COLS   <- c("section", "division", "group", "class", "subclass")
LEVEL_LABELS <- c(section = "section", division = "division", group = "group",
                   class = "class", subclass = "sub-class")

PSA_STATED_COUNTS <- list(sections = 22, divisions = 88, groups = 260,
                           classes = 493, subclasses = 1338)

# ---------------------------------------------------------------------------
# 1. Ensure the raw workbook exists locally (download fallback)
# ---------------------------------------------------------------------------

ensure_workbook <- function(path) {
  if (file.exists(path)) {
    message(sprintf("Using existing local workbook: %s", path))
    return(invisible(path))
  }

  message(sprintf("Local workbook not found at %s -- downloading from PSA...", path))
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)

  resp <- httr2::req_perform(httr2::request(SOURCE_ARTIFACT_URL))
  status <- httr2::resp_status(resp)
  if (status != 200) {
    stop(sprintf(
      "Failed to download PSIC Revision 5 workbook from %s (HTTP %d).",
      SOURCE_ARTIFACT_URL, status
    ), call. = FALSE)
  }

  writeBin(httr2::resp_body_raw(resp), path)

  # Validate the downloaded file is actually a readable xlsx, not an HTML
  # error page or a truncated download.
  sheets <- tryCatch(readxl::excel_sheets(path), error = function(e) NULL)
  if (is.null(sheets) || !"Detailed Structure" %in% sheets) {
    file.remove(path)
    stop(
      "Downloaded file failed validation: not a readable xlsx with a ",
      "'Detailed Structure' sheet. Aborting build.",
      call. = FALSE
    )
  }

  message(sprintf("Downloaded and validated workbook: %s", path))
  invisible(path)
}

# ---------------------------------------------------------------------------
# 2. Parse the "Detailed Structure" sheet into canonical (level, code,
#    label, parent_code) rows.
# ---------------------------------------------------------------------------

parse_psic_workbook <- function(path) {
  sheets <- readxl::excel_sheets(path)
  if (!"Detailed Structure" %in% sheets) {
    stop("Workbook is missing the expected 'Detailed Structure' sheet.", call. = FALSE)
  }

  raw <- readxl::read_excel(
    path,
    sheet = "Detailed Structure",
    col_names = c("section", "division", "group", "class", "subclass", "description"),
    skip = 1,
    col_types = "text"
  )

  if (nrow(raw) == 0) {
    stop("Parsed zero data rows from 'Detailed Structure' -- workbook layout may have changed.",
         call. = FALSE)
  }

  # Trackers for the most recently seen code at each level, in hierarchy order.
  last_seen <- setNames(rep(NA_character_, length(LEVEL_COLS)), LEVEL_COLS)

  out_level      <- character(0)
  out_code       <- character(0)
  out_label      <- character(0)
  out_parent     <- character(0)

  for (i in seq_len(nrow(raw))) {
    row <- raw[i, ]
    desc <- row$description
    if (is.na(desc)) {
      stop(sprintf("Row %d has no description/label text; cannot build a record.", i),
           call. = FALSE)
    }

    # Codes assigned earlier on THIS row take priority as parents over
    # previously-seen codes from earlier rows.
    assigned_this_row <- setNames(rep(NA_character_, length(LEVEL_COLS)), LEVEL_COLS)

    for (li in seq_along(LEVEL_COLS)) {
      lvl_col <- LEVEL_COLS[li]
      code_val <- row[[lvl_col]]
      if (is.na(code_val)) next

      parent_code <- NA_character_
      if (li > 1) {
        # Look for the nearest populated ancestor level, preferring a code
        # assigned earlier on this same row over the historical last-seen.
        for (pj in seq(li - 1, 1)) {
          parent_level <- LEVEL_COLS[pj]
          if (!is.na(assigned_this_row[[parent_level]])) {
            parent_code <- assigned_this_row[[parent_level]]
            break
          }
          if (!is.na(last_seen[[parent_level]])) {
            parent_code <- last_seen[[parent_level]]
            break
          }
        }
      }

      out_level  <- c(out_level, LEVEL_LABELS[[lvl_col]])
      out_code   <- c(out_code, code_val)
      out_label  <- c(out_label, desc)
      out_parent <- c(out_parent, parent_code)

      assigned_this_row[[lvl_col]] <- code_val
      last_seen[[lvl_col]] <- code_val
    }
  }

  tibble::tibble(
    level = out_level,
    code = out_code,
    label = out_label,
    parent_code = out_parent
  )
}

# ---------------------------------------------------------------------------
# 3. Validate parsed structural counts against PSA's officially stated counts
# ---------------------------------------------------------------------------

validate_counts <- function(parsed) {
  counts <- list(
    sections  = sum(parsed$level == "section"),
    divisions = sum(parsed$level == "division"),
    groups    = sum(parsed$level == "group"),
    classes   = sum(parsed$level == "class"),
    subclasses = sum(parsed$level == "sub-class")
  )

  report_line <- function(name, parsed_n, stated_n) {
    status <- if (isTRUE(parsed_n == stated_n)) "PASS" else "WARN (documented discrepancy)"
    sprintf("  %-10s parsed=%-5d stated=%-5d %s", name, parsed_n, stated_n, status)
  }

  message("PSIC Revision 5 structural validation:")
  message(report_line("sections",   counts$sections,   PSA_STATED_COUNTS$sections))
  message(report_line("divisions",  counts$divisions,  PSA_STATED_COUNTS$divisions))
  message(report_line("groups",     counts$groups,     PSA_STATED_COUNTS$groups))
  message(report_line("classes",    counts$classes,    PSA_STATED_COUNTS$classes))
  message(report_line("subclasses", counts$subclasses, PSA_STATED_COUNTS$subclasses))

  if (counts$groups != PSA_STATED_COUNTS$groups) {
    message(sprintf(
      paste0(
        "  NOTE: parsed groups count (%d) differs from PSA's officially stated ",
        "count (%d). This is a known, documented discrepancy -- see ",
        "docs/DATA_SOURCES.md. Not fabricating or dropping rows to force a match."
      ),
      counts$groups, PSA_STATED_COUNTS$groups
    ))
  }

  # Hard-fail only on counts that should be exact and are not documented as
  # ambiguous. If these drift, the parse itself is likely broken.
  hard_checks <- list(
    sections = "sections", divisions = "divisions",
    classes = "classes", subclasses = "subclasses"
  )
  for (nm in names(hard_checks)) {
    if (counts[[nm]] != PSA_STATED_COUNTS[[nm]]) {
      stop(sprintf(
        "Parsed %s count (%d) does not match PSA's stated count (%d) and this is not a documented exception. Aborting build.",
        nm, counts[[nm]], PSA_STATED_COUNTS[[nm]]
      ), call. = FALSE)
    }
  }

  counts
}

# ---------------------------------------------------------------------------
# 4. Main
# ---------------------------------------------------------------------------

main <- function() {
  ensure_workbook(RAW_XLSX_PATH)

  parsed <- parse_psic_workbook(RAW_XLSX_PATH)
  message(sprintf("Parsed %d canonical records from %d workbook rows.",
                   nrow(parsed), 1791))

  counts <- validate_counts(parsed)

  # Spot-check the known "Veterinary activities" collapsed-row case.
  vet <- parsed[parsed$label == "Veterinary activities" & parsed$level %in% c("division", "group", "class", "sub-class"), ]
  if (!all(c("75", "750", "7500", "75000") %in% vet$code)) {
    stop("Sanity check failed: expected Veterinary activities codes 75/750/7500/75000 not all found.",
         call. = FALSE)
  }

  canonical <- new_classification_tibble(
    system      = "psic",
    version     = "2026",
    level       = parsed$level,
    code        = parsed$code,
    label       = parsed$label,
    description = NA_character_,
    parent_code = parsed$parent_code,
    status      = "current",
    source      = "Philippine Statistics Authority",
    source_url  = SOURCE_URL
  )

  dir.create(dirname(OUT_DATA_PATH), recursive = TRUE, showWarnings = FALSE)
  saveRDS(canonical, OUT_DATA_PATH)
  message(sprintf("Saved canonical tibble (%d rows) to %s", nrow(canonical), OUT_DATA_PATH))

  sha256 <- digest::digest(file = RAW_XLSX_PATH, algo = "sha256")

  metadata <- list(
    system = "psic",
    version = "2026",
    display_version = "PSIC Revision 5 (2026)",
    status = "current",
    source = "Philippine Statistics Authority",
    source_url = SOURCE_URL,
    source_artifact_url = SOURCE_ARTIFACT_URL,
    retrieved_at = "2026-08-23",
    sha256 = sha256,
    license = "CC BY 4.0 unless otherwise stated by PSA",
    parsed_counts = list(
      sections = counts$sections,
      divisions = counts$divisions,
      groups = counts$groups,
      classes = counts$classes,
      subclasses = counts$subclasses
    ),
    psa_stated_counts = PSA_STATED_COUNTS
  )

  saveRDS(metadata, OUT_META_PATH)
  message(sprintf("Saved metadata to %s", OUT_META_PATH))
  message("Build complete.")

  invisible(list(canonical = canonical, metadata = metadata))
}

if (identical(environment(), globalenv())) {
  # Source schema.R directly since this script may be run standalone (not
  # via testthat's helper, which sources all of R/ automatically).
  if (!exists("new_classification_tibble")) {
    source("R/schema.R")
  }
  main()
}
