test_that("phscs_get returns exactly the canonical schema columns", {
  for (sys_ver in list(c("psic", "2019"), c("psoc", "2012"))) {
    d <- phscs_get(sys_ver[1], sys_ver[2])
    expect_equal(names(d), CLASSIFICATION_SCHEMA_COLUMNS, info = sys_ver[1])
  }
})

test_that("psgc_get returns exactly the canonical schema columns", {
  d <- psgc_get(psgc::latest_release(), level = "Reg")
  expect_equal(names(d), CLASSIFICATION_SCHEMA_COLUMNS)
})

test_that("code column stays character (no leading-zero corruption)", {
  psic <- phscs_get("psic", "2019")
  expect_true(is.character(psic$code))
  expect_false(is.numeric(psic$code))
  # divisions are 2-digit codes like "01" -- would collapse to "1" if numeric
  division_codes <- psic$code[psic$level == "division"]
  expect_true(any(nchar(division_codes) == 2 & substr(division_codes, 1, 1) == "0"))

  psgc <- psgc_get(psgc::latest_release())
  expect_true(is.character(psgc$code))
  expect_false(is.numeric(psgc$code))
  expect_true(all(nchar(psgc$code) == 10))
})

test_that("every row's status is 'current' or 'archived'", {
  for (sys_ver in list(c("psic", "2019"), c("psoc", "2012"), c("psced", "2017"),
                        c("pcoicop", "2020"), c("pcoicop", "2009"),
                        c("pcpc", "2002"), c("psccs", "2018"))) {
    d <- phscs_get(sys_ver[1], sys_ver[2])
    expect_true(all(d$status %in% c("current", "archived")), info = paste(sys_ver, collapse = ":"))
  }
  d <- psgc_get(psgc::latest_release())
  expect_true(all(d$status %in% c("current", "archived")))
})

test_that("psic 2019 is archived (superseded by PSIC Revision 5 / 2026)", {
  d <- phscs_get("psic", "2019")
  expect_true(all(d$status == "archived"))
})

test_that("pcoicop 2020 is current and pcoicop 2009 is archived", {
  d2020 <- phscs_get("pcoicop", "2020")
  d2009 <- phscs_get("pcoicop", "2009")
  expect_true(all(d2020$status == "current"))
  expect_true(all(d2009$status == "archived"))
})

test_that("psoc parent_code is genuinely derived and independently verifiable", {
  # Verified against real phscs::get_psoc() output: unit group 1111
  # ("Legislators") belongs to minor group 111 ("Legislators and senior
  # officials"), which belongs to sub-major 11, which belongs to major 1.
  d <- phscs_get("psoc", "2012")
  unit_row <- d[d$level == "unit" & d$code == "1111", ]
  expect_equal(nrow(unit_row), 1)
  expect_equal(unit_row$parent_code, "111")

  minor_row <- d[d$level == "minor" & d$code == "111", ]
  expect_equal(minor_row$parent_code, "11")

  submajor_row <- d[d$level == "sub-major" & d$code == "11", ]
  expect_equal(submajor_row$parent_code, "1")

  major_row <- d[d$level == "major" & d$code == "1", ]
  expect_true(is.na(major_row$parent_code))
})

test_that("psic division parent_code is honestly NA (section is a letter, not derivable)", {
  d <- phscs_get("psic", "2019")
  division_rows <- d[d$level == "division", ]
  expect_true(all(is.na(division_rows$parent_code)))

  # But group -> division truncation IS derivable and should be populated.
  group_row <- d[d$level == "group" & d$code == "011", ]
  expect_equal(nrow(group_row), 1)
  expect_equal(group_row$parent_code, "01")
})

test_that("psgc barangay -> municipality -> province -> region chain resolves correctly", {
  d <- psgc_get(psgc::latest_release())

  bgy <- d[d$code == "1001301001", ]  # Balintad
  mun <- d[d$code == "1001301000", ]  # Baungon
  prov <- d[d$code == "1001300000", ]  # Bukidnon
  reg <- d[d$code == "1000000000", ]  # Region X

  expect_equal(nrow(bgy), 1)
  expect_equal(nrow(mun), 1)
  expect_equal(nrow(prov), 1)
  expect_equal(nrow(reg), 1)

  expect_equal(bgy$parent_code, "1001301000")
  expect_equal(mun$parent_code, "1001300000")
  expect_equal(prov$parent_code, "1000000000")
  expect_true(is.na(reg$parent_code))
})

test_that("psgc handles an NCR city with no province segment (irregular layout)", {
  d <- psgc_get(psgc::latest_release())

  # City of Caloocan sits directly under the NCR region -- there is no
  # province level in NCR. The generic zero-trailing-digits scan must skip
  # the (no-op) province/municipality truncations and resolve straight to
  # the region, without any NCR-specific special-casing in the adapter.
  city <- d[d$code == "1380100000", ]
  region <- d[d$code == "1300000000", ]

  expect_equal(nrow(city), 1)
  expect_equal(nrow(region), 1)
  expect_equal(city$level, "City")
  expect_equal(region$level, "Reg")
  expect_equal(city$parent_code, "1300000000")
})

test_that("psgc_versions/psgc_levels/psgc_metadata behave as documented", {
  versions <- psgc_versions()
  expect_true(psgc::latest_release() %in% versions)

  levels <- psgc_levels(psgc::latest_release())
  expect_true(all(c("Reg", "Prov", "Mun", "Bgy") %in% levels))

  meta_latest <- psgc_metadata(psgc::latest_release())
  expect_equal(meta_latest$status, "current")
  expect_equal(meta_latest$system, "psgc")

  older <- versions[versions != psgc::latest_release()][1]
  meta_older <- psgc_metadata(older)
  expect_equal(meta_older$status, "archived")
})

test_that("phscs_versions/phscs_levels/phscs_metadata behave as documented", {
  expect_equal(phscs_versions("psic"), "2019")
  expect_equal(phscs_levels("psoc", "2012"), c("major", "sub-major", "minor", "unit"))

  meta <- phscs_metadata("psic", "2019")
  expect_equal(meta$status, "archived")
  expect_equal(meta$system, "psic")
  expect_equal(meta$source, "Philippine Statistics Authority")
  expect_true(nzchar(meta$license))
})
