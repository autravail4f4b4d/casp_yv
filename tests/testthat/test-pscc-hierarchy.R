# PSCC 2022 hierarchy, display-metadata, cross-reference and presentation
# tests -- the 20 checks required by
# POST_CONNECT_STAGING_UI_REFINEMENT_GRAPH.md 9.15.
#
# These run against the COMMITTED runtime artifact (data/pscc_2022.rds), never
# against the 26,551-row Excel workbook: the build script parses the workbook
# once, the tests verify what it produced. Every fixture below is a real value
# printed in "data-raw/pscc.xlsx" ("all sections").

pscc_df <- function() pscc2022_get()

row_for <- function(code, level = NULL) {
  df <- pscc_df()
  r <- df[df$code == code, , drop = FALSE]
  if (!is.null(level)) r <- r[r$level == level, , drop = FALSE]
  r
}

# --- 1. Section row preservation -------------------------------------------

test_that("9.15/1 section rows are preserved with their roman numerals", {
  sections <- pscc2022_get(level = "section")

  expect_equal(nrow(sections), 21L)
  expect_true(all(grepl("^[IVXLC]+$", sections$code)))
  expect_true("I" %in% sections$code)
  expect_true("XX" %in% sections$code)

  s1 <- row_for("I", "section")
  expect_identical(s1$label[1], "LIVE ANIMALS; ANIMAL PRODUCTS")
  expect_identical(s1$node_type[1], "section")
  expect_equal(s1$display_depth[1], 0L)
  expect_true(is.na(s1$parent_code[1]))
  expect_true(is.na(s1$breadcrumb[1]))
})

# --- 2. Chapter row preservation -------------------------------------------

test_that("9.15/2 chapter rows are preserved under their section", {
  chapters <- pscc2022_get(level = "chapter")

  expect_equal(nrow(chapters), 98L)
  expect_true(all(grepl("^[0-9]{2}$", chapters$code)))

  c1 <- row_for("01", "chapter")
  expect_identical(c1$label[1], "Live animals")
  expect_identical(c1$parent_code[1], "I")
  expect_identical(c1$section_code[1], "I")
  expect_equal(c1$display_depth[1], 1L)
  expect_identical(c1$breadcrumb[1], "Section I")

  # The two-digit chapter code keeps its leading zero.
  expect_false("1" %in% chapters$code)
})

# --- 3. Heading row preservation -------------------------------------------

test_that("9.15/3 Heading-column rows are preserved as their own nodes", {
  headings <- pscc2022_get(level = "heading")

  # The spec's 9.1 audit says 1,240; the workbook actually carries 1,245.
  expect_equal(nrow(headings), 1245L)
  expect_true(all(grepl("^[0-9]{2}\\.[0-9]{2}$", headings$code)))

  h <- row_for("01.01", "heading")
  expect_identical(h$label[1], "Live horses, asses, mules and hinnies.")
  expect_identical(h$parent_code[1], "01")
  expect_identical(h$chapter_code[1], "01")
  expect_identical(h$breadcrumb[1], "Section I › Chapter 1")
  # A Heading is not a "2022 PSCC" (column B) value.
  expect_true(is.na(h$pscc_2022_code[1]))
})

# --- 4. Descriptor-only row preservation ------------------------------------

test_that("9.15/4 descriptor-only hierarchy rows reach the artifact", {
  df <- pscc_df()
  struct <- df[df$level == "structural_group", , drop = FALSE]

  # 2,325 dash descriptors + 80 inline captions + 33 sub-chapter markers.
  expect_equal(nrow(struct), 2438L)
  expect_equal(sum(struct$node_type == "descriptor"), 2325L)
  expect_equal(sum(struct$node_type == "caption"), 80L)
  expect_equal(sum(struct$node_type == "sub_chapter"), 33L)

  # The chapter-1 "- Horses :" descriptor is a real node with real children.
  horses <- df[df$raw_description == "- Horses :" & df$heading_code == "01.01", , drop = FALSE]
  expect_equal(nrow(horses), 1L)
  expect_identical(horses$label[1], "Horses")
  expect_identical(horses$node_type[1], "descriptor")
  expect_identical(horses$parent_code[1], "01.01")

  # Structural nodes are never selectable codes and never carry a PSCC code.
  expect_true(all(!struct$is_selectable_code))
  expect_true(all(struct$is_structural_label))
  expect_true(all(is.na(struct$pscc_2022_code)))
  expect_true(all(grepl("^PSCC-STRUCT-[0-9]{5}$", struct$code)))

  # ...and nothing outside that level is marked structural.
  expect_true(all(df$is_selectable_code[df$level != "structural_group"]))
})

# --- 5. Six-digit intermediate code preservation ----------------------------

test_that("9.15/5 six-digit subheadings are preserved", {
  sub <- pscc2022_get(level = "subheading")

  expect_equal(nrow(sub), 1983L)
  expect_true(all(grepl("^[0-9]{4}\\.[0-9]{2}$", sub$code)))

  r <- row_for("0101.30", "subheading")
  expect_equal(nrow(r), 1L)
  expect_identical(r$label[1], "Asses")
  expect_identical(r$raw_description[1], "- Asses :")
  expect_identical(r$pscc_2022_code[1], "0101.30")
  expect_identical(r$parent_code[1], "01.01")
})

# --- 6. Eight-digit intermediate code preservation --------------------------

test_that("9.15/6 eight-digit intermediate categories are preserved", {
  mid <- pscc2022_get(level = "intermediate_category")

  # Spec 9.1 claims 2,297 eight-digit rows; the workbook has 2,350, of which
  # 4 repeat a code already emitted at that level and are folded.
  expect_equal(nrow(mid), 2346L)
  expect_true(all(grepl("^[0-9]{4}\\.[0-9]{2}\\.[0-9]{2}$", mid$code)))

  r <- row_for("0101.29.00", "intermediate_category")
  expect_equal(nrow(r), 1L)
  expect_identical(r$label[1], "Other")
  expect_identical(r$pscc_2022_code[1], "0101.29.00")
  expect_identical(r$level[1], "intermediate_category")

  # This is NOT an "AHTN subheading": AHTN is a cross-reference column.
  expect_false(any(grepl("ahtn", mid$level, ignore.case = TRUE)))
  expect_identical(pscc_level_label("intermediate_category"), "Intermediate category")
})

# --- 7. Detailed hyphenated commodity code preservation ---------------------

test_that("9.15/7 detailed 11-digit commodity codes are preserved", {
  com <- pscc2022_get(level = "commodity")

  # Spec 9.1 claims 15,926; the workbook has 16,049.
  expect_equal(nrow(com), 16049L)

  r <- row_for("0101.21.00-000", "commodity")
  expect_equal(nrow(r), 1L)
  expect_identical(r$pscc_2022_code[1], "0101.21.00-000")
  expect_identical(r$label[1], "Pure-bred breeding animals")
  expect_identical(r$raw_description[1], "- - Pure-bred breeding animals")
  expect_true(r$is_selectable_code[1])
})

# --- 8. Leading zero preservation -------------------------------------------

test_that("9.15/8 leading zeros survive at every level", {
  codes <- pscc_df()$code

  for (fx in c("01", "01.01", "0101.30", "0101.29.00", "0101.21.00-000",
                "0105.11.10-000", "09.03")) {
    expect_true(fx %in% codes, info = sprintf("leading-zero code '%s' missing", fx))
  }
  for (bad in c("1", "1.01", "101.30", "101.29.00", "101.21.00-000")) {
    expect_false(bad %in% codes, info = sprintf("de-zeroed code '%s' leaked in", bad))
  }
  expect_true(is.character(codes))
})

# --- 9. Punctuation preservation in codes -----------------------------------

test_that("9.15/9 dots and hyphens in codes survive verbatim", {
  df <- pscc_df()
  codes <- df$code

  expect_true("0101.29.00-001" %in% codes)
  expect_true("3808.52.20-002" %in% codes)
  # Four chapter-96 codes publish a dot where the hyphen normally goes.
  expect_true("9620.00.90.100" %in% codes)
  expect_true("9620.00.90.900" %in% codes)
  expect_false("9620.00.90-100" %in% codes)

  # Cross-references keep their own punctuation and "ex" partial-match prefix.
  xref <- stats::na.omit(df$pscc_2019_code)
  expect_true("ex9620.00.90-09" %in% xref)
})

# --- 10/11/12. Unit + cross-reference preservation --------------------------

test_that("9.15/10 Unit of Quantity is preserved on the artifact row", {
  df <- pscc_df()
  r <- row_for("0101.21.00-000", "commodity")
  expect_identical(r$unit_of_quantity[1], "u")
  expect_identical(row_for("0205.00.00-000", "commodity")$unit_of_quantity[1], "kg")

  expect_equal(sum(!is.na(df$unit_of_quantity)), 16049L)
  # Units belong to the coded row they were printed on -- never to a
  # structural label or a Heading record.
  expect_true(all(is.na(df$unit_of_quantity[df$level == "structural_group"])))
  expect_true(all(is.na(df$unit_of_quantity[df$level %in% c("section", "chapter", "heading")])))
})

test_that("9.15/11 the 2019 PSCC cross-reference is preserved", {
  df <- pscc_df()
  expect_identical(row_for("0101.21.00-000", "commodity")$pscc_2019_code[1], "0101.21.00-00")
  expect_identical(row_for("0101.29.00-001", "commodity")$pscc_2019_code[1], "0101.29.00-01")
  expect_equal(sum(!is.na(df$pscc_2019_code)), 16049L)
  expect_false(any(grepl("[0-9]\\.[0-9]{6,}", stats::na.omit(df$pscc_2019_code))))
})

test_that("9.15/12 the AHTN 2022 cross-reference is preserved", {
  df <- pscc_df()
  expect_identical(row_for("0101.21.00-000", "commodity")$ahtn_2022_code[1], "0101.21.00")
  expect_gt(sum(!is.na(df$ahtn_2022_code)), 15000L)
  expect_false(any(grepl("[0-9]\\.[0-9]{6,}", stats::na.omit(df$ahtn_2022_code))))

  # An AHTN value is never copied into the 2022 PSCC code.
  r <- row_for("0101.29.00-001", "commodity")
  expect_identical(r$ahtn_2022_code[1], "0101.29.00")
  expect_identical(r$pscc_2022_code[1], "0101.29.00-001")
  expect_false(identical(r$pscc_2022_code[1], r$ahtn_2022_code[1]))
})

# --- 13. Representative breadcrumb ------------------------------------------

test_that("9.15/13 the chapter-1 breadcrumb matches the published hierarchy", {
  r <- row_for("0101.21.00-000", "commodity")

  expect_identical(
    r$breadcrumb[1],
    paste("Section I", "Chapter 1", "Heading 01.01", "Horses", sep = " › ")
  )
  expect_identical(r$section_code[1], "I")
  expect_identical(r$chapter_code[1], "01")
  expect_identical(r$heading_code[1], "01.01")
  expect_equal(r$display_depth[1], 4L)

  # One level deeper: the descriptor "Other" is inserted, not skipped.
  expect_identical(
    row_for("0101.29.00-001", "commodity")$breadcrumb[1],
    paste("Section I", "Chapter 1", "Heading 01.01", "Horses", "Other", sep = " › ")
  )

  # Every non-root node has a breadcrumb, and only sections lack one.
  df <- pscc_df()
  expect_true(all(is.na(df$breadcrumb[df$level == "section"])))
  expect_false(any(is.na(df$breadcrumb[df$level != "section"])))
})

# --- 14. display_description exposes no dash markers ------------------------

test_that("9.15/14 public text never exposes leading hierarchy dashes", {
  df <- pscc_df()

  expect_false(any(grepl("^[[:space:]]*-[[:space:]]", df$display_description)))
  expect_false(any(grepl("^[[:space:]]*-[[:space:]]", df$label)))
  expect_identical(df$label, df$display_description)

  expect_identical(row_for("0101.21.00-000", "commodity")$display_description[1],
                    "Pure-bred breeding animals")
  expect_identical(row_for("0101.30", "subheading")$display_description[1], "Asses")

  # Interior hyphens are legitimate punctuation and must survive untouched.
  expect_true(any(grepl("Pure-bred", df$display_description, fixed = TRUE)))
  expect_true(any(grepl("SUB-CHAPTER", df$display_description, fixed = TRUE)))
  expect_true(any(grepl("semi-diesel", df$display_description, fixed = TRUE)))

  # A description that never carried a dash marker is returned untouched --
  # including a trailing colon it printed itself. (SECTION / Chapter rows are
  # the documented exception: their label is the title PSA prints after the
  # "SECTION I - " / "Chapter 1 - " prefix, and the whole printed line is
  # still kept verbatim in raw_description.)
  untouched <- df[!grepl("^-", df$raw_description) &
                    !df$node_type %in% c("section", "chapter"), , drop = FALSE]
  expect_identical(untouched$display_description, untouched$raw_description)
  expect_gt(nrow(untouched), 8000L)

  sec <- row_for("I", "section")
  expect_identical(sec$raw_description[1], "SECTION I - LIVE ANIMALS; ANIMAL PRODUCTS")
  expect_identical(sec$display_description[1], "LIVE ANIMALS; ANIMAL PRODUCTS")
})

# --- 15. raw_description is unchanged ---------------------------------------

test_that("9.15/15 raw_description keeps the exact source text", {
  df <- pscc_df()

  expect_identical(row_for("0101.21.00-000", "commodity")$raw_description[1],
                    "- - Pure-bred breeding animals")
  expect_identical(row_for("0101.30", "subheading")$raw_description[1], "- Asses :")

  # The dashes really are still there, in bulk, on the raw side.
  expect_gt(sum(grepl("^- ", df$raw_description)), 10000L)
  expect_false(any(is.na(df$raw_description)))

  # Whitespace normalisation only: no embedded newlines/tabs, and the 1,647
  # non-breaking spaces the workbook uses inside dash markers are gone.
  expect_false(any(grepl("[\r\n\t]", df$raw_description)))
  expect_false(any(grepl("\u00a0", df$raw_description)))
})

# --- 16. Cross-reference matches are explicitly labelled --------------------

test_that("9.15/16 a cross-reference match says which edition it came from", {
  expect_identical(
    pscc_match_reason_text("pscc_2019", "0101.21.00-00"),
    "Matched 2019 PSCC cross-reference: 0101.21.00-00"
  )
  expect_identical(
    pscc_match_reason_text("ahtn_2022", "0101.21.00"),
    "Matched AHTN 2022 cross-reference: 0101.21.00"
  )
  expect_identical(
    pscc_match_reason_text("pscc_2022", "0101.21.00-000"),
    "Matched 2022 PSCC code: 0101.21.00-000"
  )

  # A 2019-only code resolves through the cross-reference column and is
  # reported as such -- while the row still shows its own 2022 code.
  hit <- pscc_crossref_search("0101.21.00-00")
  expect_gte(nrow(hit), 1L)
  expect_identical(hit$match_field[1], "pscc_2019")
  expect_identical(hit$matched_value[1], "0101.21.00-00")
  expect_match(hit$match_reason[1], "2019 PSCC cross-reference", fixed = TRUE)
  expect_identical(hit$pscc_2022_code[1], "0101.21.00-000")
  expect_identical(hit$code[1], "0101.21.00-000")

  # The 2022 code wins outright and is labelled as the authoritative match.
  exact <- pscc_crossref_search("0101.21.00-000")
  expect_equal(nrow(exact), 1L)
  expect_identical(exact$match_field[1], "pscc_2022")
  expect_match(exact$match_reason[1], "^Matched 2022 PSCC code: ")

  # An AHTN value resolves, is labelled AHTN, and never overwrites the 2022
  # code on the rows it returns.
  ahtn <- pscc_crossref_search("0101.29.00")
  expect_gte(nrow(ahtn), 1L)
  expect_true(all(ahtn$pscc_2022_code != ahtn$matched_value |
                    ahtn$match_field == "pscc_2022"))

  # Blank / unmatched queries return zero rows, never an error.
  expect_equal(nrow(pscc_crossref_search("")), 0L)
  expect_equal(nrow(pscc_crossref_search(NA_character_)), 0L)
  expect_equal(nrow(pscc_crossref_search("ZZZZ-not-a-code")), 0L)

  # The result is bounded.
  capped <- pscc_crossref_search("0101", limit = 3L)
  expect_lte(nrow(capped), 3L)
})

# --- 17. PSCC and PSCCS stay separate ---------------------------------------

test_that("9.15/17 PSCC and PSCCS remain separate registry systems", {
  reg <- classification_registry()

  expect_true("pscc" %in% reg$id)
  expect_true("psccs" %in% reg$id)

  pscc_name <- reg$display_name[reg$id == "pscc"]
  psccs_name <- reg$display_name[reg$id == "psccs"]
  expect_false(identical(pscc_name, psccs_name))
  expect_false(grepl("Crime", pscc_name, ignore.case = TRUE))
  expect_match(pscc_name, "Commodity")

  # No PSCC row ever claims to be PSCCS, and the level vocabularies differ.
  expect_true(all(pscc2022_get()$system == "pscc"))
  expect_false("psccs" %in% pscc2022_get()$system)
  expect_identical(pscc2022_metadata()$system, "pscc")
  expect_false(grepl("Crime", pscc2022_metadata()$scope, ignore.case = TRUE))
})

# --- 18. Rows carrying BOTH a Heading and a 2022 PSCC code ------------------

test_that("9.15/18 a row with both Heading and 2022 PSCC keeps both", {
  df <- pscc_df()

  h <- row_for("02.05", "heading")
  c <- row_for("0205.00.00-000", "commodity")
  expect_equal(nrow(h), 1L)
  expect_equal(nrow(c), 1L)

  # Both records come from the SAME workbook row, and neither field was lost.
  expect_equal(h$source_row[1], c$source_row[1])
  expect_identical(h$code[1], "02.05")
  expect_identical(c$pscc_2022_code[1], "0205.00.00-000")
  expect_identical(c$heading_code[1], "02.05")
  expect_identical(c$parent_code[1], "02.05")

  # 173 workbook rows do this; each one yields two records.
  dual <- intersect(df$source_row[df$level == "heading"],
                    df$source_row[df$level %in% c("subheading", "intermediate_category", "commodity")])
  expect_equal(length(dual), 173L)
})

# --- 19. Float-like code artifacts are detected, not shipped ----------------

test_that("9.15/19 suspicious numeric/float code artifacts are detected", {
  df <- pscc_df()
  meta <- pscc2022_metadata()

  # The nine Excel-numeric cells were repaired to their published form and
  # every repair is recorded with its before/after text.
  expect_equal(length(meta$numeric_cell_repairs), 9L)
  for (rep in meta$numeric_cell_repairs) {
    expect_true(rep$column %in% c("Heading", "2022 PSCC"))
    expect_true(grepl("[0-9]\\.[0-9]{6,}|^[0-9]{1,2}\\.[0-9]$", rep$raw))
    expect_true(rep$repaired %in% df$code)
  }
  for (fx in c("20.06", "38.27", "39.16", "76.01", "98.10",
                "8701.21", "8701.22", "8701.29", "8708.22")) {
    expect_true(fx %in% df$code, info = sprintf("repaired code '%s' missing", fx))
  }

  # No float-expansion signature survives anywhere a code is stored.
  float_sig <- "([0-9]\\.[0-9]{6,})|([eE][+-][0-9])"
  expect_false(any(grepl(float_sig, df$code)))
  expect_false(any(grepl(float_sig, stats::na.omit(df$pscc_2022_code))))
  expect_false(any(grepl(float_sig, stats::na.omit(df$pscc_2019_code))))
  expect_false(any(grepl(float_sig, stats::na.omit(df$ahtn_2022_code))))
  expect_false(any(grepl(float_sig, stats::na.omit(df$heading_code))))
  expect_false("98.1" %in% df$code)
  expect_false("20.059999999999999" %in% df$code)
})

# --- 20. Browse mode is bounded ---------------------------------------------

test_that("9.15/20 browse mode never materialises the whole workbook", {
  df <- pscc_df()
  expect_gt(nrow(df), 24000L)

  # Blank-query browse through the ordinary service is capped but still
  # reports the truthful total.
  res <- search_classification_result("pscc", "2022", query = "", limit = 50)
  expect_equal(nrow(res$data), 50L)
  expect_equal(res$total_matches, nrow(df))
  expect_true(res$is_truncated)

  # Hierarchical browse returns ONE level at a time.
  roots <- pscc_browse_children(NULL)
  expect_equal(nrow(roots$data), 21L)
  expect_equal(roots$total_children, 21L)
  expect_false(roots$is_truncated)
  expect_true(all(roots$data$level == "section"))

  ch1 <- pscc_browse_children("I")
  expect_true(all(ch1$data$parent_code == "I"))
  expect_true(all(ch1$data$level == "chapter"))
  expect_lt(nrow(ch1$data), 100L)

  under_heading <- pscc_browse_children("01.01")
  expect_gt(nrow(under_heading$data), 0L)
  expect_true(all(under_heading$data$parent_code == "01.01"))
  # Children come back in workbook order.
  expect_false(is.unsorted(under_heading$data$source_order))

  capped <- pscc_browse_children("I", limit = 2L)
  expect_equal(nrow(capped$data), 2L)
  expect_true(capped$is_truncated)
  expect_gt(capped$total_children, 2L)
})

# --- Presentation helpers (spec 9.5 / 9.10 / 9.12) --------------------------

test_that("pscc_level_labels() maps every artifact level to a public label", {
  labels <- pscc_level_labels()

  expect_setequal(names(labels), pscc2022_levels())
  expect_identical(unname(labels[pscc2022_levels()[1]]), "Section")
  expect_identical(pscc_level_label("commodity"), "Commodity item")
  expect_identical(pscc_level_label("structural_group"), "Structural group")
  # Unknown values degrade to themselves rather than disappearing.
  expect_identical(pscc_level_label("not_a_level"), "not_a_level")
  expect_identical(pscc_level_label(c("section", "commodity")),
                    c("Section", "Commodity item"))

  choices <- pscc_level_choices()
  expect_identical(unname(choices[1]), "")
  expect_identical(names(choices)[1], "All levels")
  expect_true("Intermediate category" %in% names(choices))
  expect_false(any(grepl("ahtn", names(choices), ignore.case = TRUE)))
})

test_that("pscc_result_fields() produces the 9.5 result shape", {
  f <- pscc_result_fields(row_for("0101.21.00-000", "commodity"))

  expect_identical(f$code, "0101.21.00-000")
  expect_identical(f$description, "Pure-bred breeding animals")
  expect_identical(f$breadcrumb,
                    paste("Section I", "Chapter 1", "Heading 01.01", "Horses", sep = " › "))
  expect_identical(f$level_label, "Commodity item")
  expect_true(f$is_selectable_code)
  expect_identical(f$secondary[["Unit"]], "u")
  expect_identical(f$secondary[["2019 PSCC"]], "0101.21.00-00")
  expect_identical(f$secondary[["AHTN 2022"]], "0101.21.00")
  expect_identical(names(f$secondary), c("Unit", "2019 PSCC", "AHTN 2022"))

  # A structural label reports NO code rather than borrowing one.
  df <- pscc_df()
  horses <- df[df$raw_description == "- Horses :" & df$heading_code == "01.01", , drop = FALSE]
  sf <- pscc_result_fields(horses)
  expect_true(is.na(sf$code))
  expect_true(sf$is_structural_label)
  expect_false(sf$is_selectable_code)
  expect_length(sf$secondary, 0L)

  expect_null(pscc_result_fields(NULL))
  expect_null(pscc_result_fields(df[0L, , drop = FALSE]))
})

test_that("pscc_detail_fields() labels cross-references as cross-references", {
  d <- pscc_detail_fields(row_for("0101.21.00-000", "commodity"))

  expect_true(is.data.frame(d))
  expect_identical(d$value[d$label == "2022 PSCC"], "0101.21.00-000")
  expect_identical(d$value[d$label == "Unit of Quantity"], "u")
  expect_identical(d$value[d$label == "2019 PSCC cross-reference"], "0101.21.00-00")
  expect_identical(d$value[d$label == "AHTN 2022 cross-reference"], "0101.21.00")
  expect_identical(d$value[d$label == "Source description"], "- - Pure-bred breeding animals")

  # No label may present a cross-reference as the 2022 PSCC code.
  expect_equal(sum(d$label == "2022 PSCC"), 1L)
  expect_false(any(d$label == "2022 PSCC" & d$value == "0101.21.00"))

  # A structural node has no "2022 PSCC" row at all.
  df <- pscc_df()
  horses <- df[df$raw_description == "- Horses :" & df$heading_code == "01.01", , drop = FALSE]
  sd <- pscc_detail_fields(horses)
  expect_false("2022 PSCC" %in% sd$label)
  expect_true("Node type" %in% sd$label)
})

test_that("presentation helpers return Shiny tags without touching the data", {
  r <- row_for("0101.21.00-000", "commodity")

  result <- pscc_result_ui(r)
  expect_s3_class(result, "shiny.tag")
  html <- as.character(result)
  expect_true(grepl("0101.21.00-000", html, fixed = TRUE))
  expect_true(grepl("Pure-bred breeding animals", html, fixed = TRUE))
  expect_true(grepl("2019 PSCC", html, fixed = TRUE))
  expect_true(grepl("AHTN 2022", html, fixed = TRUE))

  detail <- pscc_detail_ui(r)
  expect_s3_class(detail, "shiny.tag")
  dhtml <- as.character(detail)
  expect_true(grepl("2019 PSCC cross-reference", dhtml, fixed = TRUE))
  expect_true(grepl("AHTN 2022 cross-reference", dhtml, fixed = TRUE))

  expect_s3_class(pscc_detail_ui(NULL), "shiny.tag")
  expect_null(pscc_result_ui(NULL))
})

# --- Structural integrity of the display tree -------------------------------

test_that("the display tree is internally consistent", {
  df <- pscc_df()

  expect_equal(nrow(df), 24180L)
  expect_equal(anyDuplicated(df$code), 0L)
  expect_identical(df$source_order, seq_len(nrow(df)))
  expect_false(is.unsorted(df$source_row))

  # Every parent exists, nobody parents themselves, depth increases by
  # exactly one from parent to child.
  idx <- match(df$parent_code, df$code)
  has_parent <- !is.na(df$parent_code)
  expect_false(any(is.na(idx[has_parent])))
  expect_false(any(has_parent & df$parent_code == df$code))
  expect_true(all(df$display_depth[has_parent] == df$display_depth[idx[has_parent]] + 1L))

  # A parent always appears before its child in source order.
  expect_true(all(df$source_order[has_parent] > df$source_order[idx[has_parent]]))

  expect_equal(min(df$display_depth), 0L)
  expect_true(all(df$display_depth[df$level == "section"] == 0L))
})

test_that("sub-chapter markers keep both published lines", {
  df <- pscc_df()
  sc <- df[df$node_type == "sub_chapter", , drop = FALSE]

  expect_equal(nrow(sc), 33L)
  expect_true(all(grepl("^SUB-CHAPTER ", sc$label)))
  # The title line PSA prints beneath the marker is kept verbatim in
  # `description` rather than being concatenated into the label.
  expect_false(any(is.na(sc$description)))
  expect_true("CHEMICAL ELEMENTS" %in% sc$description)
  expect_true(all(sc$display_depth == 2L))
  expect_true(all(!is.na(sc$chapter_code)))
})

test_that("metadata documents the new display contract", {
  meta <- pscc2022_metadata()

  expect_identical(meta$extra_columns, setdiff(names(pscc2022_get()), CLASSIFICATION_SCHEMA_COLUMNS))
  expect_true(all(c("node_type", "display_depth", "display_description",
                     "raw_description", "breadcrumb", "is_selectable_code",
                     "is_structural_label", "source_row", "source_order")
                  %in% meta$extra_columns))
  expect_identical(meta$breadcrumb_separator, " › ")
  expect_setequal(meta$node_types, unique(pscc2022_get()$node_type))
  expect_equal(meta$parsed_counts$total, nrow(pscc2022_get()))
  expect_equal(meta$parsed_counts$structural_labels, 2438L)
  expect_equal(meta$parsed_counts$selectable_codes, 21742L)
  expect_true(nzchar(meta$cross_reference_contract))
})
