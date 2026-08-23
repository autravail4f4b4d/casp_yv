# Build-time normalization pipeline for the
# "2025 Philippine Tourism Statistical Classification System (PTSCS),
#  Version 2.1".
#
# Source: official PSA workbook, linked from
#   https://psa.gov.ph/classification/ptscs
# Local raw copy (never modified in place):
#   data-raw/PTSCS-Version-2.1.xlsx
#
# This script does NOT attempt any network retrieval; the workbook must
# already be present. Runtime search reads only the local .rds artifacts
# produced here.
#
# WORKBOOK STRUCTURE (verified by direct inspection, not assumed)
# -----------------------------------------------------------------
# 3 sheets:
#   "Metadata"                 15 label/value rows of official provenance
#                              (title, originator, publication date, abstract,
#                              process -- the "Process" row is where PSA states
#                              the 176 / 214 coverage figures and the
#                              underlying 2019 PSIC / CPC 2.1 alignment)
#   "2025 Tourism Industries"  196 rows x 3 cols
#   "2025 Tourism Products"    236 rows x 3 cols
#
# Both data sheets share one layout:
#   row 1      sheet title, in column 1 only
#              ("List of Tourism Industries (Tourism Characteristic Activities)"
#               / "List of Tourism Characteristic Products")
#   row 2      blank spacer
#   row 3      COLUMN HEADER row -- the only row with text in both col 1 and
#              col 2. Industries: "Tourism Major Categories" |
#              "2019 Updates to the 2009 PSIC (5-Digit Code)" | "Description".
#              Products:   "Tourism Major Products" | "CPC 2.1" | "Description".
#              This header row is the workbook's own statement of which
#              classification supplies the codes, and is recorded verbatim in
#              the metadata artifact as evidence.
#   row 4      blank spacer
#   rows 5+    an interleaving of
#                (a) THEMATIC CATEGORY HEADING rows: text in col 1 only,
#                    numbered, e.g. "1. Accommodation for Visitors",
#                    "12.1. Other Retail Trade Service Activities"; and
#                (b) DATA rows: col 1 blank, col 2 = the underlying 5-digit
#                    source code, col 3 = the official label.
#
# ROW ACCOUNTING -- why the sheets are "larger" than the official counts
# -----------------------------------------------------------------
# PSA officially states 176 tourism industries and 214 tourism characteristic
# products. The sheets are 195 and 235 rows once the title row is consumed as
# a header by a naive read (196 / 236 raw). Every single extra row is
# accounted for structurally -- none is a duplicate, a footnote, or junk:
#
#   Industries  176 data + 16 category headings + 1 column-header row
#                   + 2 blank spacers + 1 sheet-title row = 196 raw
#   Products    214 data + 18 category headings + 1 column-header row
#                   + 2 blank spacers + 1 sheet-title row = 236 raw
#
# So the parsed data-row counts land EXACTLY on the official 176 / 214. The
# "discrepancy" was entirely thematic category structure plus sheet
# furniture. The category headings are real PTSCS structure and are
# preserved as `major_category` / `major_category_group` metadata on their
# child rows (see below) rather than discarded.
#
# CATEGORY HEADINGS ARE NOT EMITTED AS CLASSIFICATION RECORDS
# -----------------------------------------------------------------
# The headings carry no official code of their own -- only a presentational
# ordinal ("1.", "12.3."). Emitting them as classification records would
# require inventing a code, which this project forbids. They are therefore
# carried as first-class metadata columns on the records they govern, and
# the full ordered list is recorded in the metadata artifact.
#
# Two heading depths exist and both are preserved:
#   `major_category`        the most specific heading governing the row
#                           (e.g. "12.3. Education, Health and Personal
#                           Service Activities")
#   `major_category_group`  the top-level numbered heading it sits under
#                           (e.g. "12. Country-specific Tourism
#                           Characteristic Activities"); identical to
#                           `major_category` for headings that have no
#                           sub-headings.
# Heading text is preserved VERBATIM, including PSA's ordinal prefix and
# PSA's own inconsistent punctuation (the products sheet writes
# "10 - Sports and Recreational Services" where every other heading uses
# "N. Title"). Normalizing that away would misrepresent the source.
#
# PTSCS IS NOT A HIERARCHY
# -----------------------------------------------------------------
# PTSCS is a composite/thematic system: it selects codes out of two OTHER
# classifications and groups them thematically. It publishes no parent/child
# code hierarchy of its own. Accordingly `parent_code` is NA on every record
# and the canonical `level` column carries the component id
# ("tourism_industry" / "tourism_product") rather than a manufactured
# hierarchy level.
#
# UNDERLYING CLASSIFICATION PROVENANCE (spec 1.2 / 5)
# -----------------------------------------------------------------
#   Tourism Industries -> 2019 Updates to the 2009 PSIC   (source_system psic,
#                                                          source_version 2019)
#   Tourism Products   -> Central Product Classification  (source_system cpc,
#                         Version 2.1                      source_version 2.1)
# The industry codes are 2019 PSIC codes and are deliberately LEFT AS 2019
# codes. This application also carries PSIC Revision 5 (2026); silently
# re-coding PTSCS industries onto Revision 5 is explicitly prohibited, since
# PSA's own PTSCS Version 2.1 is defined against the 2019 edition. Any future
# 2019->2026 link must be surfaced as a separate, labelled correspondence.

suppressPackageStartupMessages({
  library(readxl)
  library(dplyr)
  library(tibble)
})

RAW_PATH <- "data-raw/PTSCS-Version-2.1.xlsx"
RAW_FILENAME <- basename(RAW_PATH)
OFFICIAL_SOURCE_PAGE <- "https://psa.gov.ph/classification/ptscs"
OUT_DATA_PATH <- "data/ptscs_2025_v2_1.rds"
OUT_META_PATH <- "data/ptscs_2025_v2_1_metadata.rds"

PTSCS_VERSION <- "2025-v2.1"
PTSCS_DISPLAY_VERSION <- "2025 PTSCS (Version 2.1)"

# PSA-stated coverage, taken from the workbook's own Metadata sheet
# ("Process" row) and from the PSA classification page.
OFFICIAL_COUNTS <- list(tourism_industry = 176L, tourism_product = 214L)

COMPONENT_SPEC <- list(
  tourism_industry = list(
    sheet = "2025 Tourism Industries",
    source_system = "psic",
    source_version = "2019",
    source_label = "2019 Updates to the 2009 Philippine Standard Industrial Classification (PSIC)"
  ),
  tourism_product = list(
    sheet = "2025 Tourism Products",
    source_system = "cpc",
    source_version = "2.1",
    source_label = "Central Product Classification (CPC) Version 2.1"
  )
)

if (!file.exists(RAW_PATH)) {
  stop(sprintf(
    "Missing raw PTSCS workbook at '%s'. Download the 2025 PTSCS (Version 2.1) workbook from %s and place it there, then re-run scripts/build_ptscs_2025.R.",
    RAW_PATH, OFFICIAL_SOURCE_PAGE
  ), call. = FALSE)
}

sheets <- excel_sheets(RAW_PATH)
expected_sheets <- c("Metadata", vapply(COMPONENT_SPEC, `[[`, character(1), "sheet"))
missing_sheets <- setdiff(expected_sheets, sheets)
if (length(missing_sheets) > 0) {
  stop(sprintf(
    "PTSCS workbook is missing expected sheet(s): %s. Workbook structure has changed -- re-inspect before trusting this parser.",
    paste(missing_sheets, collapse = ", ")
  ), call. = FALSE)
}

# Local definition so the script does not depend on `%||%` being exported by
# base R (>= 4.4) or by an attached tidyverse package.
`%or%` <- function(a, b) if (is.null(a) || length(a) == 0L || all(is.na(a))) b else a

blank_to_na <- function(x) {
  x <- trimws(gsub("[\r\n]+", " ", x))
  ifelse(is.na(x) | !nzchar(x), NA_character_, x)
}

# Extract the leading ordinal of a thematic heading, e.g.
#   "12.3. Education, Health and Personal Service Activities" -> "12.3"
#   "10 - Sports and Recreational Services"                   -> "10"
# Returns NA when the heading carries no ordinal at all.
heading_ordinal <- function(txt) {
  m <- regmatches(txt, regexpr("^\\s*[0-9]+(\\.[0-9]+)*", txt))
  if (length(m) == 0L) return(NA_character_)
  sub("\\.$", "", trimws(m))
}

#' Read the workbook's Metadata sheet into a named list.
read_metadata_sheet <- function(path) {
  raw <- suppressMessages(read_excel(path, sheet = "Metadata", col_names = FALSE, col_types = "text"))
  keys <- blank_to_na(raw[[1]])
  vals <- trimws(raw[[2]])
  keep <- !is.na(keys) & !is.na(vals)
  out <- as.list(vals[keep])
  names(out) <- sub(":\\s*$", "", keys[keep])
  out
}

#' Parse one PTSCS component sheet into tagged records.
#'
#' Returns a tibble of data rows plus attributes recording the workbook's own
#' column-header text and the ordered list of thematic headings encountered.
parse_component_sheet <- function(path, sheet_name, component) {
  raw <- suppressMessages(read_excel(
    path, sheet = sheet_name, col_names = FALSE, col_types = "text"
  ))
  if (ncol(raw) < 3L) {
    stop(sprintf("Sheet '%s': expected at least 3 columns, found %d.", sheet_name, ncol(raw)), call. = FALSE)
  }
  category <- blank_to_na(raw[[1]])
  code     <- blank_to_na(raw[[2]])
  label    <- blank_to_na(raw[[3]])

  # The single row carrying text in BOTH column 1 and column 2 is the
  # column-header row; everything above it is sheet title/spacer furniture.
  header_rows <- which(!is.na(category) & !is.na(code))
  if (length(header_rows) != 1L) {
    stop(sprintf(
      "Sheet '%s': expected exactly one column-header row (text in both col 1 and col 2), found %d. Workbook layout has changed.",
      sheet_name, length(header_rows)
    ), call. = FALSE)
  }
  hdr <- header_rows[[1]]
  header_text <- c(category = category[[hdr]], code = code[[hdr]], label = label[[hdr]])

  body <- seq.int(hdr + 1L, nrow(raw))
  records <- list()
  headings_seen <- character(0)
  current_leaf <- NA_character_
  current_top <- NA_character_

  for (i in body) {
    if (!is.na(code[i])) {
      # DATA row. A code must never share a row with a category heading.
      if (!is.na(category[i])) {
        stop(sprintf(
          "Sheet '%s' row %d: a row carries both a category heading and a code; the parser's row-type rule no longer holds.",
          sheet_name, i
        ), call. = FALSE)
      }
      if (is.na(label[i])) {
        stop(sprintf(
          "Sheet '%s' row %d: coded row '%s' has no label -- cannot honestly assign a title.",
          sheet_name, i, code[i]
        ), call. = FALSE)
      }
      if (is.na(current_leaf)) {
        stop(sprintf(
          "Sheet '%s' row %d: coded row '%s' appears before any thematic category heading.",
          sheet_name, i, code[i]
        ), call. = FALSE)
      }
      records[[length(records) + 1L]] <- tibble(
        code = code[i],
        label = label[i],
        major_category = current_leaf,
        major_category_group = current_top
      )
      next
    }
    if (!is.na(category[i])) {
      # THEMATIC CATEGORY HEADING row.
      current_leaf <- category[i]
      ord <- heading_ordinal(category[i])
      if (is.na(ord)) {
        stop(sprintf(
          "Sheet '%s' row %d: heading '%s' carries no ordinal prefix; cannot determine its grouping depth.",
          sheet_name, i, category[i]
        ), call. = FALSE)
      }
      if (!grepl("\\.", ord)) {
        current_top <- category[i]
      }
      headings_seen <- c(headings_seen, category[i])
      next
    }
    # Otherwise: blank spacer row -- skipped.
  }

  out <- bind_rows(records)
  out$component <- component
  attr(out, "header_text") <- header_text
  attr(out, "headings") <- headings_seen
  attr(out, "raw_rows") <- nrow(raw)
  attr(out, "blank_rows") <- sum(is.na(category) & is.na(code) & is.na(label))
  out
}

workbook_metadata <- read_metadata_sheet(RAW_PATH)

parsed_list <- lapply(names(COMPONENT_SPEC), function(comp) {
  parse_component_sheet(RAW_PATH, COMPONENT_SPEC[[comp]]$sheet, comp)
})
names(parsed_list) <- names(COMPONENT_SPEC)

# ---------------------------------------------------------------- validation

cat("PTSCS 2025 Version 2.1 -- build validation report\n")
cat(sprintf("Source workbook: %s\n", RAW_FILENAME))
cat(sprintf("Workbook Metadata sheet states title: %s\n",
            workbook_metadata[["Title"]] %or% "<absent>"))
cat(sprintf("Workbook Metadata sheet publication date: %s\n\n",
            workbook_metadata[["Publication date"]] %or% "<absent>"))

parsed_counts <- list()
build_warnings <- character(0)

for (comp in names(parsed_list)) {
  d <- parsed_list[[comp]]
  spec <- COMPONENT_SPEC[[comp]]
  n <- nrow(d)
  parsed_counts[[comp]] <- n
  official <- OFFICIAL_COUNTS[[comp]]

  cat(sprintf("Component: %s  (sheet '%s')\n", comp, spec$sheet))
  cat(sprintf("  workbook column headers : [%s] | [%s] | [%s]\n",
              attr(d, "header_text")[["category"]],
              attr(d, "header_text")[["code"]],
              attr(d, "header_text")[["label"]]))
  cat(sprintf("  underlying classification: %s (%s %s)\n",
              spec$source_label, spec$source_system, spec$source_version))
  cat(sprintf("  raw sheet rows           : %d\n", attr(d, "raw_rows")))
  cat(sprintf("  row accounting           : %d data + %d category headings + 1 column-header + %d blank + 1 sheet-title = %d\n",
              n, length(attr(d, "headings")), attr(d, "blank_rows"),
              n + length(attr(d, "headings")) + 1L + attr(d, "blank_rows") + 1L))

  status <- if (n == official) "OK" else "WARN (documented discrepancy)"
  cat(sprintf("  parsed=%d  official=%d  [%s]\n", n, official, status))
  if (n != official) {
    msg <- sprintf("PTSCS component '%s': parsed %d records but PSA officially states %d. Recorded honestly in metadata; NOT forced.",
                   comp, n, official)
    build_warnings <- c(build_warnings, msg)
    warning(msg, call. = FALSE)
  }

  # Codes are strings throughout: never numeric-coerced, leading zeros intact.
  lz <- sum(startsWith(d$code, "0"))
  cat(sprintf("  code column type         : %s\n", class(d$code)[[1]]))
  cat(sprintf("  code widths              : %s\n",
              paste(sprintf("%s chars x%d", names(table(nchar(d$code))), as.integer(table(nchar(d$code)))),
                    collapse = ", ")))
  cat(sprintf("  codes with leading zeros : %d (workbook contains none; string handling still required so none is ever lost)\n", lz))

  dups <- d$code[duplicated(d$code)]
  cat(sprintf("  duplicate codes within component: %d%s\n", length(dups),
              if (length(dups)) paste0(" -> ", paste(unique(dups), collapse = ", ")) else ""))
  if (length(dups) > 0) {
    msg <- sprintf("PTSCS component '%s' has %d duplicate code(s): %s",
                   comp, length(dups), paste(unique(dups), collapse = ", "))
    build_warnings <- c(build_warnings, msg)
    warning(msg, call. = FALSE)
  }

  cat(sprintf("  distinct major_category values (%d):\n", length(unique(d$major_category))))
  for (mc in unique(d$major_category)) {
    grp <- unique(d$major_category_group[d$major_category == mc])
    suffix <- if (identical(grp, mc)) "" else sprintf("   [group: %s]", grp)
    cat(sprintf("    %-3d %s%s\n", sum(d$major_category == mc), mc, suffix))
  }
  cat("\n")
}

parsed <- bind_rows(lapply(parsed_list, function(x) {
  attributes(x)[c("header_text", "headings", "raw_rows", "blank_rows")] <- NULL
  x
}))

# Cross-component code collisions are EXPECTED and legitimate: the two
# components draw codes from two different classifications (PSIC vs CPC), so
# the same 5-digit string can mean different things in each. Reported, not
# treated as an error -- `component` disambiguates.
collisions <- intersect(
  parsed$code[parsed$component == "tourism_industry"],
  parsed$code[parsed$component == "tourism_product"]
)
cat(sprintf("Cross-component code collisions (PSIC 2019 vs CPC 2.1): %d%s\n",
            length(collisions),
            if (length(collisions)) paste0(" -> ", paste(head(collisions, 10), collapse = ", ")) else ""))
cat("  (expected: the two components index two different classifications; `component` disambiguates)\n\n")

stopifnot(nrow(parsed) == sum(unlist(parsed_counts)))

# ------------------------------------------------------------ canonical build

source("R/schema.R")

spec_for <- function(field) {
  vapply(parsed$component, function(comp) COMPONENT_SPEC[[comp]][[field]], character(1), USE.NAMES = FALSE)
}

canonical <- new_classification_tibble(
  system = "ptscs",
  version = PTSCS_VERSION,
  # PTSCS publishes no code hierarchy of its own; the canonical `level`
  # column carries the component id rather than a manufactured level.
  level = parsed$component,
  code = parsed$code,
  label = parsed$label,
  description = NA_character_,
  parent_code = NA_character_,
  status = "current",
  source = "Philippine Statistics Authority",
  source_url = OFFICIAL_SOURCE_PAGE
)

# Composite-system provenance columns, appended AFTER the frozen canonical 10.
# The canonical schema is shared with the other classification systems and is
# NOT widened; canonical consumers simply ignore these extras.
canonical <- bind_cols(canonical, tibble(
  component            = parsed$component,
  major_category       = parsed$major_category,
  major_category_group = parsed$major_category_group,
  source_system        = spec_for("source_system"),
  source_version       = spec_for("source_version"),
  source_code          = parsed$code,
  source_label         = spec_for("source_label")
))

stopifnot(identical(names(canonical)[seq_along(CLASSIFICATION_SCHEMA_COLUMNS)],
                    CLASSIFICATION_SCHEMA_COLUMNS))
validate_classification_tibble(canonical)

# Hard guard on the explicit prohibition: PTSCS industries stay on 2019 PSIC.
industry_versions <- unique(canonical$source_version[canonical$component == "tourism_industry"])
if (!identical(industry_versions, "2019")) {
  stop(sprintf(
    "PTSCS tourism_industry provenance must be PSIC 2019, got: %s. Silent conversion to PSIC Revision 5 (2026) is prohibited.",
    paste(industry_versions, collapse = ", ")
  ), call. = FALSE)
}
product_versions <- unique(canonical$source_version[canonical$component == "tourism_product"])
if (!identical(product_versions, "2.1")) {
  stop(sprintf("PTSCS tourism_product provenance must be CPC 2.1, got: %s",
               paste(product_versions, collapse = ", ")), call. = FALSE)
}
cat("Provenance guard: industries = PSIC 2019, products = CPC 2.1. No 2026 substitution. OK\n")

sha256 <- digest::digest(file = RAW_PATH, algo = "sha256")

metadata <- list(
  system = "ptscs",
  version = PTSCS_VERSION,
  display_version = PTSCS_DISPLAY_VERSION,
  official_name = "Philippine Tourism Statistical Classification System (PTSCS)",
  status = "current",
  source = "Philippine Statistics Authority",
  source_url = OFFICIAL_SOURCE_PAGE,
  # Workbook FILENAME only -- never an absolute local machine path.
  source_artifact = RAW_FILENAME,
  retrieval_method = "manual download by user from the PSA classification page; no runtime network dependency",
  retrieved_at = as.character(Sys.Date()),
  sha256 = sha256,
  license = "CC BY 4.0 unless otherwise stated by PSA",
  build_script = "scripts/build_ptscs_2025.R",
  runtime_artifact = OUT_DATA_PATH,
  components = names(COMPONENT_SPEC),
  parsed_counts = parsed_counts,
  official_counts = OFFICIAL_COUNTS,
  underlying_classifications = list(
    tourism_industry = list(
      source_system = "psic",
      source_version = "2019",
      source_label = COMPONENT_SPEC$tourism_industry$source_label,
      workbook_code_column_header = unname(attr(parsed_list$tourism_industry, "header_text")[["code"]]),
      note = "PTSCS Version 2.1 is defined against the 2019 PSIC. Codes are deliberately NOT converted to PSIC Revision 5 (2026); any 2019->2026 link must be presented as a separate correspondence."
    ),
    tourism_product = list(
      source_system = "cpc",
      source_version = "2.1",
      source_label = COMPONENT_SPEC$tourism_product$source_label,
      workbook_code_column_header = unname(attr(parsed_list$tourism_product, "header_text")[["code"]]),
      note = "CPC is a United Nations classification; PSA adopts it for PTSCS tourism characteristic products."
    )
  ),
  major_categories = lapply(parsed_list, function(x) unname(attr(x, "headings"))),
  hierarchy = "none -- PTSCS is a composite/thematic system with no code hierarchy of its own; parent_code is NA on every record and `level` carries the component id",
  workbook_metadata_sheet = workbook_metadata,
  build_warnings = build_warnings
)

saveRDS(canonical, OUT_DATA_PATH)
saveRDS(metadata, OUT_META_PATH)

cat(sprintf("\nSaved %d canonical rows (%s) to %s\n",
            nrow(canonical),
            paste(sprintf("%s=%d", names(parsed_counts), unlist(parsed_counts)), collapse = ", "),
            OUT_DATA_PATH))
cat(sprintf("Saved metadata to %s (sha256=%s)\n", OUT_META_PATH, sha256))
if (length(build_warnings) > 0) {
  cat(sprintf("\n%d documented discrepancy/warning(s) recorded in metadata$build_warnings.\n", length(build_warnings)))
} else {
  cat("No count discrepancies: parsed counts match PSA's official 176 / 214 exactly.\n")
}
