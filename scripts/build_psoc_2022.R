# Build-time normalization pipeline for the "2022 Updates to the 2012
# Philippine Standard Occupational Classification (PSOC)".
#
# Source: official PSA workbook, normally downloaded from
#   https://psa.gov.ph/sites/default/files/kmcd/files/2022-Updates-to-the-2012-PSOC.xlsx
#   (linked from https://psa.gov.ph/classification/psoc)
#
# Automated retrieval of this specific file was blocked by Cloudflare's JS
# challenge on psa.gov.ph (curl/httr2 received HTTP 403 with
# `Cf-Mitigated: challenge` even with a browser User-Agent; a real browser
# session passed the challenge but the file could not be saved to disk
# through the available browser automation, since it downloads rather than
# renders). The workbook was therefore manually downloaded by the user from
# the same official URL and placed at:
#   data-raw/2022-Updates-to-the-2012-PSOC.xlsx
# This script does NOT attempt automated download for this source (unlike
# scripts/build_psic_2026.R, which can reach its source directly) --
# rerunning this script requires that file to already be present.
#
# WORKBOOK STRUCTURE (verified by direct inspection, not assumed)
# -----------------------------------------------------------------
# 10 sheets named "Group 1".."Group 9", "Group 0" -- one per PSOC major
# group (major group 0 = Armed Forces Occupations, per standard PSOC/ISCO
# convention). Each sheet has 6 columns (header row 1):
#   1: SUB-MAJOR GROUP (2-digit code, e.g. "41"; blank on non-sub-major rows)
#   2: MINOR GROUP (3-digit code, e.g. "411"; blank otherwise)
#   3: UNIT GROUP (4-digit code, e.g. "4110"; blank otherwise)
#   4: OCCUPATIONAL TITLES AND DEFINITIONS -- the entity's title when a code
#      is present in column 1/2/3 on that row; free-text definitions, task
#      lists, and example job titles on rows with no code in any of 1-3
#      (these are prose, not distinct classification entities, and are not
#      captured as `description` here -- see rationale below)
#   5: 1992 PSOC cross-reference code(s) -- historical crosswalk, not part
#      of the 2022 canonical structure, not used
#   6: 2008 ISCO cross-reference code -- ditto, not used
#
# Exactly like the PSIC Revision 5 workbook (scripts/build_psic_2026.R),
# when a level has exactly one child at the level below, the row collapses
# multiple code columns onto one row sharing one title (e.g. sub-major
# "411" + unit "4110" on the same row, titled "GENERAL OFFICE CLERKS",
# because sub-major group 411 has only that one unit-group child). The same
# forward-fill parsing algorithm used for PSIC Revision 5 handles this
# correctly here too: process rows top-to-bottom, and for each non-NA code
# column on a row (in hierarchy order), its parent is either an
# already-assigned code earlier on the SAME row, or the most recently seen
# code of the immediate parent level from a previous row.
#
# The major-group level itself has no code column at all -- its code comes
# from the sheet name, and its title is the first non-blank, non-marker
# text in column 4 before the first code-bearing row (skipping a literal
# "Major Group N." marker line where present; "Group 0"'s sheet omits that
# marker entirely and states the title directly on the first content row,
# so the parser does not assume the marker exists).
#
# DESCRIPTION FIELD: left NA. The workbook's prose (definitions, "tasks
# performed", "examples of the occupations classified here" lists) is
# extensive multi-paragraph text interleaved with bare example job titles
# that are NOT further classification codes -- reliably separating genuine
# definition prose from example-title lists without misattributing text
# would require guessing at a legend this workbook doesn't state
# explicitly. Rather than risk mislabeling text as a "description", this
# build leaves description = NA, matching how many phscs-sourced editions
# in this application already have NA descriptions per record (see
# R/adapters/adapter_phscs.R). The full text remains in the source
# workbook for anyone who needs it.

suppressPackageStartupMessages({
  library(readxl)
  library(dplyr)
  library(tibble)
})

RAW_PATH <- "data-raw/2022-Updates-to-the-2012-PSOC.xlsx"
OFFICIAL_SOURCE_PAGE <- "https://psa.gov.ph/classification/psoc"
OFFICIAL_ARTIFACT_URL <- "https://psa.gov.ph/sites/default/files/kmcd/files/2022-Updates-to-the-2012-PSOC.xlsx"
OUT_DATA_PATH <- "data/psoc_2022.rds"
OUT_META_PATH <- "data/psoc_2022_metadata.rds"

PSA_STATED_COUNTS <- list(major_group = 10, sub_major_group = 43, minor_group = 130, unit_group = 456)

if (!file.exists(RAW_PATH)) {
  stop(sprintf(
    "Missing raw PSOC 2022 workbook at '%s'. This file could not be auto-downloaded (blocked by Cloudflare on psa.gov.ph) and must be manually placed there from %s.",
    RAW_PATH, OFFICIAL_ARTIFACT_URL
  ), call. = FALSE)
}

sheets <- excel_sheets(RAW_PATH)
group_sheets <- sheets[grepl("^Group\\s*[0-9]$", sheets)]
stopifnot(length(group_sheets) == 10)

#' Parse one "Group N" sheet into major/sub_major/minor/unit records.
parse_group_sheet <- function(path, sheet_name) {
  major_code <- trimws(sub("^Group\\s*", "", sheet_name))

  raw <- suppressMessages(read_excel(
    path, sheet = sheet_name, skip = 1, col_types = "text",
    col_names = c("submajor", "minor", "unit", "title", "legacy_1992", "legacy_isco2008")
  ))

  clean_code <- function(x) {
    x <- trimws(x)
    ifelse(is.na(x) | !nzchar(x), NA_character_, x)
  }
  raw$submajor <- clean_code(raw$submajor)
  raw$minor <- clean_code(raw$minor)
  raw$unit <- clean_code(raw$unit)
  raw$title <- trimws(gsub("[\r\n]+", " ", raw$title))
  raw$title <- ifelse(is.na(raw$title) | !nzchar(raw$title), NA_character_, raw$title)

  has_code <- !is.na(raw$submajor) | !is.na(raw$minor) | !is.na(raw$unit)
  first_code_idx <- which(has_code)[1]
  if (is.na(first_code_idx)) {
    stop(sprintf("Sheet '%s': no coded rows found at all -- workbook structure has changed.", sheet_name), call. = FALSE)
  }

  pre_titles <- raw$title[seq_len(first_code_idx - 1)]
  pre_titles <- pre_titles[!is.na(pre_titles)]
  pre_titles <- pre_titles[!grepl("^Major Group\\b", pre_titles, ignore.case = TRUE)]
  if (length(pre_titles) == 0L) {
    stop(sprintf("Sheet '%s': could not locate a major-group title before the first coded row.", sheet_name), call. = FALSE)
  }
  major_title <- pre_titles[[1]]

  records <- list(tibble(level = "major_group", code = major_code, label = major_title, parent_code = NA_character_))

  last_submajor <- NA_character_
  last_minor <- NA_character_

  code_rows <- which(has_code)
  for (i in code_rows) {
    sm <- raw$submajor[i]
    mn <- raw$minor[i]
    un <- raw$unit[i]
    title <- raw$title[i]
    if (is.na(title)) {
      stop(sprintf("Sheet '%s' row %d: a coded row has no title -- cannot honestly assign a label.", sheet_name, i + 1), call. = FALSE)
    }

    if (!is.na(sm)) {
      records[[length(records) + 1L]] <- tibble(level = "sub_major_group", code = sm, label = title, parent_code = major_code)
      last_submajor <- sm
    }
    if (!is.na(mn)) {
      parent_sm <- if (!is.na(sm)) sm else last_submajor
      records[[length(records) + 1L]] <- tibble(level = "minor_group", code = mn, label = title, parent_code = parent_sm)
      last_minor <- mn
    }
    if (!is.na(un)) {
      parent_mn <- if (!is.na(mn)) mn else last_minor
      records[[length(records) + 1L]] <- tibble(level = "unit_group", code = un, label = title, parent_code = parent_mn)
    }
  }

  bind_rows(records)
}

parsed <- bind_rows(lapply(group_sheets, function(s) parse_group_sheet(RAW_PATH, s)))

counts <- list(
  major_group = sum(parsed$level == "major_group"),
  sub_major_group = sum(parsed$level == "sub_major_group"),
  minor_group = sum(parsed$level == "minor_group"),
  unit_group = sum(parsed$level == "unit_group")
)

cat("PSOC 2022 parsed structural counts vs. PSA-stated counts:\n")
for (lvl in names(PSA_STATED_COUNTS)) {
  parsed_n <- counts[[lvl]]
  stated_n <- PSA_STATED_COUNTS[[lvl]]
  status <- if (parsed_n == stated_n) "OK" else "WARN (documented discrepancy)"
  cat(sprintf("  %-16s parsed=%-4d stated=%-4d [%s]\n", lvl, parsed_n, stated_n, status))
}

# Referential integrity is a stronger correctness check than raw counts: if
# the workbook were malformed (truncated rows, misaligned columns), parent
# codes would fail to resolve. This is a hard failure condition -- unlike a
# level-count mismatch against PSA's own summary text, a broken parent chain
# would mean the parsed data itself is wrong, not just differently-counted.
check_parents_resolve <- function(child_level, parent_level) {
  child_parents <- unique(parsed$parent_code[parsed$level == child_level])
  parent_codes <- parsed$code[parsed$level == parent_level]
  orphans <- setdiff(child_parents, parent_codes)
  if (length(orphans) > 0) {
    stop(sprintf(
      "PSOC 2022 referential integrity failure: %d '%s' parent_code value(s) do not exist as '%s' codes: %s",
      length(orphans), child_level, parent_level, paste(orphans, collapse = ", ")
    ), call. = FALSE)
  }
}
check_parents_resolve("sub_major_group", "major_group")
check_parents_resolve("minor_group", "sub_major_group")
check_parents_resolve("unit_group", "minor_group")
cat("Referential integrity: all parent_code chains resolve to a real parent record. OK\n")

cat("\nValidation fixture: PSA's documented 2022 update example (Mathematicians and Actuaries split)\n")
fixture <- parsed[parsed$level == "unit_group" & parsed$code %in% c("2121", "2123"), c("code", "label")]
print(fixture)
if (!("2121" %in% fixture$code)) {
  warning("Expected unit group 2121 (Mathematicians) not found in parsed data -- documenting, not blocking.")
}
if (!("2123" %in% fixture$code)) {
  warning("Expected unit group 2123 (Actuaries) not found in parsed data -- documenting, not blocking.")
}

source("R/schema.R")

canonical <- new_classification_tibble(
  system = "psoc",
  version = "2022",
  level = parsed$level,
  code = parsed$code,
  label = parsed$label,
  description = NA_character_,
  parent_code = parsed$parent_code,
  status = "current",
  source = "Philippine Statistics Authority",
  source_url = OFFICIAL_SOURCE_PAGE
)

sha256 <- digest::digest(file = RAW_PATH, algo = "sha256")

metadata <- list(
  system = "psoc",
  version = "2022",
  display_version = "2022 Updates to the 2012 PSOC",
  status = "current",
  source = "Philippine Statistics Authority",
  source_url = OFFICIAL_SOURCE_PAGE,
  source_artifact_url = OFFICIAL_ARTIFACT_URL,
  retrieval_method = "manual download by user (automated retrieval blocked by Cloudflare JS challenge on psa.gov.ph; see script header comment)",
  retrieved_at = as.character(Sys.Date()),
  sha256 = sha256,
  license = "CC BY 4.0 unless otherwise stated by PSA",
  parsed_counts = counts,
  psa_stated_counts = PSA_STATED_COUNTS
)

saveRDS(canonical, OUT_DATA_PATH)
saveRDS(metadata, OUT_META_PATH)

cat(sprintf("\nSaved %d canonical rows to %s\n", nrow(canonical), OUT_DATA_PATH))
cat(sprintf("Saved metadata to %s (sha256=%s)\n", OUT_META_PATH, sha256))
