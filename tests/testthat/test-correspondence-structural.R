# Workstream B acceptance tests for R/correspondence/structural_graph.R.
#
# Two jobs:
#   1. pin the section-level graph (forward, reverse, and their symmetry);
#   2. VALIDATE the graph's structural claims against the actual normalized
#      2019 and 2026 PSIC data, rather than trusting the spec's expected
#      structure blindly (spec section 4).

# --- Expected structures (spec section 1 / section 4) ----------------------
# These are the *verification targets*. Where the real data disagrees the
# discrepancy is documented in R/correspondence/structural_graph.R's header
# and docs/CORRESPONDENCE_SOURCES.md, not silently forced.

expected_2026_ranges <- list(
  A = c("01", "03"), B = c("05", "09"), C = c("10", "33"), D = c("35", "35"),
  E = c("36", "39"), F = c("41", "44"), G = c("46", "47"), H = c("49", "53"),
  I = c("55", "56"), J = c("58", "60"), K = c("61", "63"), L = c("64", "66"),
  M = c("68", "68"), N = c("69", "75"), O = c("77", "82"), P = c("84", "84"),
  Q = c("85", "85"), R = c("86", "88"), S = c("90", "93"), T = c("94", "96"),
  U = c("97", "98"), V = c("99", "99")
)

expected_forward <- list(
  A = "A", B = "B", C = "C", D = "D", E = "E", F = "F",
  G = c("G", "T"),
  H = "H", I = "I",
  J = c("J", "K"),
  K = "L", L = "M", M = "N", N = "O", O = "P", P = "Q",
  Q = "R", R = "S", S = "T", T = "U", U = "V"
)

expected_reverse <- list(
  A = "A", B = "B", C = "C", D = "D", E = "E", F = "F",
  G = "G", H = "H", I = "I",
  J = "J", K = "J", L = "K", M = "L", N = "M", O = "N", P = "O",
  Q = "P", R = "Q", S = "R",
  T = c("G", "S"),
  U = "T", V = "U"
)

# ---------------------------------------------------------------------------
# Graph shape
# ---------------------------------------------------------------------------

test_that("PSIC_SECTION_GRAPH has the frozen column contract", {
  expect_true(is.data.frame(PSIC_SECTION_GRAPH))
  expect_identical(
    names(PSIC_SECTION_GRAPH),
    c("from_version", "from_section", "to_version", "to_section",
      "relation_type", "rationale", "evidence_key", "provenance_default")
  )
  for (col in names(PSIC_SECTION_GRAPH)) {
    expect_true(is.character(PSIC_SECTION_GRAPH[[col]]), info = col)
    expect_false(anyNA(PSIC_SECTION_GRAPH[[col]]), info = col)
  }
  expect_true(all(PSIC_SECTION_GRAPH$from_version == "2019"))
  expect_true(all(PSIC_SECTION_GRAPH$to_version == "2026"))
})

test_that("section-level relation_type stays in the three-value vocabulary", {
  expect_setequal(
    unique(PSIC_SECTION_GRAPH$relation_type),
    c("unchanged", "renamed", "split")
  )
  # And each is a subset of the wider schema vocabulary.
  expect_true(all(PSIC_SECTION_GRAPH$relation_type %in% CORRESPONDENCE_RELATION_TYPES))
})

test_that("every 2019 and 2026 section in the data appears in the graph", {
  p19 <- get_classification("psic", "2019")
  p26 <- get_classification("psic", "2026")
  sections_19 <- sort(unique(p19$code[p19$level == "section"]))
  sections_26 <- sort(unique(p26$code[p26$level == "section"]))

  expect_identical(sections_19, LETTERS[1:21])
  expect_identical(sections_26, LETTERS[1:22])

  expect_setequal(unique(PSIC_SECTION_GRAPH$from_section), sections_19)
  expect_setequal(unique(PSIC_SECTION_GRAPH$to_section), sections_26)
})

# ---------------------------------------------------------------------------
# Forward edges (spec section 4)
# ---------------------------------------------------------------------------

test_that("psic_section_targets() reproduces every expected 2019 -> 2026 edge", {
  for (src in names(expected_forward)) {
    expect_setequal(psic_section_targets(src), expected_forward[[src]])
  }
})

test_that("2019 G splits to 2026 G and T; 2019 J splits to 2026 J and K", {
  expect_setequal(psic_section_targets("G"), c("G", "T"))
  expect_setequal(psic_section_targets("J"), c("J", "K"))

  g_rows <- PSIC_SECTION_GRAPH[PSIC_SECTION_GRAPH$from_section == "G", ]
  j_rows <- PSIC_SECTION_GRAPH[PSIC_SECTION_GRAPH$from_section == "J", ]
  expect_true(all(g_rows$relation_type == "split"))
  expect_true(all(j_rows$relation_type == "split"))
})

test_that("the K-onward one-letter shift is recorded as 'renamed'", {
  shifted <- c(K = "L", L = "M", M = "N", N = "O", O = "P", P = "Q",
               Q = "R", R = "S", S = "T", T = "U", U = "V")
  for (src in names(shifted)) {
    expect_identical(psic_section_targets(src), unname(shifted[src]))
    row <- PSIC_SECTION_GRAPH[PSIC_SECTION_GRAPH$from_section == src, ]
    expect_identical(nrow(row), 1L)
    expect_identical(row$relation_type, "renamed")
  }
})

test_that("psic_section_targets() is well-behaved for unknown input", {
  expect_identical(psic_section_targets("Z"), character(0))
  expect_identical(psic_section_targets("A", from_version = "2026", to_version = "2019"),
                   character(0))
})

# ---------------------------------------------------------------------------
# Reverse edges (spec section 5)
# ---------------------------------------------------------------------------

test_that("psic_section_sources() reproduces every expected 2026 -> 2019 edge", {
  for (tgt in names(expected_reverse)) {
    expect_setequal(psic_section_sources(tgt), expected_reverse[[tgt]])
  }
})

test_that("2026 T is multi-source: 2019 S plus the migrated 2019 G repair content", {
  expect_setequal(psic_section_sources("T"), c("S", "G"))
})

test_that("psic_section_sources() is well-behaved for unknown input", {
  expect_identical(psic_section_sources("Z"), character(0))
  expect_identical(psic_section_sources("A", from_version = "2019", to_version = "2026"),
                   character(0))
})

# ---------------------------------------------------------------------------
# Forward/reverse symmetry as a property of the single table
# ---------------------------------------------------------------------------

test_that("every graph edge round-trips forward -> reverse", {
  for (i in seq_len(nrow(PSIC_SECTION_GRAPH))) {
    row <- PSIC_SECTION_GRAPH[i, ]
    back <- psic_section_sources(row$to_section,
                                 from_version = row$to_version,
                                 to_version = row$from_version)
    expect_true(row$from_section %in% back,
                info = sprintf("edge %s%s -> %s%s missing from reverse lookup",
                               row$from_version, row$from_section,
                               row$to_version, row$to_section))
  }
})

test_that("every graph edge round-trips reverse -> forward", {
  for (i in seq_len(nrow(PSIC_SECTION_GRAPH))) {
    row <- PSIC_SECTION_GRAPH[i, ]
    fwd <- psic_section_targets(row$from_section,
                                from_version = row$from_version,
                                to_version = row$to_version)
    expect_true(row$to_section %in% fwd,
                info = sprintf("edge %s%s -> %s%s missing from forward lookup",
                               row$from_version, row$from_section,
                               row$to_version, row$to_section))
  }
})

test_that("the forward and reverse closures cover exactly the same edge set", {
  fwd_pairs <- sort(unlist(lapply(unique(PSIC_SECTION_GRAPH$from_section), function(s) {
    paste0(s, ">", psic_section_targets(s))
  })))
  rev_pairs <- sort(unlist(lapply(unique(PSIC_SECTION_GRAPH$to_section), function(s) {
    paste0(psic_section_sources(s), ">", s)
  })))
  expect_identical(fwd_pairs, rev_pairs)
})

# ---------------------------------------------------------------------------
# Section -> division membership, validated against real data
# ---------------------------------------------------------------------------

test_that("2026 divisions carry their section in parent_code (the data-derived path)", {
  p26 <- get_classification("psic", "2026")
  drows <- p26[p26$level == "division", ]
  expect_identical(nrow(drows), 88L)
  expect_false(anyNA(drows$parent_code))
  expect_true(all(drows$parent_code %in% LETTERS[1:22]))
})

test_that("2026 section -> division membership matches the official PSA broad structure", {
  observed <- .psic_observed_divisions("2026")
  for (sec in names(expected_2026_ranges)) {
    lo <- expected_2026_ranges[[sec]][1]
    hi <- expected_2026_ranges[[sec]][2]
    expect_identical(
      psic_section_divisions(sec, "2026"),
      observed[observed >= lo & observed <= hi],
      info = sec
    )
  }
})

test_that("2026 division map derived from data equals the declared official ranges", {
  from_data <- .psic_division_section_map("2026")
  declared <- .psic_declared_division_section_map("2026")
  expect_identical(from_data[order(names(from_data))],
                   declared[order(names(declared))])
})

test_that("2019 divisions have NO section parent in the data (documented quirk)", {
  # This is *why* the 2019 map is declared rather than read. If a future
  # phscs/adapter change starts supplying these, revisit the derivation.
  p19 <- get_classification("psic", "2019")
  drows <- p19[p19$level == "division", ]
  expect_identical(nrow(drows), 88L)
  expect_true(all(is.na(drows$parent_code)))
})

test_that("the 2019 section map partitions every observed division exactly once", {
  observed <- .psic_observed_divisions("2019")
  map <- .psic_division_section_map("2019")

  expect_identical(sort(names(map)), observed)   # invents nothing, drops nothing
  expect_false(anyNA(map))                       # assigns everything

  # Union of all sections' divisions is the observed set, with no overlap.
  by_section <- lapply(LETTERS[1:21], psic_section_divisions, version = "2019")
  expect_identical(sort(unlist(by_section)), observed)
  expect_identical(length(unlist(by_section)), length(observed))
})

test_that("2019 section blocks are contiguous and ascend with the section letter", {
  observed <- .psic_observed_divisions("2019")
  map <- .psic_division_section_map("2019")
  in_order <- unname(map[observed])

  # Contiguity: one run per section, no section reappearing later.
  runs <- rle(in_order)
  expect_identical(length(runs$values), 21L)
  expect_identical(anyDuplicated(runs$values), 0L)
  # Ascending: run order equals alphabetical section order.
  expect_identical(runs$values, LETTERS[1:21])
})

test_that("2019 division 45 exists and 2026 division 45 does not", {
  expect_identical(psic_division_section("45", "2019"), "G")
  expect_true(is.na(psic_division_section("45", "2026")))
  expect_true(is.na(psic_division_section("44", "2019")))
  expect_identical(psic_division_section("44", "2026"), "F")
})

test_that("psic_division_section() returns NA for unknown or non-division input", {
  expect_true(is.na(psic_division_section("ZZ", "2019")))
  expect_true(is.na(psic_division_section(NA_character_, "2026")))
  expect_identical(psic_division_section(character(0), "2026"), character(0))
  expect_identical(psic_division_section(c("01", "99"), "2026"), c("A", "V"))
})

test_that("psic_section_divisions() returns character(0) for a missing section", {
  expect_identical(psic_section_divisions("V", "2019"), character(0))
  expect_identical(psic_section_divisions("Z", "2026"), character(0))
})

# ---------------------------------------------------------------------------
# Cross-edition validation of the section graph against real division sets
# ---------------------------------------------------------------------------

test_that("every 'unchanged'/'renamed' edge has identical 2019 and 2026 division sets", {
  simple <- PSIC_SECTION_GRAPH[PSIC_SECTION_GRAPH$relation_type != "split", ]
  for (i in seq_len(nrow(simple))) {
    row <- simple[i, ]
    src <- psic_section_divisions(row$from_section, "2019")
    tgt <- psic_section_divisions(row$to_section, "2026")
    if (row$from_section == "F") {
      # Documented discrepancy 1: 2026 F additionally holds division 44,
      # which has no 2019 counterpart anywhere in the data.
      expect_identical(setdiff(src, tgt), character(0))
      expect_identical(setdiff(tgt, src), "44")
    } else {
      expect_identical(src, tgt,
                       info = sprintf("2019 %s vs 2026 %s", row$from_section, row$to_section))
    }
  }
})

test_that("the G split is confirmed by real division sets", {
  # 2019 G = 45, 46, 47. 2026 G = 46, 47. Division 45 is the one that goes.
  expect_identical(psic_section_divisions("G", "2019"), c("45", "46", "47"))
  expect_identical(psic_section_divisions("G", "2026"), c("46", "47"))
  expect_true("95" %in% psic_section_divisions("T", "2026"))
})

test_that("the J split is confirmed by real division sets", {
  expect_identical(psic_section_divisions("J", "2019"), c("58", "59", "60", "61", "62", "63"))
  expect_identical(psic_section_divisions("J", "2026"), c("58", "59", "60"))
  expect_identical(psic_section_divisions("K", "2026"), c("61", "62", "63"))
  # The split is exhaustive and non-overlapping.
  expect_identical(
    sort(c(psic_section_divisions("J", "2026"), psic_section_divisions("K", "2026"))),
    psic_section_divisions("J", "2019")
  )
})

# ---------------------------------------------------------------------------
# psic_is_repair_migration() -- fixtures taken from data/psic_2026.rds
# ---------------------------------------------------------------------------

test_that("the 2026 repair-migration fixtures exist in the real data", {
  p26 <- get_classification("psic", "2026")
  codes <- setNames(p26$label, p26$code)
  expect_identical(unname(codes[["95"]]),
                   "Repair and Maintenance of Computers, Personal and Household Goods, and Motor Vehicles and Motorcycles")
  expect_identical(unname(codes[["953"]]),
                   "Repair and maintenance of motor vehicles and motorcycles")
  expect_identical(unname(codes[["9531"]]), "Repair and maintenance of motor vehicles")
  expect_identical(unname(codes[["95311"]]), "General repair and maintenance of motor vehicles")
  expect_identical(unname(codes[["4610"]]), "Wholesale on a fee or contract basis")
})

test_that("psic_is_repair_migration() is TRUE for group 953 and its descendants", {
  expect_true(psic_is_repair_migration("953"))
  expect_true(psic_is_repair_migration("9531"))
  expect_true(psic_is_repair_migration("95311"))   # General repair and maintenance of motor vehicles
  expect_true(psic_is_repair_migration("9532"))    # Repair and maintenance of motorcycles
  expect_true(psic_is_repair_migration("95340"))   # Motor vehicle and motorcycle washing and detailing
})

test_that("psic_is_repair_migration() is FALSE for 2026 trade codes", {
  expect_false(psic_is_repair_migration("46"))
  expect_false(psic_is_repair_migration("4610"))   # Wholesale on a fee or contract basis
  expect_false(psic_is_repair_migration("47"))
  expect_false(psic_is_repair_migration("4741"))
})

test_that("psic_is_repair_migration() excludes the parts of division 95 that came from 2019 S", {
  # 951/952 continue 2019 division 95, which sat under 2019 section S.
  expect_false(psic_is_repair_migration("95"))
  expect_false(psic_is_repair_migration("951"))
  expect_false(psic_is_repair_migration("9510"))
  expect_false(psic_is_repair_migration("952"))
  expect_false(psic_is_repair_migration("954"))
})

test_that("psic_is_repair_migration() handles NA and vector input", {
  expect_false(psic_is_repair_migration(NA_character_))
  expect_identical(psic_is_repair_migration(c("953", "4610", NA)), c(TRUE, FALSE, FALSE))
})

# ---------------------------------------------------------------------------
# psic_g_disposition() -- fixtures taken from the real 2019 data
# ---------------------------------------------------------------------------

test_that("the 2019 section-G fixtures exist in the real data with the expected labels", {
  p19 <- get_classification("psic", "2019")
  lab <- setNames(p19$label, p19$code)
  expect_identical(unname(lab[["45"]]),
                   "Wholesale and retail trade and repair of motor vehicles and motorcycles")
  expect_identical(unname(lab[["4510"]]), "Sale of motor vehicles")
  expect_identical(unname(lab[["45101"]]), "Sale of passenger motor vehicles")
  expect_identical(unname(lab[["4520"]]), "Maintenance and repair of motor vehicles")
  expect_identical(unname(lab[["45201"]]), "Repair of motor vehicles, including overhauling")
  expect_identical(unname(lab[["4540"]]),
                   "Sale, maintenance and repair of motorcycles and related parts and accessories")
})

test_that("psic_g_disposition() returns 'repair' for real motor-vehicle repair codes", {
  expect_identical(psic_g_disposition("45201"), "repair")  # Repair of motor vehicles, incl. overhauling
  expect_identical(psic_g_disposition("4520"), "repair")   # Maintenance and repair of motor vehicles
  expect_identical(psic_g_disposition("452"), "repair")
  expect_identical(psic_g_disposition("45202"), "repair")  # Repair of batteries for motor vehicles
  expect_identical(psic_g_disposition("45203"), "repair")  # Vulcanizing or preparing of tires
  expect_identical(psic_g_disposition("45204"), "repair")  # Car washing and auto-detailing services
  expect_identical(psic_g_disposition("45402"), "repair")  # Maintenance and repair of motorcycles
})

test_that("psic_g_disposition() returns 'trade' for real vehicle-sales codes", {
  expect_identical(psic_g_disposition("45101"), "trade")   # Sale of passenger motor vehicles
  expect_identical(psic_g_disposition("4510"), "trade")    # Sale of motor vehicles
  expect_identical(psic_g_disposition("451"), "trade")
  expect_identical(psic_g_disposition("45301"), "trade")   # Wholesale of motor vehicles parts
  expect_identical(psic_g_disposition("45302"), "trade")   # Retail sale of motor vehicles parts
  expect_identical(psic_g_disposition("45401"), "trade")   # Sale of motorcycles
})

test_that("psic_g_disposition() calls all of 2019 divisions 46 and 47 'trade'", {
  p19 <- get_classification("psic", "2019")
  trade_codes <- p19$code[substr(p19$code, 1, 2) %in% c("46", "47")]
  expect_gt(length(trade_codes), 100)
  expect_true(all(psic_g_disposition(trade_codes) == "trade"))
})

test_that("psic_g_disposition() returns NA where a record genuinely straddles the split", {
  expect_true(is.na(psic_g_disposition("G")))      # the section itself
  expect_true(is.na(psic_g_disposition("45")))     # "...trade and repair of motor vehicles..."
  expect_true(is.na(psic_g_disposition("454")))    # "Sale, maintenance and repair of motorcycles..."
  expect_true(is.na(psic_g_disposition("4540")))
})

test_that("psic_g_disposition() returns NA outside section G", {
  expect_true(is.na(psic_g_disposition("5811")))   # section J
  expect_true(is.na(psic_g_disposition("95")))     # 2019 section S
  expect_true(is.na(psic_g_disposition("99999")))  # not a 2019 code at all
  expect_true(is.na(psic_g_disposition(NA_character_)))
  expect_identical(psic_g_disposition(character(0)), character(0))
})

test_that("psic_g_disposition() partitions 2019 division 45 without contradiction", {
  p19 <- get_classification("psic", "2019")
  d45 <- p19$code[substr(p19$code, 1, 2) == "45"]
  disp <- psic_g_disposition(d45)
  expect_true(all(disp %in% c("trade", "repair", NA_character_)))
  expect_gt(sum(disp == "trade", na.rm = TRUE), 0)
  expect_gt(sum(disp == "repair", na.rm = TRUE), 0)
  # Only the genuinely mixed nodes are undetermined.
  expect_setequal(d45[is.na(disp)], c("45", "454", "4540"))
})

# ---------------------------------------------------------------------------
# psic_j_disposition() -- fixtures taken from the real 2019 data
# ---------------------------------------------------------------------------

test_that("the 2019 section-J fixtures exist in the real data with the expected labels", {
  p19 <- get_classification("psic", "2019")
  lab <- setNames(p19$label, p19$code)
  expect_identical(unname(lab[["5811"]]), "Book Publishing")
  expect_identical(unname(lab[["60"]]), "Programming and broadcasting activities")
  expect_identical(unname(lab[["6110"]]), "Wired telecommunications activities")
  expect_identical(unname(lab[["6201"]]), "Computer programming activities")
  expect_identical(unname(lab[["6311"]]), "Data processing, hosting and related activities")
})

test_that("psic_j_disposition() returns 'J' for real publishing/broadcasting codes", {
  expect_identical(psic_j_disposition("5811"), "J")   # Book Publishing
  expect_identical(psic_j_disposition("58"), "J")     # Publishing activities
  expect_identical(psic_j_disposition("581"), "J")
  expect_identical(psic_j_disposition("59"), "J")     # Motion picture / sound recording
  expect_identical(psic_j_disposition("60"), "J")     # Programming and broadcasting
  expect_identical(psic_j_disposition("602"), "J")
})

test_that("psic_j_disposition() returns 'K' for real telecom / computer-programming codes", {
  expect_identical(psic_j_disposition("6110"), "K")   # Wired telecommunications activities
  expect_identical(psic_j_disposition("61"), "K")     # Telecommunications
  expect_identical(psic_j_disposition("6201"), "K")   # Computer programming activities
  expect_identical(psic_j_disposition("62"), "K")
  expect_identical(psic_j_disposition("6311"), "K")   # Data processing, hosting
  expect_identical(psic_j_disposition("63"), "K")
})

test_that("psic_j_disposition() covers every 2019 section-J code with J or K", {
  p19 <- get_classification("psic", "2019")
  j_codes <- p19$code[substr(p19$code, 1, 2) %in% c("58", "59", "60", "61", "62", "63")]
  expect_gt(length(j_codes), 50)
  disp <- psic_j_disposition(j_codes)
  expect_false(anyNA(disp))
  expect_setequal(unique(disp), c("J", "K"))
  # And each code's target agrees with the section graph's allowed targets.
  expect_true(all(disp %in% psic_section_targets("J")))
})

test_that("psic_j_disposition() returns NA for the straddling section letter and non-J codes", {
  expect_true(is.na(psic_j_disposition("J")))
  expect_true(is.na(psic_j_disposition("45201")))
  expect_true(is.na(psic_j_disposition("99999")))
  expect_true(is.na(psic_j_disposition(NA_character_)))
  expect_identical(psic_j_disposition(character(0)), character(0))
})

# ---------------------------------------------------------------------------
# Dispositions agree with the graph they are meant to route through
# ---------------------------------------------------------------------------

test_that("G/J dispositions only ever name sections the graph allows", {
  expect_setequal(psic_section_targets("G"), c("G", "T"))
  expect_setequal(psic_section_targets("J"), c("J", "K"))

  # "trade" routes to 2026 G; "repair" routes to 2026 T group 953.
  expect_true("G" %in% psic_section_targets("G"))
  expect_true("T" %in% psic_section_targets("G"))
  expect_identical(psic_division_section("95", "2026"), "T")
  expect_true(psic_is_repair_migration("953"))
})
