# Build-time normalization pipeline for the 2022 Philippine Standard
# Commodity Classification (PSCC).
#
# Turns PSA's official PSCC workbook (data-raw/pscc.xlsx) into local runtime
# artifacts (data/pscc_2022.rds + data/pscc_2022_metadata.rds) so the running
# app never parses Excel per request and never depends on PSA network
# availability.
#
# Run from the repository root:
#   Rscript scripts/build_pscc_2022.R
#
# ---------------------------------------------------------------------------
# CODE INTEGRITY CONTRACT
# ---------------------------------------------------------------------------
# PSCC codes are STRINGS. The workbook is read with col_types = "text" and no
# code is ever passed through as.numeric() except for the handful of cells
# that Excel itself stored as numbers (see `repair_numeric_cell()`), where the
# float text is round-tripped back to its published fixed-width form. Leading
# zeros, dots, hyphens and 3-digit suffixes are preserved verbatim.

suppressPackageStartupMessages({
  library(readxl)
  library(tibble)
})

RAW_XLSX_PATH  <- "data-raw/pscc.xlsx"
RAW_SHEET      <- "all sections"
SOURCE_URL     <- "https://psa.gov.ph/classification/pscc"
OUT_DATA_PATH  <- "data/pscc_2022.rds"
OUT_META_PATH  <- "data/pscc_2022_metadata.rds"

PSCC_SYSTEM          <- "pscc"
PSCC_VERSION         <- "2022"
PSCC_DISPLAY_VERSION <- "2022 PSCC"
PSCC_OFFICIAL_NAME   <- "Philippine Standard Commodity Classification"
PSCC_DISPLAY_NAME    <- "Philippine Standard Commodity Classification (PSCC)"
PSCC_SCOPE <- paste(
  "Detailed classification of commodities entering/traded in Philippine trade."
)

# Hierarchy, in order. Derived from the workbook, not assumed:
#   section          -- "SECTION I - ..." description rows          (roman numeral)
#   chapter          -- "Chapter 1 - ..." description rows          (2-digit)
#   heading          -- column 1 "Heading"                          (NN.NN, HS 4-digit)
#   subheading       -- column 2, NNNN.NN                           (HS 6-digit)
#   ahtn subheading  -- column 2, NNNN.NN.NN                        (AHTN 8-digit)
#   commodity        -- column 2, NNNN.NN.NN-NNN                    (PSCC 11-digit)
PSCC_LEVELS <- c("section", "chapter", "heading", "subheading",
                  "ahtn subheading", "commodity")

# Expected raw column order in the "all sections" sheet (header row 1).
RAW_COLS <- c("heading", "code", "description", "unit", "pscc2019", "ahtn2022")
EXPECTED_HEADER <- c("Heading", "2022 PSCC", "DESCRIPTION", "Unit of Quantity")

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

`%||%` <- function(a, b) if (is.null(a)) b else a

squish <- function(x) {
  x <- gsub("[\r\n\t]+", " ", x)
  x <- gsub("[[:space:]]+", " ", x)
  trimws(x)
}

# Excel stored a handful of code/heading cells as numbers rather than text, so
# readxl surfaces them as float literals ("20.059999999999999"). Round-trip
# them back to the published fixed-width decimal form. This is the ONLY place
# a code touches as.numeric(), and it applies only to cells that cannot
# possibly carry a leading zero problem (they are dotted decimals whose
# integer part is already >= 2 digits in the published form).
repair_numeric_cell <- function(x, width, digits) {
  n <- suppressWarnings(as.numeric(x))
  if (is.na(n)) {
    stop(sprintf("Cannot repair non-numeric malformed cell value '%s'.", x), call. = FALSE)
  }
  sprintf(paste0("%0", width, ".", digits, "f"), n)
}

# ---------------------------------------------------------------------------
# 1. Read + structural validation of the raw workbook
# ---------------------------------------------------------------------------

read_pscc_workbook <- function(path) {
  if (!file.exists(path)) {
    stop(sprintf(
      "PSCC source workbook not found at %s. Place the official PSA PSCC workbook there and re-run scripts/build_pscc_2022.R.",
      path
    ), call. = FALSE)
  }

  sheets <- readxl::excel_sheets(path)
  if (!RAW_SHEET %in% sheets) {
    stop(sprintf("Workbook is missing the expected '%s' sheet (found: %s).",
                  RAW_SHEET, paste(sheets, collapse = ", ")), call. = FALSE)
  }

  header <- suppressMessages(readxl::read_excel(
    path, sheet = RAW_SHEET, col_names = FALSE, col_types = "text", n_max = 1
  ))
  if (ncol(header) != length(RAW_COLS)) {
    stop(sprintf("Expected %d columns in '%s', found %d. Workbook layout changed.",
                  length(RAW_COLS), RAW_SHEET, ncol(header)), call. = FALSE)
  }
  header_txt <- squish(as.character(unlist(header[1, ], use.names = FALSE)))
  for (i in seq_along(EXPECTED_HEADER)) {
    if (!identical(header_txt[i], EXPECTED_HEADER[i])) {
      stop(sprintf("Unexpected header in column %d: expected '%s', found '%s'.",
                    i, EXPECTED_HEADER[i], header_txt[i]), call. = FALSE)
    }
  }
  # Columns 5-6 sit under a merged "2019 PSCC / AHTN 2022" banner; assert the
  # banner text mentions both editions rather than pinning an exact string.
  banner <- paste(header_txt[5:6], collapse = " ")
  if (!grepl("2019", banner) || !grepl("AHTN", banner)) {
    stop(sprintf("Expected a '2019 PSCC / AHTN 2022' cross-reference banner in columns 5-6, found '%s'.",
                  banner), call. = FALSE)
  }

  raw <- suppressMessages(readxl::read_excel(
    path, sheet = RAW_SHEET, col_names = FALSE, col_types = "text", skip = 1
  ))
  names(raw) <- RAW_COLS

  if (nrow(raw) == 0) {
    stop("Parsed zero data rows from the PSCC workbook. Aborting build.", call. = FALSE)
  }
  non_char <- RAW_COLS[!vapply(raw[RAW_COLS], is.character, logical(1))]
  if (length(non_char) > 0) {
    stop(sprintf("Raw workbook column(s) did not read as character: %s. Refusing to numeric-coerce PSCC codes.",
                  paste(non_char, collapse = ", ")), call. = FALSE)
  }

  for (col in RAW_COLS) {
    v <- raw[[col]]
    v <- ifelse(is.na(v), NA_character_, squish(v))
    v[!is.na(v) & v == ""] <- NA_character_
    raw[[col]] <- v
  }

  raw$source_row <- seq_len(nrow(raw)) + 1L  # +1 for the header row
  raw
}

# ---------------------------------------------------------------------------
# 2. Repair Excel-numeric cells in the two code-bearing columns
# ---------------------------------------------------------------------------

HEADING_RE   <- "^[0-9]{2}\\.[0-9]{2}$"
SUBHEAD_RE   <- "^[0-9]{4}\\.[0-9]{2}$"
AHTN_RE      <- "^[0-9]{4}\\.[0-9]{2}\\.[0-9]{2}$"
COMMODITY_RE <- "^[0-9]{4}\\.[0-9]{2}\\.[0-9]{2}-[0-9]{3}$"
# Four rows in chapter 96 publish the 11-digit code with an AHTN-style dot
# separator instead of the usual hyphen. Preserved verbatim; see anomalies.
COMMODITY_DOTTED_RE <- "^[0-9]{4}\\.[0-9]{2}\\.[0-9]{2}\\.[0-9]{3}$"

repair_code_columns <- function(raw) {
  repairs <- list()

  h_bad <- which(!is.na(raw$heading) & !grepl(HEADING_RE, raw$heading))
  for (i in h_bad) {
    before <- raw$heading[i]
    after <- repair_numeric_cell(before, width = 5, digits = 2)
    if (!grepl(HEADING_RE, after)) {
      stop(sprintf("Heading cell '%s' (row %d) could not be repaired to NN.NN (got '%s').",
                    before, raw$source_row[i], after), call. = FALSE)
    }
    raw$heading[i] <- after
    repairs[[length(repairs) + 1L]] <- list(
      column = "Heading", source_row = raw$source_row[i], raw = before, repaired = after
    )
  }

  ok_re <- paste0("(", SUBHEAD_RE, ")|(", AHTN_RE, ")|(", COMMODITY_RE, ")|(", COMMODITY_DOTTED_RE, ")")
  ok_re <- gsub("\\^|\\$", "", ok_re)
  c_bad <- which(!is.na(raw$code) &
                   !grepl(SUBHEAD_RE, raw$code) &
                   !grepl(AHTN_RE, raw$code) &
                   !grepl(COMMODITY_RE, raw$code) &
                   !grepl(COMMODITY_DOTTED_RE, raw$code))
  for (i in c_bad) {
    before <- raw$code[i]
    after <- repair_numeric_cell(before, width = 7, digits = 2)
    if (!grepl(SUBHEAD_RE, after)) {
      stop(sprintf("2022 PSCC code cell '%s' (row %d) could not be repaired to NNNN.NN (got '%s').",
                    before, raw$source_row[i], after), call. = FALSE)
    }
    raw$code[i] <- after
    repairs[[length(repairs) + 1L]] <- list(
      column = "2022 PSCC", source_row = raw$source_row[i], raw = before, repaired = after
    )
  }

  list(raw = raw, repairs = repairs)
}

# ---------------------------------------------------------------------------
# 3. Parse rows into canonical records
# ---------------------------------------------------------------------------

SECTION_RE <- "^SECTION\\s+([IVXLC]+)\\s*[-–—]\\s*(.+)$"
CHAPTER_RE <- "^Chapter\\s+([0-9]+)\\s*[-–—]\\s*(.+)$"
# Chapter 60's heading row inverts the number and the dash.
CHAPTER_ALT_RE <- "^Chapter\\s*[-–—]\\s*([0-9]+)\\s+(.+)$"

classify_code_level <- function(code) {
  if (grepl(SUBHEAD_RE, code))   return("subheading")
  if (grepl(AHTN_RE, code))      return("ahtn subheading")
  if (grepl(COMMODITY_RE, code)) return("commodity")
  if (grepl(COMMODITY_DOTTED_RE, code)) return("commodity")
  NA_character_
}

parse_pscc <- function(raw) {
  n <- nrow(raw)

  lvl <- character(0); cde <- character(0); lab <- character(0)
  par <- character(0); srow <- integer(0); scol <- character(0)

  cur_section <- NA_character_
  cur_chapter <- NA_character_

  sub_chapter_rows <- 0L
  qualifier_rows   <- 0L
  duplicate_notes  <- list()
  anomalies        <- list()

  seen <- new.env(parent = emptyenv())   # "level\rcode" -> TRUE
  key_of <- function(level, code) paste(level, code, sep = "\r")
  # `source_column` records which workbook column the code text came from, so
  # that row-level extras (unit of quantity, cross-references) are attributed
  # only to the "2022 PSCC" code on that row -- never to a "Heading" record
  # that happens to be printed on the same physical row.
  add_row <- function(level, code, label, parent, row_no, source_column) {
    k <- key_of(level, code)
    if (!is.null(seen[[k]])) {
      duplicate_notes[[length(duplicate_notes) + 1L]] <<- list(
        level = level, code = code, source_row = row_no,
        kept_label = seen[[k]], dropped_label = label
      )
      return(invisible(FALSE))
    }
    seen[[k]] <<- label
    lvl  <<- c(lvl, level)
    cde  <<- c(cde, code)
    lab  <<- c(lab, label)
    par  <<- c(par, parent)
    srow <<- c(srow, row_no)
    scol <<- c(scol, source_column)
    invisible(TRUE)
  }

  for (i in seq_len(n)) {
    hd   <- raw$heading[i]
    cd   <- raw$code[i]
    desc <- raw$description[i]
    row_no <- raw$source_row[i]

    if (is.na(hd) && is.na(cd)) {
      if (is.na(desc)) next

      m <- regmatches(desc, regexec(SECTION_RE, desc))[[1]]
      if (length(m) == 3L) {
        cur_section <- m[2]
        cur_chapter <- NA_character_
        add_row("section", cur_section, m[3], NA_character_, row_no, "description")
        next
      }

      m <- regmatches(desc, regexec(CHAPTER_RE, desc))[[1]]
      if (length(m) != 3L) {
        m <- regmatches(desc, regexec(CHAPTER_ALT_RE, desc))[[1]]
      }
      if (length(m) == 3L) {
        cur_chapter <- sprintf("%02d", as.integer(m[2]))
        if (is.na(cur_section)) {
          stop(sprintf("Chapter row %d ('%s') appears before any SECTION row.", row_no, desc),
               call. = FALSE)
        }
        add_row("chapter", cur_chapter, m[3], cur_section, row_no, "description")
        next
      }

      if (grepl("^Sub-?Chapter", desc, ignore.case = TRUE)) {
        sub_chapter_rows <- sub_chapter_rows + 1L
        next
      }

      # Remaining code-less description rows are the HS dash-indent qualifier
      # lines ("- Horses :"). They carry no code and therefore cannot become
      # canonical records; they are counted, not silently ignored.
      qualifier_rows <- qualifier_rows + 1L
      next
    }

    if (!is.na(hd)) {
      if (is.na(desc)) {
        stop(sprintf("Heading '%s' at row %d has no description text.", hd, row_no), call. = FALSE)
      }
      ch <- substr(gsub("\\.", "", hd), 1, 2)
      if (is.na(cur_chapter) || !identical(ch, cur_chapter)) {
        stop(sprintf("Heading '%s' at row %d does not sit under its own chapter (current chapter: %s).",
                      hd, row_no, cur_chapter %||% "none"), call. = FALSE)
      }
      add_row("heading", hd, desc, cur_chapter, row_no, "heading")
    }

    if (!is.na(cd)) {
      level <- classify_code_level(cd)
      if (is.na(level)) {
        stop(sprintf("Unrecognised 2022 PSCC code shape '%s' at row %d.", cd, row_no), call. = FALSE)
      }
      if (is.na(desc)) {
        stop(sprintf("Code '%s' at row %d has no description text.", cd, row_no), call. = FALSE)
      }
      if (grepl(COMMODITY_DOTTED_RE, cd)) {
        anomalies[[length(anomalies) + 1L]] <- list(
          source_row = row_no, code = cd,
          note = "11-digit commodity code published with a dot separator instead of a hyphen; preserved verbatim."
        )
      }
      # parent_code is resolved in a second pass, once every code that exists
      # in the workbook is known.
      add_row(level, cd, desc, NA_character_, row_no, "code")
    }
  }

  list(
    records = tibble::tibble(level = lvl, code = cde, label = lab,
                              parent_code = par, source_row = srow,
                              source_column = scol),
    sub_chapter_rows = sub_chapter_rows,
    qualifier_rows = qualifier_rows,
    duplicate_notes = duplicate_notes,
    anomalies = anomalies
  )
}

# ---------------------------------------------------------------------------
# 4. Resolve parents against verified ancestors only
# ---------------------------------------------------------------------------
# The workbook prints a code row only where PSA prints one, so the strict
# 6-digit -> 8-digit -> 11-digit chain is sparse: most 11-digit commodities
# have no explicit 8-digit row above them. Rather than inventing intermediate
# codes (forbidden) or dropping the hierarchy entirely, each code is attached
# to its NEAREST ANCESTOR THAT ACTUALLY EXISTS as a row in the workbook. Every
# candidate prefix is checked against the real code set before it is used; if
# none exists, parent_code stays NA.

resolve_parents <- function(records) {
  exists_at <- function(level) {
    e <- new.env(parent = emptyenv())
    for (cd in records$code[records$level == level]) e[[cd]] <- TRUE
    e
  }
  headings <- exists_at("heading")
  subheads <- exists_at("subheading")
  ahtns    <- exists_at("ahtn subheading")

  has <- function(e, k) !is.null(e[[k]])

  heading_key <- function(code) {
    d4 <- substr(code, 1, 4)
    paste0(substr(d4, 1, 2), ".", substr(d4, 3, 4))
  }

  distance <- integer(nrow(records))
  parents  <- records$parent_code

  for (i in seq_len(nrow(records))) {
    lv <- records$level[i]
    cd <- records$code[i]

    if (lv %in% c("section", "chapter", "heading")) {
      distance[i] <- if (is.na(parents[i])) NA_integer_ else 1L
      next
    }

    candidates <- character(0)
    if (lv == "commodity")      candidates <- c(substr(cd, 1, 10), substr(cd, 1, 7))
    if (lv == "ahtn subheading") candidates <- c(substr(cd, 1, 7))

    resolved <- NA_character_
    dist <- NA_integer_
    step <- 1L
    for (cand in candidates) {
      if (nchar(cand) == 10L && has(ahtns, cand)) { resolved <- cand; dist <- step; break }
      if (nchar(cand) == 7L  && has(subheads, cand)) { resolved <- cand; dist <- step; break }
      step <- step + 1L
    }
    if (is.na(resolved)) {
      hk <- heading_key(cd)
      if (has(headings, hk)) { resolved <- hk; dist <- step }
    }

    parents[i] <- resolved
    distance[i] <- dist
  }

  records$parent_code <- parents
  records$parent_distance <- distance
  records
}

# ---------------------------------------------------------------------------
# 5. Descriptive context
# ---------------------------------------------------------------------------
# Many published labels are bare HS continuations ("- - Other"). The canonical
# `description` column is filled with the published 4-digit heading text that
# the code belongs to, resolved by verified 4-digit prefix. Nothing is
# invented: the text is PSA's own heading wording.

attach_heading_description <- function(records) {
  heading_label <- new.env(parent = emptyenv())
  h <- records$level == "heading"
  for (j in which(h)) heading_label[[gsub("\\.", "", records$code[j])]] <- records$label[j]

  desc <- rep(NA_character_, nrow(records))
  below <- records$level %in% c("subheading", "ahtn subheading", "commodity")
  for (j in which(below)) {
    v <- heading_label[[substr(records$code[j], 1, 4)]]
    if (!is.null(v)) desc[j] <- v
  }
  records$description <- desc
  records
}

# ---------------------------------------------------------------------------
# 6. Validation report + hard failures
# ---------------------------------------------------------------------------

validate_and_report <- function(records, raw, parsed) {
  if (nrow(records) == 0) {
    stop("Zero canonical PSCC records produced. Aborting build.", call. = FALSE)
  }
  if (!is.character(records$code)) {
    stop("Canonical PSCC code column is not character. Aborting build.", call. = FALSE)
  }

  key <- paste(records$level, records$code, sep = "\r")
  if (anyDuplicated(key) > 0) {
    dups <- unique(key[duplicated(key)])
    stop(sprintf("Duplicate canonical (level, code) keys: %s",
                  paste(head(gsub("\r", "/", dups), 10), collapse = ", ")), call. = FALSE)
  }

  unknown_levels <- setdiff(unique(records$level), PSCC_LEVELS)
  if (length(unknown_levels) > 0) {
    stop(sprintf("Records carry levels outside the declared hierarchy: %s",
                  paste(unknown_levels, collapse = ", ")), call. = FALSE)
  }

  all_codes <- unique(records$code)
  orphan <- records$parent_code[!is.na(records$parent_code)]
  missing_parents <- setdiff(orphan, all_codes)
  if (length(missing_parents) > 0) {
    stop(sprintf("Non-NA parent_code values that are not real PSCC codes: %s",
                  paste(head(missing_parents, 10), collapse = ", ")), call. = FALSE)
  }

  counts <- table(factor(records$level, levels = PSCC_LEVELS))
  leading_zero <- sum(grepl("^0", records$code))
  punctuated   <- sum(grepl("[.-]", records$code))
  hyphenated   <- sum(grepl("-", records$code))

  message("")
  message("PSCC 2022 build validation report")
  message("---------------------------------")
  message(sprintf("  raw workbook rows            : %d", nrow(raw)))
  message(sprintf("  canonical records            : %d", nrow(records)))
  for (lv in PSCC_LEVELS) {
    message(sprintf("    %-18s : %d", lv, as.integer(counts[[lv]])))
  }
  message(sprintf("  codes with a leading zero    : %d", leading_zero))
  message(sprintf("  punctuated codes (. or -)    : %d", punctuated))
  message(sprintf("  hyphenated 11-digit codes    : %d", hyphenated))
  message(sprintf("  duplicate (level, code) keys : 0 (verified)"))
  message(sprintf("  parent refs unresolved (NA)  : %d",
                   sum(is.na(records$parent_code) & records$level != "section")))
  message(sprintf("  sub-chapter heading rows     : %d (no code; not canonical)",
                   parsed$sub_chapter_rows))
  message(sprintf("  HS dash-qualifier rows       : %d (no code; not canonical)",
                   parsed$qualifier_rows))
  message(sprintf("  duplicate source rows folded : %d", length(parsed$duplicate_notes)))
  message(sprintf("  separator anomalies preserved: %d", length(parsed$anomalies)))

  if (length(parsed$duplicate_notes) > 0) {
    warning(sprintf(
      "%d workbook rows repeat a code already emitted at the same level; first occurrence kept, alternates recorded in metadata$duplicate_code_notes.",
      length(parsed$duplicate_notes)
    ), call. = FALSE)
  }
  if (length(parsed$anomalies) > 0) {
    warning(sprintf(
      "%d code(s) use a non-standard separator and were preserved verbatim; see metadata$anomalies.",
      length(parsed$anomalies)
    ), call. = FALSE)
  }

  n_na_parent <- sum(is.na(records$parent_code) & records$level != "section")
  if (n_na_parent > 0) {
    message(sprintf(
      "  NOTE: %d record(s) had no verifiable ancestor row and keep parent_code = NA rather than a guessed parent.",
      n_na_parent
    ))
  }

  list(
    by_level = as.list(setNames(as.integer(counts), PSCC_LEVELS)),
    total = nrow(records),
    leading_zero_codes = leading_zero,
    punctuated_codes = punctuated,
    hyphenated_codes = hyphenated,
    duplicate_keys = 0L,
    unresolved_parents = n_na_parent,
    sub_chapter_rows = parsed$sub_chapter_rows,
    qualifier_rows = parsed$qualifier_rows,
    raw_rows = nrow(raw)
  )
}

# ---------------------------------------------------------------------------
# 7. Main
# ---------------------------------------------------------------------------

main <- function() {
  raw <- read_pscc_workbook(RAW_XLSX_PATH)
  message(sprintf("Read %d rows x %d columns from '%s' [%s].",
                   nrow(raw), length(RAW_COLS), RAW_SHEET, RAW_XLSX_PATH))

  fixed <- repair_code_columns(raw)
  raw <- fixed$raw
  if (length(fixed$repairs) > 0) {
    message(sprintf("Repaired %d Excel-numeric code/heading cell(s) back to published form.",
                     length(fixed$repairs)))
  }

  parsed <- parse_pscc(raw)
  records <- parsed$records
  records <- resolve_parents(records)
  records <- attach_heading_description(records)

  counts <- validate_and_report(records, raw, parsed)

  canonical <- new_classification_tibble(
    system      = PSCC_SYSTEM,
    version     = PSCC_VERSION,
    level       = records$level,
    code        = records$code,
    label       = records$label,
    description = records$description,
    parent_code = records$parent_code,
    status      = "current",
    source      = "Philippine Statistics Authority",
    source_url  = SOURCE_URL
  )

  # Per-row extras that do not fit the frozen 10-column canonical schema are
  # kept here, keyed by (level, code), rather than widening the schema.
  from_code_col <- records$source_column == "code"
  extras_idx <- match(records$source_row, raw$source_row)
  pick <- function(v) ifelse(from_code_col, v[extras_idx], NA_character_)
  code_attributes <- tibble::tibble(
    level            = records$level,
    code             = records$code,
    unit_of_quantity = pick(raw$unit),
    pscc_2019        = pick(raw$pscc2019),
    ahtn_2022        = pick(raw$ahtn2022),
    source_row       = records$source_row,
    parent_distance  = records$parent_distance
  )
  keep <- !is.na(code_attributes$unit_of_quantity) |
    !is.na(code_attributes$pscc_2019) |
    !is.na(code_attributes$ahtn_2022)
  code_attributes <- code_attributes[keep, , drop = FALSE]

  dir.create(dirname(OUT_DATA_PATH), recursive = TRUE, showWarnings = FALSE)
  saveRDS(canonical, OUT_DATA_PATH)
  message(sprintf("Saved canonical tibble (%d rows) to %s", nrow(canonical), OUT_DATA_PATH))

  sha256 <- digest::digest(file = RAW_XLSX_PATH, algo = "sha256")

  metadata <- list(
    system = PSCC_SYSTEM,
    version = PSCC_VERSION,
    display_version = PSCC_DISPLAY_VERSION,
    official_name = PSCC_OFFICIAL_NAME,
    display_name = PSCC_DISPLAY_NAME,
    scope = PSCC_SCOPE,
    status = "current",
    source = "Philippine Statistics Authority",
    source_url = SOURCE_URL,
    source_artifact = basename(RAW_XLSX_PATH),
    source_sheet = RAW_SHEET,
    retrieved_at = "2026-08-23",
    sha256 = sha256,
    levels = PSCC_LEVELS,
    parsed_counts = counts,
    # Provenance of the derivations this build performs.
    derivations = list(
      section_code = "Roman numeral as printed in the workbook's 'SECTION <n> - <label>' rows.",
      chapter_code = "Two-digit zero-padded form of the chapter number printed in 'Chapter <n> - <label>' rows; matches the chapter prefix carried by every heading code in that chapter.",
      parent_code = "Nearest ancestor code that actually exists as a row in the workbook (10-digit, then 7-digit, then the 4-digit heading). No intermediate code is invented; unresolvable parents stay NA.",
      description = "Published 4-digit heading text for the code, resolved by verified 4-digit prefix. NA at section/chapter/heading level."
    ),
    # Per-row source columns that do not fit the canonical 10-column schema.
    code_attributes = code_attributes,
    unit_of_quantity_values = sort(unique(stats::na.omit(code_attributes$unit_of_quantity))),
    cross_reference_columns = c("2019 PSCC", "AHTN 2022"),
    numeric_cell_repairs = fixed$repairs,
    duplicate_code_notes = parsed$duplicate_notes,
    anomalies = parsed$anomalies,
    known_limitations = c(
      "The workbook's HS dash-indent qualifier lines carry no code and are not emitted as canonical records; their text is not part of any label.",
      "PSA prints intermediate 6-/8-digit rows only where it chooses to, so parent_code attaches each code to its nearest ancestor that genuinely exists in the workbook rather than to a synthesised intermediate.",
      "Four chapter-96 commodity codes are published with a dot separator instead of a hyphen and are preserved exactly as published."
    )
  )

  saveRDS(metadata, OUT_META_PATH)
  message(sprintf("Saved metadata to %s", OUT_META_PATH))
  message("PSCC 2022 build complete.")

  invisible(list(canonical = canonical, metadata = metadata))
}

if (identical(environment(), globalenv())) {
  if (!exists("new_classification_tibble")) {
    source("R/schema.R")
  }
  main()
}
