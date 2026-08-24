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
#
# ---------------------------------------------------------------------------
# STRUCTURE CONTRACT (POST_CONNECT_STAGING_UI_REFINEMENT_GRAPH.md 9.1-9.16)
# ---------------------------------------------------------------------------
# EVERY non-blank workbook row becomes a node. That includes the code-less
# rows PSA prints to carry hierarchy:
#   * "SUB-CHAPTER I" markers (+ the title line that follows them);
#   * dash-indent descriptor lines ("- Horses :", "- - - - Oxen");
#   * inline group captions ("A. Of four-wheel drive").
# These are structural labels, NOT selectable commodity codes, and are marked
# as such (`level == "structural_group"`, `is_selectable_code == FALSE`).
#
# The display tree is built from the COMBINED evidence PSA prints -- the
# Heading column, the 2022 PSCC column, the description's dash depth and the
# surrounding structural context -- never from code length alone. Where the
# workbook gives no evidence for a parent, none is invented.
#
# AHTN 2022 and 2019 PSCC are CROSS-REFERENCES, not hierarchy levels. The
# 8-digit 2022 PSCC row is therefore called `intermediate_category`, never
# "ahtn subheading".

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
#   section               -- "SECTION I - ..." description rows   (roman numeral)
#   chapter               -- "Chapter 1 - ..." description rows   (2-digit)
#   heading               -- column 1 "Heading"                   (NN.NN, HS 4-digit)
#   subheading            -- column 2, NNNN.NN                    (HS 6-digit)
#   intermediate_category -- column 2, NNNN.NN.NN                 (8-digit)
#   commodity             -- column 2, NNNN.NN.NN-NNN             (11-digit)
#   structural_group      -- code-less structural rows PSA prints to carry
#                            hierarchy (sub-chapters, dash descriptors,
#                            inline captions). Never a selectable code.
PSCC_LEVELS <- c("section", "chapter", "heading", "subheading",
                  "intermediate_category", "commodity", "structural_group")

# Node types are finer-grained than levels; they say WHICH kind of row in the
# workbook produced the node.
PSCC_NODE_TYPES <- c("section", "chapter", "sub_chapter", "heading",
                      "subheading", "intermediate_category", "commodity",
                      "descriptor", "caption")

# Expected raw column order in the "all sections" sheet (header row 1).
RAW_COLS <- c("heading", "code", "description", "unit", "pscc2019", "ahtn2022")
EXPECTED_HEADER <- c("Heading", "2022 PSCC", "DESCRIPTION", "Unit of Quantity")

# Breadcrumb separator (U+203A SINGLE RIGHT-POINTING ANGLE QUOTATION MARK).
BREADCRUMB_SEP <- " › "
NBSP <- "\u00a0"  # U+00A0: the workbook separates dash markers with it on 1,647 rows

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

`%||%` <- function(a, b) if (is.null(a)) b else a

# NA-safe integer default. `%||%` only covers NULL; the depth bookkeeping below
# genuinely starts out as NA_integer_.
na_or <- function(x, default) if (length(x) != 1L || is.na(x)) as.integer(default) else as.integer(x)

# NOTE: R's TRE `[[:space:]]` does NOT match U+00A0, and 1,647 workbook
# descriptions separate their dash markers with a non-breaking space. Replace
# it explicitly BEFORE squishing, otherwise every one of those rows silently
# reads as dash-depth 0 and its hierarchy is lost.
squish <- function(x) {
  x <- gsub(NBSP, " ", x, fixed = TRUE)
  x <- gsub("[\r\n\t]+", " ", x)
  x <- gsub("[[:space:]]+", " ", x)
  trimws(x)
}

# A leading run of hyphens, each optionally followed by spaces. This is PSA's
# printed indentation marker. It is anchored at the start of the string, so
# legitimate interior punctuation ("Pure-bred", "semi-diesel", "SUB-CHAPTER")
# is never touched.
DASH_MARKER_RE <- "^(-[ ]*)+"

dash_depth <- function(desc) {
  if (is.na(desc)) return(0L)
  m <- regmatches(desc, regexpr(DASH_MARKER_RE, desc))
  if (length(m) == 0L || !nzchar(m)) return(0L)
  length(gregexpr("-", m, fixed = TRUE)[[1]])
}

# `display_description`: ONLY the leading structural dash markers are removed,
# plus a trailing " :" that PSA uses to mark a descriptor that opens a group.
# A description that does not start with a dash marker is returned unchanged.
display_description_of <- function(desc) {
  if (is.na(desc)) return(NA_character_)
  if (!grepl(DASH_MARKER_RE, desc)) return(desc)
  out <- sub(DASH_MARKER_RE, "", desc)
  out <- sub("[[:space:]]+:$", "", out)
  out <- trimws(out)
  if (!nzchar(out)) desc else out
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

# A code that still looks like an un-round-tripped IEEE-754 expansion, e.g.
# "8701.2099999999991" or "1.0000000000000001e-05". Used as a post-build
# assertion (9.8: detect suspicious float artifacts rather than coerce).
FLOAT_ARTIFACT_RE <- "([0-9]\\.[0-9]{6,})|([eE][+-][0-9])"

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
# 3. Parse rows into display-tree nodes
# ---------------------------------------------------------------------------

SECTION_RE <- "^SECTION\\s+([IVXLC]+)\\s*[-–—]\\s*(.+)$"
CHAPTER_RE <- "^Chapter\\s+([0-9]+)\\s*[-–—]\\s*(.+)$"
# Chapter 60's heading row inverts the number and the dash.
CHAPTER_ALT_RE <- "^Chapter\\s*[-–—]\\s*([0-9]+)\\s+(.+)$"

classify_code_level <- function(code) {
  if (grepl(SUBHEAD_RE, code))   return("subheading")
  if (grepl(AHTN_RE, code))      return("intermediate_category")
  if (grepl(COMMODITY_RE, code)) return("commodity")
  if (grepl(COMMODITY_DOTTED_RE, code)) return("commodity")
  NA_character_
}

# Structural (code-less) nodes still need a unique, non-NA `code` because the
# canonical schema forbids NA there. The id is deliberately shaped so it can
# NEVER be mistaken for a PSCC code: it carries no digit-dot pattern, it is
# prefixed with the system name and the word STRUCT, and it embeds the
# workbook row it came from. `is_selectable_code` is FALSE for all of them.
structural_id <- function(source_row) sprintf("PSCC-STRUCT-%05d", source_row)

# Is `parent` a genuine code prefix of `child`? Used only against codes that
# actually exist as rows in the workbook, so this never invents an ancestor.
is_code_prefix <- function(parent, child) {
  nchar(child) > nchar(parent) && startsWith(child, parent)
}

parse_pscc <- function(raw) {
  n <- nrow(raw)

  # --- output accumulators (grown as pre-allocated vectors) ----------------
  cap <- n + 500L
  out <- list(
    level = character(cap), node_type = character(cap), code = character(cap),
    label = character(cap), raw_description = character(cap),
    display_description = character(cap), parent_code = character(cap),
    display_depth = integer(cap), breadcrumb = character(cap),
    section_code = character(cap), chapter_code = character(cap),
    heading_code = character(cap), pscc_2022_code = character(cap),
    unit_of_quantity = character(cap), pscc_2019_code = character(cap),
    ahtn_2022_code = character(cap), source_row = integer(cap)
  )
  m <- 0L

  # --- display-tree stack: stk[[d + 1]] is the node currently at depth d ---
  stk <- list()

  cur_section <- NA_character_
  cur_chapter <- NA_character_
  cur_heading <- NA_character_
  container_depth <- NA_integer_   # depth of the chapter or sub-chapter in force
  heading_depth   <- NA_integer_
  last_depth      <- NA_integer_

  seen <- new.env(parent = emptyenv())     # "level\rcode" -> label
  subchapter_titles <- list()              # record index (as string) -> title
  duplicate_notes <- list()
  anomalies       <- list()
  depth_clamps    <- 0L
  dash_prefix_conflicts <- 0L
  empty_after_strip     <- 0L

  crumb_of <- function(node_type, code, label) {
    if (identical(node_type, "section")) return(paste("Section", code))
    if (identical(node_type, "chapter")) return(paste("Chapter", as.integer(code)))
    if (identical(node_type, "heading")) return(paste("Heading", code))
    label
  }

  # Places a node in the display tree at `depth`, emits it, and makes it the
  # innermost node at that depth. Returns the depth actually used.
  emit <- function(level, node_type, code, label, raw_desc, disp_desc, depth,
                    unit = NA_character_, p2019 = NA_character_,
                    ahtn = NA_character_, source_row) {
    depth <- as.integer(depth)
    stopifnot(!is.na(depth), depth >= 0L, depth <= length(stk))
    parent <- if (depth == 0L) NA_character_ else stk[[depth]]$code
    crumb <- if (depth == 0L) NA_character_ else {
      paste(vapply(stk[seq_len(depth)], function(z) z$crumb, character(1)),
            collapse = BREADCRUMB_SEP)
    }

    seen[[paste(level, code, sep = "\r")]] <<- list(label = label, depth = depth)

    m <<- m + 1L
    out$level[m]               <<- level
    out$node_type[m]           <<- node_type
    out$code[m]                <<- code
    out$label[m]               <<- label
    out$raw_description[m]     <<- raw_desc
    out$display_description[m] <<- disp_desc
    out$parent_code[m]         <<- parent
    out$display_depth[m]       <<- depth
    out$breadcrumb[m]          <<- crumb
    out$section_code[m]        <<- cur_section
    out$chapter_code[m]        <<- cur_chapter
    out$heading_code[m]        <<- cur_heading
    # Only column B of the workbook is a "2022 PSCC code". Section roman
    # numerals, chapter numbers and Heading-column values live in their own
    # fields and must never be surfaced as the 2022 PSCC code.
    out$pscc_2022_code[m]      <<- if (level %in% c("subheading", "intermediate_category", "commodity")) code else NA_character_
    out$unit_of_quantity[m]    <<- unit
    out$pscc_2019_code[m]      <<- p2019
    out$ahtn_2022_code[m]      <<- ahtn
    out$source_row[m]          <<- source_row

    stk <<- c(stk[seq_len(depth)],
              list(list(code = code,
                        crumb = crumb_of(node_type, code, disp_desc))))
    last_depth <<- depth
    depth
  }

  # Same placement, but for a (level, code) already emitted earlier: the row
  # is folded away and the RETAINED node is pushed instead, so any deeper rows
  # that follow still attach to a real ancestor. The retained node's ORIGINAL
  # depth is reused -- otherwise its later children would record a depth that
  # is not `parent depth + 1`.
  push_existing <- function(key, code, node_type, disp_desc) {
    depth <- min(as.integer(seen[[key]]$depth), length(stk))
    stk <<- c(stk[seq_len(depth)],
              list(list(code = code, crumb = crumb_of(node_type, code, disp_desc))))
    last_depth <<- depth
  }

  # Depth for a code-bearing row that prints no dash marker: attach it under
  # the deepest ancestor ALREADY ON THE STACK whose code is a genuine prefix
  # of this code. Falls back to the heading. Never invents an intermediate.
  depth_by_code_prefix <- function(code) {
    if (is.na(heading_depth)) return(min(length(stk), na_or(container_depth, 0L) + 1L))
    d <- length(stk) - 1L
    while (d > heading_depth) {
      if (is_code_prefix(stk[[d + 1L]]$code, code)) return(d + 1L)
      d <- d - 1L
    }
    heading_depth + 1L
  }

  consumed <- rep(FALSE, n)

  for (i in seq_len(n)) {
    if (consumed[i]) next

    hd     <- raw$heading[i]
    cd     <- raw$code[i]
    desc   <- raw$description[i]
    row_no <- raw$source_row[i]

    if (is.na(hd) && is.na(cd) && is.na(desc)) next

    # ---------------- code-less rows -------------------------------------
    if (is.na(hd) && is.na(cd)) {
      mm <- regmatches(desc, regexec(SECTION_RE, desc))[[1]]
      if (length(mm) == 3L) {
        cur_section <- mm[2]
        cur_chapter <- NA_character_
        cur_heading <- NA_character_
        container_depth <- NA_integer_
        heading_depth <- NA_integer_
        stk <- list()
        emit("section", "section", cur_section, mm[3], desc, mm[3], 0L,
             source_row = row_no)
        next
      }

      mm <- regmatches(desc, regexec(CHAPTER_RE, desc))[[1]]
      if (length(mm) != 3L) {
        mm <- regmatches(desc, regexec(CHAPTER_ALT_RE, desc))[[1]]
      }
      if (length(mm) == 3L) {
        if (is.na(cur_section)) {
          stop(sprintf("Chapter row %d ('%s') appears before any SECTION row.", row_no, desc),
               call. = FALSE)
        }
        cur_chapter <- sprintf("%02d", as.integer(mm[2]))
        cur_heading <- NA_character_
        heading_depth <- NA_integer_
        container_depth <- emit("chapter", "chapter", cur_chapter, mm[3], desc,
                                mm[3], 1L, source_row = row_no)
        next
      }

      if (startsWith(desc, "SUB-CHAPTER")) {
        if (is.na(cur_chapter)) {
          stop(sprintf("Sub-chapter row %d ('%s') appears before any Chapter row.",
                        row_no, desc), call. = FALSE)
        }
        # PSA prints the marker and its title on two consecutive lines. The
        # marker becomes the node; the title is preserved verbatim in the
        # canonical `description` column rather than being concatenated into
        # the label (which would rewrite official text).
        title <- if (i < n && is.na(raw$heading[i + 1L]) && is.na(raw$code[i + 1L]) &&
                      !is.na(raw$description[i + 1L])) raw$description[i + 1L] else NA_character_
        if (!is.na(title)) consumed[i + 1L] <- TRUE
        cur_heading <- NA_character_
        heading_depth <- NA_integer_
        container_depth <- emit("structural_group", "sub_chapter",
                                 structural_id(row_no), desc, desc, desc, 2L,
                                 source_row = row_no)
        subchapter_titles[[as.character(m)]] <- title
        next
      }

      dd <- dash_depth(desc)
      disp <- display_description_of(desc)
      if (!identical(disp, desc) && !nzchar(disp)) empty_after_strip <- empty_after_strip + 1L
      if (grepl("^-[^ ]", desc)) {
        anomalies[[length(anomalies) + 1L]] <- list(
          source_row = row_no, code = NA_character_, value = desc,
          note = "Dash hierarchy marker printed without a following space; read as depth-1 and preserved verbatim in raw_description."
        )
      }

      if (is.na(heading_depth)) {
        # A structural line printed before the chapter's first heading.
        depth <- min(na_or(container_depth, 0L) + 1L, length(stk))
      } else if (dd >= 1L) {
        depth <- heading_depth + dd
        if (depth > length(stk)) { depth <- length(stk); depth_clamps <- depth_clamps + 1L }
      } else {
        # Inline caption printed among sibling rows. It is placed AS A PEER of
        # the row before it -- the workbook gives no evidence that it parents
        # the rows that follow, and hierarchy is never invented.
        depth <- max(na_or(last_depth, heading_depth + 1L), heading_depth + 1L)
        depth <- min(depth, length(stk))
      }
      emit("structural_group", if (dd >= 1L) "descriptor" else "caption",
           structural_id(row_no), disp, desc, disp, depth, source_row = row_no)
      next
    }

    # ---------------- Heading column --------------------------------------
    if (!is.na(hd)) {
      if (is.na(desc)) {
        stop(sprintf("Heading '%s' at row %d has no description text.", hd, row_no), call. = FALSE)
      }
      ch <- substr(gsub("\\.", "", hd), 1, 2)
      if (is.na(cur_chapter) || !identical(ch, cur_chapter)) {
        stop(sprintf("Heading '%s' at row %d does not sit under its own chapter (current chapter: %s).",
                      hd, row_no, cur_chapter %||% "none"), call. = FALSE)
      }
      cur_heading <- hd
      hdepth <- min(na_or(container_depth, 0L) + 1L, length(stk))
      key <- paste("heading", hd, sep = "\r")
      disp <- display_description_of(desc)
      if (!is.null(seen[[key]])) {
        duplicate_notes[[length(duplicate_notes) + 1L]] <- list(
          level = "heading", code = hd, source_row = row_no,
          kept_label = seen[[key]]$label, dropped_label = disp
        )
        push_existing(key, hd, "heading", disp)
        heading_depth <- last_depth
      } else {
        heading_depth <- emit("heading", "heading", hd, disp, desc, disp, hdepth,
                               source_row = row_no)
      }
    }

    # ---------------- 2022 PSCC column ------------------------------------
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
          source_row = row_no, code = cd, value = cd,
          note = "11-digit commodity code published with a dot separator instead of a hyphen; preserved verbatim."
        )
      }

      dd <- dash_depth(desc)
      disp <- display_description_of(desc)
      if (grepl("^-[^ ]", desc)) {
        anomalies[[length(anomalies) + 1L]] <- list(
          source_row = row_no, code = cd, value = desc,
          note = "Dash hierarchy marker printed without a following space; read as depth-1 and preserved verbatim in raw_description."
        )
      }

      prefix_depth <- depth_by_code_prefix(cd)
      if (is.na(heading_depth)) {
        depth <- min(max(prefix_depth, 1L), length(stk))
      } else if (dd >= 1L) {
        depth <- heading_depth + dd
        if (depth > length(stk)) { depth <- length(stk); depth_clamps <- depth_clamps + 1L }
        if (depth != prefix_depth) dash_prefix_conflicts <- dash_prefix_conflicts + 1L
      } else {
        depth <- prefix_depth
      }

      key <- paste(level, cd, sep = "\r")
      if (!is.null(seen[[key]])) {
        duplicate_notes[[length(duplicate_notes) + 1L]] <- list(
          level = level, code = cd, source_row = row_no,
          kept_label = seen[[key]]$label, dropped_label = disp
        )
        push_existing(key, cd, level, disp)
      } else {
        emit(level, level, cd, disp, desc, disp, depth,
             unit = raw$unit[i], p2019 = raw$pscc2019[i], ahtn = raw$ahtn2022[i],
             source_row = row_no)
      }
    }
  }

  records <- tibble::tibble(
    level = out$level[seq_len(m)],
    node_type = out$node_type[seq_len(m)],
    code = out$code[seq_len(m)],
    label = out$label[seq_len(m)],
    raw_description = out$raw_description[seq_len(m)],
    display_description = out$display_description[seq_len(m)],
    parent_code = out$parent_code[seq_len(m)],
    display_depth = out$display_depth[seq_len(m)],
    breadcrumb = out$breadcrumb[seq_len(m)],
    section_code = out$section_code[seq_len(m)],
    chapter_code = out$chapter_code[seq_len(m)],
    heading_code = out$heading_code[seq_len(m)],
    pscc_2022_code = out$pscc_2022_code[seq_len(m)],
    unit_of_quantity = out$unit_of_quantity[seq_len(m)],
    pscc_2019_code = out$pscc_2019_code[seq_len(m)],
    ahtn_2022_code = out$ahtn_2022_code[seq_len(m)],
    source_row = out$source_row[seq_len(m)],
    source_order = seq_len(m)
  )

  list(
    records = records,
    subchapter_titles = subchapter_titles,
    duplicate_notes = duplicate_notes,
    anomalies = anomalies,
    depth_clamps = depth_clamps,
    dash_prefix_conflicts = dash_prefix_conflicts,
    empty_after_strip = empty_after_strip,
    consumed_subchapter_titles = sum(consumed)
  )
}

# ---------------------------------------------------------------------------
# 4. Descriptive context
# ---------------------------------------------------------------------------
# Many published labels are bare HS continuations ("Other"). The canonical
# `description` column is filled with the published 4-digit heading text the
# node sits under, resolved from the heading actually in force when the row
# was parsed. Nothing is invented: the text is PSA's own heading wording.
# Sub-chapter nodes instead carry the title line PSA prints beneath them.

attach_descriptions <- function(records, subchapter_titles) {
  heading_label <- new.env(parent = emptyenv())
  for (j in which(records$node_type == "heading")) {
    heading_label[[records$code[j]]] <- records$label[j]
  }

  desc <- rep(NA_character_, nrow(records))
  under_heading <- !is.na(records$heading_code) & records$node_type != "heading"
  for (j in which(under_heading)) {
    v <- heading_label[[records$heading_code[j]]]
    if (!is.null(v)) desc[j] <- v
  }
  for (k in names(subchapter_titles)) {
    desc[as.integer(k)] <- subchapter_titles[[k]]
  }
  records$description <- desc
  records
}

# ---------------------------------------------------------------------------
# 5. Validation report + hard failures
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
  unknown_types <- setdiff(unique(records$node_type), PSCC_NODE_TYPES)
  if (length(unknown_types) > 0) {
    stop(sprintf("Records carry node types outside the declared set: %s",
                  paste(unknown_types, collapse = ", ")), call. = FALSE)
  }

  all_codes <- unique(records$code)
  orphan <- records$parent_code[!is.na(records$parent_code)]
  missing_parents <- setdiff(orphan, all_codes)
  if (length(missing_parents) > 0) {
    stop(sprintf("Non-NA parent_code values that are not real PSCC codes: %s",
                  paste(head(missing_parents, 10), collapse = ", ")), call. = FALSE)
  }

  # 9.8: suspicious float-like code artifacts must be detected, never shipped.
  float_like <- records$code[grepl(FLOAT_ARTIFACT_RE, records$code)]
  if (length(float_like) > 0) {
    stop(sprintf("Code(s) still look like floating-point expansions: %s",
                  paste(head(float_like, 10), collapse = ", ")), call. = FALSE)
  }
  xref <- c(records$pscc_2019_code, records$ahtn_2022_code)
  xref <- xref[!is.na(xref)]
  float_xref <- xref[grepl(FLOAT_ARTIFACT_RE, xref)]
  if (length(float_xref) > 0) {
    stop(sprintf("Cross-reference code(s) look like floating-point expansions: %s",
                  paste(head(float_xref, 10), collapse = ", ")), call. = FALSE)
  }

  # No structural node may masquerade as a selectable PSCC code.
  struct <- records$level == "structural_group"
  if (any(!is.na(records$pscc_2022_code[struct]))) {
    stop("A structural_group node carries a 2022 PSCC code. Aborting build.", call. = FALSE)
  }
  if (any(grepl("[0-9]", records$code[struct]) & !grepl("^PSCC-STRUCT-", records$code[struct]))) {
    stop("A structural_group node has a code that is not a PSCC-STRUCT id.", call. = FALSE)
  }

  # Leading dash markers must not survive into the public label.
  leaky <- sum(grepl(DASH_MARKER_RE, records$label))
  if (leaky > 0) {
    stop(sprintf("%d label(s) still begin with a structural dash marker.", leaky), call. = FALSE)
  }

  counts <- table(factor(records$level, levels = PSCC_LEVELS))
  type_counts <- table(factor(records$node_type, levels = PSCC_NODE_TYPES))
  leading_zero <- sum(grepl("^0", records$code))
  punctuated   <- sum(grepl("[.-]", records$pscc_2022_code[!is.na(records$pscc_2022_code)]))
  hyphenated   <- sum(grepl("-", records$pscc_2022_code[!is.na(records$pscc_2022_code)]))

  message("")
  message("PSCC 2022 build validation report")
  message("---------------------------------")
  message(sprintf("  raw workbook rows            : %d", nrow(raw)))
  message(sprintf("  canonical records            : %d", nrow(records)))
  for (lv in PSCC_LEVELS) {
    message(sprintf("    %-22s : %d", lv, as.integer(counts[[lv]])))
  }
  message("  node types:")
  for (nt in PSCC_NODE_TYPES) {
    message(sprintf("    %-22s : %d", nt, as.integer(type_counts[[nt]])))
  }
  message(sprintf("  selectable codes             : %d", sum(!struct)))
  message(sprintf("  structural labels            : %d", sum(struct)))
  message(sprintf("  codes with a leading zero    : %d", leading_zero))
  message(sprintf("  punctuated 2022 PSCC codes   : %d", punctuated))
  message(sprintf("  hyphenated 2022 PSCC codes   : %d", hyphenated))
  message(sprintf("  max display depth            : %d", max(records$display_depth)))
  message(sprintf("  sub-chapter titles folded    : %d", parsed$consumed_subchapter_titles))
  message(sprintf("  duplicate source rows folded : %d", length(parsed$duplicate_notes)))
  message(sprintf("  separator/marker anomalies   : %d", length(parsed$anomalies)))
  message(sprintf("  depth clamps applied         : %d", parsed$depth_clamps))
  message(sprintf("  dash/prefix depth conflicts  : %d", parsed$dash_prefix_conflicts))

  if (length(parsed$duplicate_notes) > 0) {
    warning(sprintf(
      "%d workbook rows repeat a code already emitted at the same level; first occurrence kept, alternates recorded in metadata$duplicate_code_notes.",
      length(parsed$duplicate_notes)
    ), call. = FALSE)
  }
  if (length(parsed$anomalies) > 0) {
    warning(sprintf(
      "%d source anomaly/anomalies preserved verbatim; see metadata$anomalies.",
      length(parsed$anomalies)
    ), call. = FALSE)
  }

  list(
    by_level = as.list(setNames(as.integer(counts), PSCC_LEVELS)),
    by_node_type = as.list(setNames(as.integer(type_counts), PSCC_NODE_TYPES)),
    total = nrow(records),
    selectable_codes = sum(!struct),
    structural_labels = sum(struct),
    leading_zero_codes = leading_zero,
    punctuated_codes = punctuated,
    hyphenated_codes = hyphenated,
    duplicate_keys = 0L,
    unresolved_parents = sum(is.na(records$parent_code) & records$level != "section"),
    max_display_depth = max(records$display_depth),
    depth_clamps = parsed$depth_clamps,
    dash_prefix_conflicts = parsed$dash_prefix_conflicts,
    subchapter_titles_folded = parsed$consumed_subchapter_titles,
    raw_rows = nrow(raw)
  )
}

# ---------------------------------------------------------------------------
# 6. Main
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
  records <- attach_descriptions(parsed$records, parsed$subchapter_titles)

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

  # Display/source-form metadata rides ALONGSIDE the frozen canonical schema.
  # R/search.R does `matched[, c(CLASSIFICATION_SCHEMA_COLUMNS, extras)]`, so
  # these must come strictly AFTER the canonical ten, in this order.
  canonical$node_type           <- records$node_type
  canonical$display_depth       <- records$display_depth
  canonical$display_description <- records$display_description
  canonical$raw_description     <- records$raw_description
  canonical$breadcrumb          <- records$breadcrumb
  canonical$section_code        <- records$section_code
  canonical$chapter_code        <- records$chapter_code
  canonical$heading_code        <- records$heading_code
  canonical$pscc_2022_code      <- records$pscc_2022_code
  canonical$unit_of_quantity    <- records$unit_of_quantity
  canonical$pscc_2019_code      <- records$pscc_2019_code
  canonical$ahtn_2022_code      <- records$ahtn_2022_code
  canonical$is_selectable_code  <- records$level != "structural_group"
  canonical$is_structural_label <- records$level == "structural_group"
  canonical$source_row          <- records$source_row
  canonical$source_order        <- records$source_order

  stopifnot(identical(names(canonical)[seq_along(CLASSIFICATION_SCHEMA_COLUMNS)],
                       CLASSIFICATION_SCHEMA_COLUMNS))

  # Legacy per-code attribute table, retained for callers that read metadata
  # rather than the artifact's extra columns.
  code_attributes <- tibble::tibble(
    level            = records$level,
    code             = records$code,
    unit_of_quantity = records$unit_of_quantity,
    pscc_2019        = records$pscc_2019_code,
    ahtn_2022        = records$ahtn_2022_code,
    source_row       = records$source_row,
    display_depth    = records$display_depth
  )
  keep <- !is.na(code_attributes$unit_of_quantity) |
    !is.na(code_attributes$pscc_2019) |
    !is.na(code_attributes$ahtn_2022)
  code_attributes <- code_attributes[keep, , drop = FALSE]

  dir.create(dirname(OUT_DATA_PATH), recursive = TRUE, showWarnings = FALSE)
  saveRDS(canonical, OUT_DATA_PATH)
  message(sprintf("Saved canonical tibble (%d rows x %d cols) to %s",
                   nrow(canonical), ncol(canonical), OUT_DATA_PATH))

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
    node_types = PSCC_NODE_TYPES,
    breadcrumb_separator = BREADCRUMB_SEP,
    extra_columns = setdiff(names(canonical), CLASSIFICATION_SCHEMA_COLUMNS),
    parsed_counts = counts,
    # Provenance of the derivations this build performs.
    derivations = list(
      section_code = "Roman numeral as printed in the workbook's 'SECTION <n> - <label>' rows.",
      chapter_code = "Two-digit zero-padded form of the chapter number printed in 'Chapter <n> - <label>' rows; matches the chapter prefix carried by every heading code in that chapter.",
      structural_code = "Code-less structural rows (sub-chapters, dash descriptors, inline captions) get a synthetic PSCC-STRUCT-<workbook row> id so they can occupy the canonical `code` column. It is deliberately unmistakable for a PSCC code and is flagged is_selectable_code = FALSE.",
      parent_code = "Immediate parent in the display tree built from the workbook's own printed structure: SECTION > Chapter > (SUB-CHAPTER) > Heading > dash-indent depth, with dash-less coded rows attached to the deepest ancestor already on the stack whose code is a genuine prefix of theirs. No intermediate code is invented.",
      display_depth = "Depth of the node in that same display tree (section = 0).",
      display_description = "Source DESCRIPTION with ONLY the leading structural dash markers removed, plus a trailing ' :' where the dash markers were present. Interior hyphens are never touched. Rows without a leading dash marker are unchanged.",
      raw_description = "The workbook DESCRIPTION cell verbatim (whitespace normalised only, including U+00A0 -> space).",
      label = "Equal to display_description; raw_description keeps the untouched source text.",
      breadcrumb = "Ancestor path of the node in the display tree, joined with ' › ' -- e.g. 'Section I › Chapter 1 › Heading 01.01 › Horses'. Excludes the node itself.",
      description = "Published 4-digit heading text for every node under a heading; the title line PSA prints beneath a SUB-CHAPTER marker for sub-chapter nodes; NA at section/chapter/heading level.",
      sub_chapter = "A 'SUB-CHAPTER <n>' marker row and the title line immediately beneath it become ONE node: the marker is the label, the title is the canonical description. Neither text is rewritten."
    ),
    code_attributes = code_attributes,
    unit_of_quantity_values = sort(unique(stats::na.omit(code_attributes$unit_of_quantity))),
    cross_reference_columns = c("2019 PSCC", "AHTN 2022"),
    cross_reference_contract = paste(
      "'2019 PSCC' and 'AHTN 2022' are cross-references, never hierarchy levels",
      "and never a substitute for the 2022 PSCC code. A search that matches on",
      "one of them must say so explicitly (see pscc_match_reason_text())."
    ),
    numeric_cell_repairs = fixed$repairs,
    duplicate_code_notes = parsed$duplicate_notes,
    anomalies = parsed$anomalies,
    known_limitations = c(
      "Inline caption rows such as 'A. Of four-wheel drive' carry no code and no dash marker. They are preserved in source order as PEERS of the row above them; the workbook gives no unambiguous evidence that they parent the rows below, and hierarchy is never invented.",
      "Two dash markers in chapters 87 and 89 are printed without a following space ('-With both...'); they are read as depth 1 and the raw text is preserved verbatim.",
      "PSA prints intermediate 6-/8-digit rows only where it chooses to, so a dash-less coded row attaches to the deepest ancestor that genuinely exists in the workbook rather than to a synthesised intermediate.",
      "Four chapter-96 commodity codes are published with a dot separator instead of a hyphen and are preserved exactly as published.",
      "Structural nodes are addressable by a synthetic PSCC-STRUCT-<row> id. That id is NOT a PSA code and must never be presented as one."
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
