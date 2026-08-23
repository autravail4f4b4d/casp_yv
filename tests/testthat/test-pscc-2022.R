# PSCC 2022 adapter + artifact contract tests.
#
# Fixtures below are REAL codes taken from data-raw/pscc.xlsx ("all sections"
# sheet). They are chosen specifically to catch the failure mode this project
# has repeatedly hit: Excel/numeric coercion silently eating a leading zero or
# rewriting published punctuation.

test_that("pscc2022_versions() is exactly the 2022 edition", {
  expect_identical(pscc2022_versions(), "2022")
  expect_true(all(pscc2022_get()$version == "2022"))
})

test_that("metadata carries the official PSA name and provenance", {
  meta <- pscc2022_metadata()

  expect_identical(meta$official_name, "Philippine Standard Commodity Classification")
  expect_identical(meta$display_name, "Philippine Standard Commodity Classification (PSCC)")
  expect_identical(meta$version, "2022")
  expect_identical(meta$display_version, "2022 PSCC")
  expect_identical(meta$status, "current")
  expect_identical(meta$source, "Philippine Statistics Authority")
  expect_identical(meta$source_url, "https://psa.gov.ph/classification/pscc")

  # PSCC must never be described as the crime classification (PSCCS).
  expect_false(grepl("Crime", meta$official_name, ignore.case = TRUE))
  expect_false(grepl("Crime", meta$display_name, ignore.case = TRUE))

  # Only the workbook filename is recorded -- never an absolute local path.
  expect_identical(meta$source_artifact, "pscc.xlsx")
  expect_identical(basename(meta$source_artifact), meta$source_artifact)
  expect_false(grepl("[/\\\\]|^[A-Za-z]:", meta$source_artifact))

  expect_match(meta$sha256, "^[0-9a-f]{64}$")
  expect_true(nzchar(meta$retrieved_at))
  expect_true(nzchar(meta$scope))
})

test_that("canonical tibble matches the frozen schema exactly", {
  df <- pscc2022_get()

  expect_identical(names(df), CLASSIFICATION_SCHEMA_COLUMNS)
  expect_true(all(vapply(df, is.character, logical(1))))
  expect_silent(validate_classification_tibble(df))
  expect_gt(nrow(df), 20000)
  expect_true(all(df$system == "pscc"))
  expect_true(all(df$source == "Philippine Statistics Authority"))
  expect_true(all(df$source_url == "https://psa.gov.ph/classification/pscc"))
})

test_that("codes are strings, never numeric", {
  df <- pscc2022_get()

  expect_true(is.character(df$code))
  expect_false(is.numeric(df$code))
  expect_false(anyNA(df$code))
  expect_false(any(df$code == ""))
  expect_false(any(grepl("e[+-][0-9]", df$code, ignore.case = TRUE)))
  # No float residue from an accidental numeric round-trip.
  expect_false(any(grepl("[0-9]\\.[0-9]{6,}", df$code)))
})

test_that("real leading-zero codes survive verbatim at every level", {
  codes <- pscc2022_get()$code

  # Every one of these is printed exactly like this in the workbook.
  leading_zero_fixtures <- c(
    "01.01",           # heading         -- Live horses, asses, mules and hinnies.
    "0101.30",         # subheading      -- Asses
    "0101.29.00",      # ahtn subheading -- Other (horses)
    "0101.21.00-000",  # commodity       -- Pure-bred breeding animals
    "0105.11.10-000",  # commodity       -- Breeding fowls
    "01",              # chapter         -- Live animals
    "09.03"            # heading         -- Mate
  )
  for (fx in leading_zero_fixtures) {
    expect_true(fx %in% codes, info = sprintf("leading-zero code '%s' missing", fx))
  }

  # The zero must still be there -- i.e. the de-zeroed variant must NOT exist.
  expect_false("1.01" %in% codes)
  expect_false("101.30" %in% codes)
  expect_false("101.21.00-000" %in% codes)
  expect_false("1" %in% codes)

  meta <- pscc2022_metadata()
  expect_gt(meta$parsed_counts$leading_zero_codes, 1000)
})

test_that("real punctuated and hyphenated codes survive verbatim", {
  df <- pscc2022_get()
  codes <- df$code

  # Dotted + hyphenated 11-digit commodity codes as published.
  expect_true("0101.29.00-001" %in% codes)
  expect_true("9620.00.30-000" %in% codes)
  expect_true("3808.52.20-002" %in% codes)

  # Four chapter-96 codes are published with a dot where a hyphen normally
  # goes; the build preserves them exactly rather than "correcting" PSA.
  expect_true("9620.00.90.100" %in% codes)
  expect_true("9620.00.90.900" %in% codes)
  expect_false("9620.00.90-100" %in% codes)

  meta <- pscc2022_metadata()
  expect_equal(length(meta$anomalies), 4L)
  expect_true(all(vapply(meta$anomalies, function(a) a$code, character(1)) %in% codes))

  expect_gt(meta$parsed_counts$hyphenated_codes, 16000)
  expect_gt(meta$parsed_counts$punctuated_codes, 20000)
})

test_that("Excel-numeric cells were repaired back to their published form", {
  codes <- pscc2022_get()$code
  meta <- pscc2022_metadata()

  # These five headings and four subheadings are stored as numbers in the
  # workbook; readxl surfaces them as float text ("20.059999999999999").
  for (fx in c("20.06", "38.27", "39.16", "76.01", "98.10")) {
    expect_true(fx %in% codes, info = sprintf("repaired heading '%s' missing", fx))
  }
  for (fx in c("8701.21", "8701.22", "8701.29", "8708.22")) {
    expect_true(fx %in% codes, info = sprintf("repaired subheading '%s' missing", fx))
  }
  # The unrepaired float text must be nowhere in the artifact.
  expect_false("98.1" %in% codes)
  expect_false("20.059999999999999" %in% codes)

  expect_equal(length(meta$numeric_cell_repairs), 9L)
})

test_that("no duplicate canonical (level, code) keys", {
  df <- pscc2022_get()
  expect_equal(anyDuplicated(paste(df$level, df$code, sep = "\r")), 0L)
  expect_equal(pscc2022_metadata()$parsed_counts$duplicate_keys, 0L)

  # The four workbook rows that repeat a code at the same level are recorded,
  # not silently discarded.
  notes <- pscc2022_metadata()$duplicate_code_notes
  expect_equal(length(notes), 4L)
  expect_true(all(vapply(notes, function(n) nzchar(n$dropped_label), logical(1))))
})

test_that("every non-NA parent_code refers to a real PSCC code", {
  df <- pscc2022_get()
  parents <- unique(df$parent_code[!is.na(df$parent_code)])
  expect_length(setdiff(parents, df$code), 0L)

  # Only sections sit at the root.
  expect_true(all(is.na(df$parent_code[df$level == "section"])))
  expect_false(any(is.na(df$parent_code[df$level != "section"])))

  # Spot-check verified linkage from the workbook.
  parent_of <- function(code) df$parent_code[df$code == code][1]
  expect_identical(parent_of("01"), "I")
  expect_identical(parent_of("01.01"), "01")
  expect_identical(parent_of("0101.30"), "01.01")
  expect_identical(parent_of("0101.29.00-001"), "0101.29.00")
  expect_identical(parent_of("9620.00.90.100"), "9620.00.90")

  # No code is ever its own parent.
  expect_false(any(!is.na(df$parent_code) & df$parent_code == df$code))
})

test_that("declared levels match the levels actually present", {
  levels <- pscc2022_levels()
  expect_identical(
    levels,
    c("section", "chapter", "heading", "subheading", "ahtn subheading", "commodity")
  )
  df <- pscc2022_get()
  expect_setequal(unique(df$level), levels)
  expect_identical(pscc2022_metadata()$levels, levels)
})

test_that("level filter returns only that level and matches the full set", {
  df <- pscc2022_get()

  sections <- pscc2022_get(level = "section")
  expect_true(all(sections$level == "section"))
  expect_equal(nrow(sections), 21L)
  expect_identical(names(sections), CLASSIFICATION_SCHEMA_COLUMNS)

  chapters <- pscc2022_get(level = "chapter")
  expect_equal(nrow(chapters), 98L)

  commodities <- pscc2022_get(level = "commodity")
  expect_true(all(commodities$level == "commodity"))
  expect_gt(nrow(commodities), 16000)

  total <- sum(vapply(pscc2022_levels(),
                       function(l) nrow(pscc2022_get(level = l)), integer(1)))
  expect_equal(total, nrow(df))
})

test_that("an unsupported level errors clearly", {
  expect_error(pscc2022_get(level = "division"), "Unsupported PSCC level 'division'")
  expect_error(pscc2022_get(level = "division"), "Available levels")
  expect_error(pscc2022_get(level = "sub-class"), "Unsupported PSCC level")
})

test_that("a missing runtime artifact names the build script", {
  missing_data <- file.path(tempdir(), "pscc_2022_does_not_exist.rds")
  missing_meta <- file.path(tempdir(), "pscc_2022_metadata_does_not_exist.rds")
  expect_false(file.exists(missing_data))

  expect_error(pscc2022_get(data_path = missing_data),
               "scripts/build_pscc_2022.R", fixed = TRUE)
  expect_error(pscc2022_metadata(metadata_path = missing_meta),
               "scripts/build_pscc_2022.R", fixed = TRUE)
  expect_error(pscc2022_get(data_path = missing_data),
               "runtime artifact is missing")
})

test_that("PSCC 2022 is presented as current throughout", {
  df <- pscc2022_get()
  expect_identical(unique(df$status), "current")
  expect_false(any(df$status == "archived"))
  expect_identical(pscc2022_metadata()$status, "current")
})

test_that("unit of quantity and cross-reference metadata are preserved", {
  meta <- pscc2022_metadata()
  attrs <- meta$code_attributes

  expect_true(is.data.frame(attrs))
  expect_true(all(c("level", "code", "unit_of_quantity", "pscc_2019", "ahtn_2022")
                  %in% names(attrs)))
  expect_true(is.character(attrs$code))
  expect_true(is.character(attrs$unit_of_quantity))
  expect_true(is.character(attrs$pscc_2019))
  expect_true(is.character(attrs$ahtn_2022))
  expect_gt(nrow(attrs), 16000)

  expect_identical(meta$cross_reference_columns, c("2019 PSCC", "AHTN 2022"))
  expect_true(all(c("kg", "u") %in% meta$unit_of_quantity_values))

  # Exact row from the workbook: 0101.21.00-000, unit "u",
  # 2019 PSCC "0101.21.00-00", AHTN 2022 "0101.21.00".
  row <- attrs[attrs$code == "0101.21.00-000", ]
  expect_equal(nrow(row), 1L)
  expect_identical(row$unit_of_quantity[1], "u")
  expect_identical(row$pscc_2019[1], "0101.21.00-00")
  expect_identical(row$ahtn_2022[1], "0101.21.00")

  # Cross-reference codes keep their leading zeros and "ex" partial-match
  # prefix exactly as published.
  expect_true(any(grepl("^ex", attrs$pscc_2019)))
  expect_true("ex9620.00.90-09" %in% attrs$pscc_2019)
  expect_false(any(grepl("[0-9]\\.[0-9]{6,}", stats::na.omit(attrs$pscc_2019))))

  # Every attribute row keys back to a real canonical record.
  codes <- pscc2022_get()$code
  expect_length(setdiff(attrs$code, codes), 0L)
})

test_that("labels and derived descriptions carry real PSA text", {
  df <- pscc2022_get()

  expect_false(any(is.na(df$label)))
  expect_false(any(df$label == ""))
  # Whitespace was squished; no embedded newlines/tabs leak into labels.
  expect_false(any(grepl("[\r\n\t]", df$label)))

  expect_identical(df$label[df$code == "01.01" & df$level == "heading"][1],
                    "Live horses, asses, mules and hinnies.")
  expect_identical(df$label[df$code == "I" & df$level == "section"][1],
                    "LIVE ANIMALS; ANIMAL PRODUCTS")
  expect_identical(df$label[df$code == "01" & df$level == "chapter"][1],
                    "Live animals")

  # description is the published 4-digit heading text for codes below the
  # heading level, and NA at/above it.
  expect_identical(df$description[df$code == "0101.21.00-000"][1],
                    "Live horses, asses, mules and hinnies.")
  expect_true(is.na(df$description[df$code == "01.01" & df$level == "heading"][1]))
  expect_true(all(is.na(df$description[df$level == "section"])))
  expect_false(any(is.na(df$description[df$level == "commodity"])))
})

test_that("parsed counts in metadata agree with the artifact", {
  df <- pscc2022_get()
  counts <- pscc2022_metadata()$parsed_counts

  expect_equal(counts$total, nrow(df))
  for (lv in pscc2022_levels()) {
    expect_equal(counts$by_level[[lv]], sum(df$level == lv),
                 info = sprintf("level count mismatch for '%s'", lv))
  }
  expect_equal(counts$leading_zero_codes, sum(grepl("^0", df$code)))
  expect_equal(counts$unresolved_parents,
               sum(is.na(df$parent_code) & df$level != "section"))
})

test_that("the adapter memoises within a session and can be reset", {
  first <- pscc2022_get()
  second <- pscc2022_get()
  expect_identical(first, second)

  .pscc2022_reset_cache()
  expect_equal(length(ls(.pscc2022_cache)), 0L)
  expect_identical(pscc2022_get(), first)
})
