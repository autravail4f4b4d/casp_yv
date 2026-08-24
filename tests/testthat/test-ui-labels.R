# UI-POST-06 (edition/release label humanisation) and UI-POST-03
# (human-readable level labels + Level-vs-Component redundancy).
#
# These are presentation-layer contracts. The point of testing them at the
# service level is that a display transform must never change which record
# is selected: every function under test is a pure mapping, and the raw
# identifier must always survive alongside the pretty one.

# ---------------------------------------------------------------------
# Edition / release labels
# ---------------------------------------------------------------------

test_that("underscored release tokens are humanised", {
  expect_identical(release_display_label("Q1_2023"), "Q1 2023")
  expect_identical(release_display_label("Q4_2023"), "Q4 2023")
  expect_identical(release_display_label("April_2024"), "April 2024")
  expect_identical(release_display_label("July_2025"), "July 2025")
})

test_that("editions without underscores are left exactly alone", {
  untouched <- c("2019", "2026", "2022", "2012", "2017", "2018", "2025-v2.1")
  expect_identical(release_display_label(untouched), untouched)
})

test_that("the transform is vectorised, NA-safe and length-preserving", {
  input <- c("Q1_2023", NA_character_, "2026")
  out <- release_display_label(input)

  expect_length(out, 3L)
  expect_identical(out[[1L]], "Q1 2023")
  expect_true(is.na(out[[2L]]))
  expect_identical(out[[3L]], "2026")
})

test_that("humanising never changes chronological order", {
  # Order preservation is the property that matters: the label is applied to
  # an already-ordered vector, so it must not permute anything.
  versions <- classification_versions("psgc")
  labels <- release_display_label(versions)

  expect_length(labels, length(versions))
  # Every label maps back to exactly one raw edition, in the same position.
  expect_identical(gsub(" ", "_", labels, fixed = TRUE), versions)
})

test_that("every real edition in the registry gets a non-empty label", {
  reg <- classification_registry()
  for (id in reg$id) {
    versions <- classification_versions(id)
    labels <- release_display_label(versions)
    expect_length(labels, length(versions))
    expect_false(any(is.na(labels)), info = id)
    expect_true(all(nzchar(labels)), info = id)
    # No underscore may survive into a public label.
    expect_false(any(grepl("_", labels, fixed = TRUE)), info = id)
  }
})

# ---------------------------------------------------------------------
# Level labels
# ---------------------------------------------------------------------

test_that("PSGC level abbreviations are expanded", {
  expect_identical(level_display_label("psgc", "Bgy"), "Barangay")
  expect_identical(level_display_label("psgc", "SubMun"), "Sub-municipality")
  expect_identical(level_display_label("psgc", "Prov"), "Province")
  expect_identical(level_display_label("psgc", "Reg"), "Region")
  expect_identical(level_display_label("psgc", "Mun"), "Municipality")
})

test_that("PSCED run-together level tokens are separated", {
  expect_identical(level_display_label("psced", "broadfield"), "Broad field")
  expect_identical(level_display_label("psced", "detailedfield"), "Detailed field")
})

test_that("generic tokens lose their underscores and gain a capital", {
  expect_identical(level_display_label("psoc", "sub_major_group"), "Sub major group")
  expect_identical(level_display_label("psoc", "unit_group"), "Unit group")
  expect_identical(level_display_label("psic", "sub-class"), "Sub-class")
  expect_identical(level_display_label("psic", "section"), "Section")
})

test_that("no public level label leaks a machine token", {
  reg <- classification_registry()
  for (id in reg$id) {
    for (v in classification_versions(id)) {
      raw <- classification_levels(id, v)
      if (length(raw) == 0L) next
      labels <- level_display_label(id, raw)

      expect_length(labels, length(raw))
      expect_false(any(is.na(labels)), info = paste(id, v))
      expect_true(all(nzchar(labels)), info = paste(id, v))
      # Underscores are the tell-tale of a raw token reaching the UI.
      expect_false(any(grepl("_", labels, fixed = TRUE)),
                   info = paste(id, v, paste(labels, collapse = ", ")))
      # Every label starts with a capital letter.
      expect_true(all(grepl("^[A-Z0-9]", labels)),
                  info = paste(id, v, paste(labels, collapse = ", ")))
    }
  }
})

test_that("level_choice_vector keeps raw values as the submitted value", {
  raw <- classification_levels("psgc", "Q2_2026")
  choices <- level_choice_vector("psgc", raw)

  # Values are raw (what the repository validates against); names are public.
  expect_identical(unname(choices), raw)
  expect_true("Barangay" %in% names(choices))
  expect_false(any(grepl("_", names(choices), fixed = TRUE)))
  # Order is preserved so hierarchy order survives into the control.
  expect_identical(unname(choices), raw)
})

test_that("every level label still round-trips to a valid repository level", {
  # The real safety property: whatever is displayed, the value submitted must
  # still be accepted by the service layer.
  raw <- classification_levels("psoc", "2022")
  choices <- level_choice_vector("psoc", raw)
  for (value in unname(choices)) {
    expect_silent(get_classification("psoc", "2022", level = value))
  }
})

# ---------------------------------------------------------------------
# Component labels (UI-POST-03)
# ---------------------------------------------------------------------

test_that("PTSCS components use the published public names", {
  ids <- classification_components("ptscs")
  labels <- component_display_label("ptscs", ids)

  expect_setequal(labels, c("Tourism Industries", "Tourism Characteristic Products"))
  expect_identical(component_display_label("ptscs", "tourism_industry"), "Tourism Industries")
  expect_identical(component_display_label("ptscs", "tourism_product"),
                   "Tourism Characteristic Products")
})

test_that("PSCrCS components use the published public names", {
  ids <- classification_components("pscrcs")
  labels <- component_display_label("pscrcs", ids)

  expect_setequal(
    labels,
    c("Creative Industries", "Creative Goods and Services", "Creative Occupations")
  )
})

test_that("no component label leaks a machine token", {
  for (system in c("ptscs", "pscrcs")) {
    ids <- classification_components(system)
    labels <- component_display_label(system, ids)

    expect_length(labels, length(ids))
    expect_false(any(grepl("_", labels, fixed = TRUE)), info = system)
    expect_true(all(nzchar(labels)), info = system)
    # The raw token must never be shown verbatim as the label.
    expect_false(any(labels == ids), info = system)
  }
})

test_that("component_choice_vector submits the raw id, not the label", {
  ids <- classification_components("pscrcs")
  choices <- component_choice_vector("pscrcs", ids)

  expect_identical(unname(choices), ids)
  expect_true("Creative Goods and Services" %in% names(choices))
  # Every submitted value must still be accepted by the repository.
  for (value in unname(choices)) {
    expect_silent(get_classification("pscrcs", "2025", component = value))
  }
})

test_that("an unmapped component degrades to a readable title case", {
  expect_identical(component_display_label("nosuchsystem", "some_new_component"),
                   "Some New Component")
})

# ---------------------------------------------------------------------
# Component x Level redundancy (UI-POST-03)
# ---------------------------------------------------------------------

test_that("PTSCS component and level are one-to-one in the artifact", {
  pairs <- classification_component_levels("ptscs", "2025-v2.1")

  expect_gt(nrow(pairs), 0L)
  # Every component maps to exactly one level...
  per_component <- tapply(pairs$level, pairs$component, function(x) length(unique(x)))
  expect_true(all(per_component == 1L))
  # ...and in this artifact the two tokens are actually identical.
  expect_identical(pairs$component, pairs$level)
})

test_that("PSCrCS component and level are one-to-one in the artifact", {
  pairs <- classification_component_levels("pscrcs", "2025")

  expect_gt(nrow(pairs), 0L)
  per_component <- tapply(pairs$level, pairs$component, function(x) length(unique(x)))
  expect_true(all(per_component == 1L))
  expect_identical(pairs$component, pairs$level)
})

test_that("Level is reported as uninformative for both composite systems", {
  expect_false(classification_level_is_informative("ptscs", "2025-v2.1"))
  expect_false(classification_level_is_informative("pscrcs", "2025"))

  # ...and also within each individual component.
  for (cmp in classification_components("ptscs")) {
    expect_false(classification_level_is_informative("ptscs", "2025-v2.1", component = cmp),
                 info = cmp)
  }
  for (cmp in classification_components("pscrcs")) {
    expect_false(classification_level_is_informative("pscrcs", "2025", component = cmp),
                 info = cmp)
  }
})

test_that("Level stays informative for ordinary hierarchical systems", {
  expect_true(classification_level_is_informative("psgc", "Q2_2026"))
  expect_true(classification_level_is_informative("psic", "2026"))
  expect_true(classification_level_is_informative("psoc", "2022"))
  expect_true(classification_level_is_informative("pscc", "2022"))
})

test_that("the redundancy verdict is derived from data, not hard-coded", {
  # A synthetic component/level frame with a genuinely subdividing component
  # must flip the verdict. This is what stops the rule from being a disguised
  # per-system allowlist: if a future edition adds real sub-levels, Level
  # must reappear without any code change.
  informative <- function(pairs) {
    per_component <- tapply(pairs$level, pairs$component, function(x) length(unique(x)))
    any(per_component > 1L)
  }

  redundant <- data.frame(
    component = c("a", "b"), level = c("a", "b"), stringsAsFactors = FALSE
  )
  genuine <- data.frame(
    component = c("a", "a", "b"),
    level = c("a_one", "a_two", "b"),
    stringsAsFactors = FALSE
  )

  expect_false(informative(redundant))
  expect_true(informative(genuine))
})

test_that("an unknown component never errors and reports no extra levels", {
  expect_false(classification_level_is_informative("ptscs", "2025-v2.1",
                                                   component = "no_such_component"))
})

test_that("systems with no component dimension yield an empty pair frame", {
  pairs <- classification_component_levels("psic", "2026")
  expect_equal(nrow(pairs), 0L)
  expect_identical(names(pairs), c("component", "level"))
})
