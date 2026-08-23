# P0 regression matrix for the repaired PSIC 2019 <-> Revision 5 (2026)
# detailed correspondence (spec section 18).
#
# These assert the SHIPPED ARTIFACT, not the resolver in isolation: what
# matters for staging is that Compare Editions actually shows the right
# thing, and the artifact is what it reads. Every fixture below is a real
# record from the local datasets.
#
# Root cause these guard against: the pre-repair builder matched on exact
# code -> 4-digit class prefix -> 3/2-digit prefix + label similarity. It
# had no model of PSA's section restructuring, so where a whole division
# was dissolved it produced nothing at all. Measured on the pre-repair
# artifact: all 16 of 2019 division 45's sub-classes (motor-vehicle trade
# AND repair) were "discontinued" with target_code = NA, and the artifact
# contained zero section-level rows.

.detailed_artifact <- function() {
  path <- NULL
  for (p in c("data/psic_2019_to_2026_correspondence.rds",
              file.path("..", "..", "data", "psic_2019_to_2026_correspondence.rds"))) {
    if (file.exists(p)) { path <- p; break }
  }
  testthat::skip_if(is.null(path), "correspondence artifact not built")
  readRDS(path)
}

.targets_for <- function(d, code) {
  rows <- d[!is.na(d$source_code) & d$source_code == code & !is.na(d$target_code), , drop = FALSE]
  rows$target_code
}

# ---------------------------------------------------------------------------
# Section-level structure -- the layer that did not exist before
# ---------------------------------------------------------------------------

test_that("the artifact now carries section-level edges at all", {
  d <- .detailed_artifact()
  expect_gt(sum(d$source_level == "section", na.rm = TRUE), 0)
})

test_that("2019 G maps to BOTH 2026 G and 2026 T", {
  d <- .detailed_artifact()
  s <- d[d$source_level == "section" & !is.na(d$source_code) & d$source_code == "G", ]
  expect_setequal(s$target_code, c("G", "T"))
  # Deterministic structural movement, never a fuzzy guess.
  expect_true(all(s$provenance == "derived"))
  expect_true(all(s$confidence == "high"))
  expect_false(any(s$provenance == "official"))
})

test_that("2019 J splits across 2026 J and 2026 K", {
  d <- .detailed_artifact()
  s <- d[d$source_level == "section" & !is.na(d$source_code) & d$source_code == "J", ]
  expect_setequal(s$target_code, c("J", "K"))
})

test_that("the K-onward section letter shift is represented end to end", {
  d <- .detailed_artifact()
  s <- d[d$source_level == "section" & !is.na(d$source_code), ]
  shift <- c(K = "L", L = "M", M = "N", N = "O", O = "P",
             P = "Q", Q = "R", R = "S", S = "T", T = "U", U = "V")
  for (from in names(shift)) {
    got <- s$target_code[s$source_code == from]
    expect_equal(got, unname(shift[[from]]), info = paste("2019", from))
  }
})

test_that("sections that did not move still map to themselves", {
  d <- .detailed_artifact()
  s <- d[d$source_level == "section" & !is.na(d$source_code), ]
  for (from in c("A", "B", "C", "D", "E", "F", "H", "I")) {
    expect_equal(s$target_code[s$source_code == from], from, info = from)
  }
})

# ---------------------------------------------------------------------------
# Motor vehicles / motorcycles -- the mandatory domain (spec section 6)
# ---------------------------------------------------------------------------

test_that("no 2019 division-45 sub-class is left unmapped any more", {
  d <- .detailed_artifact()
  v <- d[!is.na(d$source_code) & startsWith(d$source_code, "45"), ]
  expect_gt(nrow(v), 0)
  # Was 16/16 discontinued before the repair.
  expect_equal(sum(v$relation_type == "discontinued"), 0)
  expect_true(all(!is.na(v$target_code)))
})

test_that("2019 motor-vehicle REPAIR routes into Revision 5 section T repair structure", {
  d <- .detailed_artifact()
  # 45201 "Repair of motor vehicles, including overhauling"
  tg <- .targets_for(d, "45201")
  expect_gt(length(tg), 0)
  # Division 95 = Repair and Maintenance, group 953 = motor vehicles and
  # motorcycles, per PSA's Section T training material.
  expect_true(all(startsWith(tg, "95")))
  expect_true(any(startsWith(tg, "953")))
  # And specifically NOT into the trade structure.
  expect_false(any(startsWith(tg, "46")))
  expect_false(any(startsWith(tg, "47")))
})

test_that("2019 motor-vehicle SALES route into the Revision 5 trade structure, not repair", {
  d <- .detailed_artifact()
  # 45101 "Sale of passenger motor vehicles"
  tg <- .targets_for(d, "45101")
  expect_gt(length(tg), 0)
  expect_true(all(startsWith(tg, "46") | startsWith(tg, "47")))
  # This is the specific bug the spec forbids: do not send every former
  # division-45 descendant to T.
  expect_false(any(startsWith(tg, "95")))
})

test_that("battery and tyre repair reach their Revision 5 counterparts", {
  d <- .detailed_artifact()
  # 45202 "Repair of batteries for motor vehicles" -> 95314 exists in 2026.
  batt <- .targets_for(d, "45202")
  expect_true(all(startsWith(batt, "95")))
  expect_true("95314" %in% batt)

  # 45203 "Vulcanizing or preparing of tires for motor vehicles"
  tyre <- .targets_for(d, "45203")
  expect_true(all(startsWith(tyre, "95")))
})

test_that("trade and repair descendants of division 45 are cleanly separated", {
  d <- .detailed_artifact()
  v <- d[!is.na(d$source_code) & startsWith(d$source_code, "45") & !is.na(d$target_code), ]
  v$t2 <- substr(v$target_code, 1, 2)

  by_source <- split(v$t2, v$source_code)
  for (code in names(by_source)) {
    tgts <- unique(by_source[[code]])
    # Each source lands wholly in trade (46/47) or wholly in repair (95) --
    # never straddling both, which would mean the disposition test failed.
    all_trade  <- all(tgts %in% c("46", "47"))
    all_repair <- all(tgts == "95")
    expect_true(all_trade || all_repair, info = paste(code, paste(tgts, collapse = "/")))
  }
})

# ---------------------------------------------------------------------------
# J -> J/K at detailed level
# ---------------------------------------------------------------------------

test_that("2019 J descendants route by division into 2026 J (58-60) or K (61-63)", {
  d <- .detailed_artifact()
  j <- d[!is.na(d$source_code) & !is.na(d$target_code) &
           d$source_level == "sub-class" &
           substr(d$source_code, 1, 2) %in% c("58", "59", "60", "61", "62", "63"), ]
  expect_gt(nrow(j), 0)

  j_side <- c("58", "59", "60")
  k_side <- c("61", "62", "63")

  from_j <- j[substr(j$source_code, 1, 2) %in% j_side, ]
  from_k <- j[substr(j$source_code, 1, 2) %in% k_side, ]

  # Publishing/broadcasting/content stays in the 58-60 (2026 J) space.
  expect_true(all(substr(from_j$target_code, 1, 2) %in% j_side))
  # Telecoms/computing/information services land in 61-63 (2026 K).
  expect_true(all(substr(from_k$target_code, 1, 2) %in% k_side))
})

# ---------------------------------------------------------------------------
# Letter-shift continuity must not be down-ranked to fuzzy
# ---------------------------------------------------------------------------

test_that("continuity across a shifted section letter is derived and high confidence", {
  d <- .detailed_artifact()
  # 2019 section K (financial and insurance) -> 2026 section L. Divisions
  # 64-66 keep their numbers across the shift, so this is deterministic
  # continuity, NOT a low-confidence label guess.
  fin <- d[!is.na(d$source_code) & !is.na(d$target_code) &
             d$source_level == "sub-class" &
             substr(d$source_code, 1, 2) %in% c("64", "65", "66"), ]
  skip_if(nrow(fin) == 0, "no financial sub-class rows in artifact")

  exact <- fin[fin$source_code == fin$target_code, ]
  expect_gt(nrow(exact), 0)
  expect_true(all(exact$provenance == "derived"))
  expect_true(all(exact$confidence == "high"))
  expect_false(any(exact$provenance == "suggested"))
})

# ---------------------------------------------------------------------------
# Provenance and multiplicity invariants
# ---------------------------------------------------------------------------

test_that("no edge anywhere in the artifact is labelled official", {
  d <- .detailed_artifact()
  expect_false("official" %in% d$provenance)
  expect_true(all(d$provenance %in% c("derived", "suggested")))
})

test_that("multiplicity is preserved rather than flattened to one best target", {
  d <- .detailed_artifact()
  # A split must actually appear as several rows sharing one source.
  splits <- d[d$relation_type == "split" & !is.na(d$source_code), ]
  expect_gt(nrow(splits), 0)
  counts <- table(splits$source_code)
  expect_gt(max(counts), 1)

  # And a merge as several sources sharing one target.
  merges <- d[d$relation_type == "merged" & !is.na(d$target_code), ]
  if (nrow(merges) > 0) {
    expect_gt(max(table(merges$target_code)), 1)
  }
})

test_that("every derived edge carries evidence explaining why it exists", {
  d <- .detailed_artifact()
  derived <- d[d$provenance == "derived", ]
  expect_true(all(!is.na(derived$evidence) & nzchar(derived$evidence)))
})

test_that("the repair reduced the number of unmapped 2019 sub-classes", {
  d <- .detailed_artifact()
  disc <- sum(d$relation_type == "discontinued", na.rm = TRUE)
  # 143 before the structural repair; the point of the fix is that whole
  # dissolved divisions now resolve. Guard against silent regression.
  expect_lt(disc, 50)
})
