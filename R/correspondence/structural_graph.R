# Deterministic SECTION-LEVEL structural graph for PSIC 2019 <-> PSIC
# Revision 5 (2026).
#
# WHY THIS FILE EXISTS
# --------------------
# The similarity/hierarchy scorer in R/correspondence/scoring.R has no model
# of PSA's section-letter restructuring between the two editions. It can
# therefore never represent, on its own:
#
#   * 2019 G (Wholesale/Retail Trade AND repair of motor vehicles and
#     motorcycles) becoming 2026 G (trade, divisions 46-47) PLUS part of
#     2026 T (division 95, group 953 -- repair and maintenance of motor
#     vehicles and motorcycles);
#   * 2019 J (Information and Communication, divisions 58-63) becoming
#     2026 J (divisions 58-60) PLUS 2026 K (divisions 61-63);
#   * the downstream one-letter shift that the J split forces on every
#     later section (2019 K -> 2026 L, ... 2019 U -> 2026 V).
#
# This module is the deterministic, direction-agnostic source of truth for
# that restructuring. It is pure structure: it decides *which section* a
# concept lands in, never *which specific row*. Row-level multiplicity is
# the detailed mapping engine's job.
#
# EVIDENCE AND PROVENANCE
# -----------------------
# Every edge carries `provenance_default = "derived"`. Per spec sections 10
# and 15, `official` is reserved exclusively for an explicit PSA-published
# correspondence record, and no such record has been incorporated into this
# application (see docs/CORRESPONDENCE_SOURCES.md). The PSA Revision 5
# broad structure and the PSA Section T training material are official
# *structural* evidence about each edition; combining two official
# structures into a mapping between them is derivation, not an official
# crosswalk.
#
# METHOD RULE (spec section 4)
# ----------------------------
# The section graph below is a *verification target*, not blind truth. Its
# division-range claims are validated against the actual normalized 2019
# and 2026 data by tests/testthat/test-correspondence-structural.R. Where
# the real data contradicts an expected relationship, the discrepancy is
# documented (see "KNOWN DISCREPANCIES" below and
# docs/CORRESPONDENCE_SOURCES.md) rather than forced.
#
# SECTION -> DIVISION MEMBERSHIP: HOW EACH EDITION IS DERIVED
# -----------------------------------------------------------
# 2026: derived directly from the data. Every division row in
#   data/psic_2026.rds carries its section letter in `parent_code`
#   (verified: 0 of 88 division rows have an NA parent). The declared
#   range table below is used only as a cross-check and as a fallback if a
#   future rebuild ever drops those parents.
#
# 2019: NOT derivable from the data. `R/adapters/adapter_phscs.R` derives
#   parent_code by code truncation, and no numeric truncation of a division
#   code ("45") can equal a section letter ("G"), so all 88 division rows
#   have parent_code = NA. The upstream `phscs` source table was also
#   inspected: it is level-blocked (all 21 sections, then all 88 divisions,
#   ...), not document-ordered, so an ordinal "last section seen before
#   this division" scan recovers nothing either -- it assigns all 88
#   divisions to section U. There is no section->division edge anywhere in
#   the local 2019 data.
#
#   The 2019 range table below is therefore *declared* from the official
#   PSIC 2019 structure (ISIC Rev.4-aligned), and then validated against
#   the data on three independent axes by the structural tests:
#     (a) partition: it assigns every observed 2019 division exactly once
#         and invents no division that the data does not contain;
#     (b) monotone contiguity: section letters in ascending order map to
#         ascending, non-overlapping, contiguous division blocks;
#     (c) cross-edition agreement: for every "unchanged"/"renamed" edge in
#         PSIC_SECTION_GRAPH, the 2019 source section's division set equals
#         the 2026 target section's data-derived division set -- and for
#         the two "split" sections the division sets partition exactly as
#         the split claims (2019 G 45/46/47 -> 2026 G 46/47; 2019 J 58-63
#         -> 2026 J 58-60 + 2026 K 61-63).
#   Axis (c) is the strong one: it is real evidence out of the 2026 data
#   confirming the declared 2019 boundaries, not a restatement of them.
#
# KNOWN DISCREPANCIES (documented, not forced)
# --------------------------------------------
# 1. 2026 division 44 ("Renting of construction machinery and equipment
#    with operator", section F) has no counterpart anywhere in the 2019
#    data -- the only 2019 "with operator" entry is sub-class 50113
#    ("Renting of ship with operator", section H). Its 2019 antecedent
#    cannot be established from local data, so NO extra section edge into
#    2026 F is asserted. 2019 F -> 2026 F is still recorded as "unchanged"
#    because every 2019 F division (41-43) does land in 2026 F; the inflow
#    is a one-sided gain on the 2026 side.
# 2. 2019 division 45 has no counterpart division code in 2026; its content
#    is redistributed across 2026 G (trade) and 2026 T group 953 (repair).
#    This is the G split and is modelled explicitly.
# 3. 2026 division 95 is a *merged* recipient: groups 951/952 continue 2019
#    division 95 (under 2019 section S), while group 953 receives the
#    repair content migrated out of 2019 section G. `psic_is_repair_migration()`
#    therefore recognises only 953-rooted codes, not all of division 95.

# ---------------------------------------------------------------------------
# Evidence keys
# ---------------------------------------------------------------------------

#' Stable identifiers for the structural evidence behind each graph edge.
#'
#' Internal: the public surface exposes these only as the `evidence_key`
#' column of `PSIC_SECTION_GRAPH` (semicolon-separated when an edge rests
#' on more than one source).
.PSIC_STRUCTURAL_EVIDENCE_KEYS <- c(
  psa_rev5_broad_structure =
    paste("PSA Introduction to PSIC Revision 5 -- official broad structure",
          "(section letter to division range) for the 2026 edition."),
  psa_section_t_training =
    paste("PSA Section T PSIC training material -- official placement of",
          "division 94, division 95 (including repair and maintenance of",
          "motor vehicles and motorcycles) and division 96 in Revision 5",
          "Section T, and identification of group 953."),
  psic_2019_official_structure =
    paste("Official PSIC 2019 structure (ISIC Rev.4-aligned) -- section",
          "letter to division range for the 2019 edition."),
  psic_division_range_continuity =
    paste("Deterministic division-range continuity observed between the",
          "two editions' own normalized structures.")
)

.psic_evidence <- function(...) paste(c(...), collapse = ";")

# ---------------------------------------------------------------------------
# Declared section -> division ranges (verification targets)
# ---------------------------------------------------------------------------

# Official PSA Revision 5 broad structure.
.PSIC_2026_SECTION_DIVISION_RANGES <- list(
  A = c("01", "03"), B = c("05", "09"), C = c("10", "33"), D = c("35", "35"),
  E = c("36", "39"), F = c("41", "44"), G = c("46", "47"), H = c("49", "53"),
  I = c("55", "56"), J = c("58", "60"), K = c("61", "63"), L = c("64", "66"),
  M = c("68", "68"), N = c("69", "75"), O = c("77", "82"), P = c("84", "84"),
  Q = c("85", "85"), R = c("86", "88"), S = c("90", "93"), T = c("94", "96"),
  U = c("97", "98"), V = c("99", "99")
)

# Official PSIC 2019 structure (ISIC Rev.4-aligned). Declared, because the
# local 2019 data carries no section->division edge at all; validated by
# tests/testthat/test-correspondence-structural.R (see header, axes a/b/c).
.PSIC_2019_SECTION_DIVISION_RANGES <- list(
  A = c("01", "03"), B = c("05", "09"), C = c("10", "33"), D = c("35", "35"),
  E = c("36", "39"), F = c("41", "43"), G = c("45", "47"), H = c("49", "53"),
  I = c("55", "56"), J = c("58", "63"), K = c("64", "66"), L = c("68", "68"),
  M = c("69", "75"), N = c("77", "82"), O = c("84", "84"), P = c("85", "85"),
  Q = c("86", "88"), R = c("90", "93"), S = c("94", "96"), T = c("97", "98"),
  U = c("99", "99")
)

.psic_declared_ranges <- function(version) {
  switch(as.character(version),
    "2019" = .PSIC_2019_SECTION_DIVISION_RANGES,
    "2026" = .PSIC_2026_SECTION_DIVISION_RANGES,
    stop(sprintf("No declared PSIC section/division structure for version '%s'", version),
         call. = FALSE)
  )
}

# ---------------------------------------------------------------------------
# The section graph itself
# ---------------------------------------------------------------------------

.psic_build_section_graph <- function() {
  ev_struct <- .psic_evidence("psa_rev5_broad_structure", "psic_2019_official_structure")
  ev_cont <- .psic_evidence("psa_rev5_broad_structure", "psic_2019_official_structure",
                            "psic_division_range_continuity")

  edge <- function(from_section, to_section, relation_type, rationale, evidence_key) {
    list(from_section = from_section, to_section = to_section,
         relation_type = relation_type, rationale = rationale,
         evidence_key = evidence_key)
  }

  # Sections whose letter and division range are identical in both editions.
  unchanged_letters <- c("A", "B", "C", "D", "E", "H", "I")
  unchanged_edges <- lapply(unchanged_letters, function(s) {
    edge(s, s, "unchanged",
         sprintf(paste("Section %s keeps its letter and its division range across",
                       "editions; the 2019 division set equals the 2026 division set."), s),
         ev_cont)
  })

  # 2019 K..U shift down one letter because the J split consumed a letter.
  shift_pairs <- list(
    c("K", "L"), c("L", "M"), c("M", "N"), c("N", "O"), c("O", "P"),
    c("P", "Q"), c("Q", "R"), c("R", "S"), c("S", "T"), c("T", "U"), c("U", "V")
  )
  shift_edges <- lapply(shift_pairs, function(p) {
    edge(p[1], p[2], "renamed",
         sprintf(paste("2019 section %s is re-lettered to 2026 section %s. The scope is",
                       "continuous: both carry the identical division range. The letter",
                       "moves only because splitting 2019 J into 2026 J and 2026 K",
                       "inserted one extra section letter ahead of them."), p[1], p[2]),
         ev_cont)
  })

  special_edges <- list(
    edge("F", "F", "unchanged",
         paste("2019 section F (divisions 41-43) maps wholly to 2026 section F.",
               "2026 F additionally contains division 44 ('Renting of construction",
               "machinery and equipment with operator'), which has no counterpart",
               "anywhere in the 2019 data; that inflow is a one-sided gain on the",
               "2026 side and is deliberately NOT asserted as a section edge from",
               "any 2019 section."),
         ev_cont),

    edge("G", "G", "split",
         paste("2019 section G ('Wholesale and retail trade; repair of motor vehicles",
               "and motorcycles') bundles trade with repair. The trade component --",
               "2019 divisions 46 and 47 in full, plus the sale/wholesale/retail",
               "activities inside division 45 -- continues as 2026 section G",
               "(divisions 46-47)."),
         ev_cont),

    edge("G", "T", "split",
         paste("The repair/maintenance component of 2019 section G (the repair,",
               "maintenance, vulcanizing and washing activities inside division 45)",
               "migrates to 2026 section T, division 95, group 953 ('Repair and",
               "maintenance of motor vehicles and motorcycles'). PSA Section T",
               "training material places division 95 -- explicitly including motor",
               "vehicles and motorcycles -- in Revision 5 Section T. Not all former",
               "division 45 descendants go here: trade descendants stay in G."),
         .psic_evidence("psa_section_t_training", "psa_rev5_broad_structure",
                        "psic_2019_official_structure")),

    edge("J", "J", "split",
         paste("2019 section J ('Information and Communication', divisions 58-63) is",
               "split. Divisions 58-60 (publishing; motion picture, video and",
               "television production and sound recording; programming and",
               "broadcasting) remain section J in Revision 5, retitled 'Publishing,",
               "Broadcasting, and Content Production and Distribution Activities'."),
         ev_cont),

    edge("J", "K", "split",
         paste("The remainder of 2019 section J -- divisions 61 (telecommunications),",
               "62 (computer programming and consultancy) and 63 (information service",
               "activities) -- becomes the new 2026 section K",
               "('Telecommunications, Computer Programming, Consultancy, Computing",
               "Infrastructure, and Other Information Service Activities'). This new",
               "letter is what pushes 2019 K..U down one letter."),
         ev_cont)
  )

  all_edges <- c(unchanged_edges, special_edges, shift_edges)

  ordered <- all_edges[order(
    vapply(all_edges, function(e) e$from_section, character(1)),
    vapply(all_edges, function(e) e$to_section, character(1))
  )]

  tibble::tibble(
    from_version       = rep("2019", length(ordered)),
    from_section       = vapply(ordered, function(e) e$from_section, character(1)),
    to_version         = rep("2026", length(ordered)),
    to_section         = vapply(ordered, function(e) e$to_section, character(1)),
    relation_type      = vapply(ordered, function(e) e$relation_type, character(1)),
    rationale          = vapply(ordered, function(e) e$rationale, character(1)),
    evidence_key       = vapply(ordered, function(e) e$evidence_key, character(1)),
    # Spec sections 10/15: only an explicit PSA-published crosswalk may ever
    # be "official", and none has been incorporated into this application.
    provenance_default = rep("derived", length(ordered))
  )
}

#' Section-level structural graph, PSIC 2019 -> PSIC Revision 5 (2026).
#'
#' Direction-agnostic source of truth: forward lookups
#' (`psic_section_targets()`) and reverse lookups
#' (`psic_section_sources()`) are both computed from this one table, so
#' they cannot drift apart.
#'
#' Columns (all character):
#'   from_version, from_section, to_version, to_section,
#'   relation_type, rationale, evidence_key, provenance_default
#'
#' `relation_type` is deliberately restricted at section level to:
#'   "unchanged" -- same letter, same division scope;
#'   "renamed"   -- letter changed, scope continuous;
#'   "split"     -- one source section feeds several target sections.
#' Row-level multiplicity (merge/reclassify/new/discontinued) belongs to the
#' detailed mapping engine, not here.
PSIC_SECTION_GRAPH <- .psic_build_section_graph()

#' 2026 sections a given 2019 section maps into.
#'
#' @param section character(1) section letter in `from_version`.
#' @param from_version character(1). Edition `section` belongs to.
#' @param to_version character(1). Edition to look the targets up in.
#' @return Sorted character vector of target section letters; `character(0)`
#'   when the section is unknown for that direction (never NULL, never an
#'   error). Length > 1 for the split sections G and J.
psic_section_targets <- function(section, from_version = "2019", to_version = "2026") {
  g <- PSIC_SECTION_GRAPH
  keep <- g$from_version == from_version &
    g$to_version == to_version &
    g$from_section %in% section
  sort(unique(g$to_section[keep]))
}

#' 2019 sections that feed a given 2026 section.
#'
#' Derived from `PSIC_SECTION_GRAPH` itself -- there is deliberately no
#' separately authored reverse table (spec section 5).
#'
#' @param section character(1) section letter in `from_version`.
#' @param from_version character(1). Edition `section` belongs to (2026).
#' @param to_version character(1). Edition to look the sources up in (2019).
#' @return Sorted character vector of source section letters; `character(0)`
#'   when unknown. Length > 1 for 2026 T, which draws from both 2019 S and
#'   the repair content migrated out of 2019 G.
psic_section_sources <- function(section, from_version = "2026", to_version = "2019") {
  g <- PSIC_SECTION_GRAPH
  keep <- g$to_version == from_version &
    g$from_version == to_version &
    g$to_section %in% section
  sort(unique(g$from_section[keep]))
}

# ---------------------------------------------------------------------------
# Section <-> division membership, per edition
# ---------------------------------------------------------------------------

.psic_structural_cache <- new.env(parent = emptyenv())

#' Reset the memoized per-edition division maps. Test helper.
.psic_structural_reset_cache <- function() {
  rm(list = ls(.psic_structural_cache), envir = .psic_structural_cache)
  invisible(NULL)
}

#' Observed division codes for one edition, straight from canonical data.
.psic_observed_divisions <- function(version) {
  data <- get_classification("psic", version)
  sort(unique(data$code[data$level == "division"]))
}

#' Expand the declared range table into a division -> section named vector,
#' restricted to divisions the edition's data actually contains.
#'
#' Range membership is decided by string comparison on the zero-padded
#' two-character division codes, never by numeric coercion -- leading zeros
#' are load-bearing ("01" .. "09").
.psic_declared_division_section_map <- function(version, divisions = NULL) {
  ranges <- .psic_declared_ranges(version)
  if (is.null(divisions)) divisions <- .psic_observed_divisions(version)

  out <- rep(NA_character_, length(divisions))
  names(out) <- divisions
  for (sec in names(ranges)) {
    lo <- ranges[[sec]][1]
    hi <- ranges[[sec]][2]
    hit <- divisions >= lo & divisions <= hi
    out[hit] <- sec
  }
  out
}

#' Division -> section named character vector for one edition.
#'
#' 2026 is read out of the data (`parent_code` on division rows). 2019 has
#' no such edge in the data and falls back to the declared official
#' structure -- see this file's header for the full derivation and the
#' three validation axes the structural tests apply to it.
.psic_division_section_map <- function(version) {
  version <- as.character(version)
  key <- paste0("divsec::", version)
  cached <- .psic_structural_cache[[key]]
  if (!is.null(cached)) return(cached)

  data <- get_classification("psic", version)
  drows <- data[data$level == "division", c("code", "parent_code"), drop = FALSE]
  divisions <- sort(unique(drows$code))

  map <- setNames(rep(NA_character_, length(divisions)), divisions)
  # Data-first: use parent_code wherever the edition actually records the
  # section letter there (true for 2026, never true for 2019).
  from_data <- drows$parent_code[match(divisions, drows$code)]
  usable <- !is.na(from_data) & from_data %in% names(.psic_declared_ranges(version))
  map[usable] <- from_data[usable]

  # Declared-structure fallback for whatever the data cannot supply.
  if (any(is.na(map))) {
    declared <- .psic_declared_division_section_map(version, divisions)
    map[is.na(map)] <- declared[is.na(map)]
  }

  assign(key, map, envir = .psic_structural_cache)
  map
}

#' Which section does this division belong to, in that edition?
#'
#' @param division_code character. Two-character division code(s), e.g. "45".
#' @param version character(1). "2019" or "2026".
#' @return Character vector the same length as `division_code`: the section
#'   letter, or NA_character_ for a division that edition does not contain.
psic_division_section <- function(division_code, version) {
  if (length(division_code) == 0L) return(character(0))
  map <- .psic_division_section_map(version)
  out <- unname(map[as.character(division_code)])
  out[is.na(as.character(division_code))] <- NA_character_
  out
}

#' Division codes belonging to a section, in that edition.
#'
#' @param section character(1). Section letter.
#' @param version character(1). "2019" or "2026".
#' @return Sorted character vector of division codes; `character(0)` when
#'   the section does not exist in that edition.
psic_section_divisions <- function(section, version) {
  map <- .psic_division_section_map(version)
  sort(names(map)[!is.na(map) & map %in% section])
}

# ---------------------------------------------------------------------------
# The G repair migration
# ---------------------------------------------------------------------------

#' Repair/maintenance structure that migrated out of 2019 section G.
#'
#' Revision 5 group 953 ("Repair and maintenance of motor vehicles and
#' motorcycles", inside division 95, inside section T) is the destination of
#' the repair content that 2019 bundled into section G alongside trade.
#'
#' Deliberately NOT all of division 95: groups 951 (computers and
#' communication equipment) and 952 (personal and household goods) continue
#' 2019 division 95, which sat under 2019 section S, not G. Group 954
#' (intermediation services for repair) is a new Revision 5 concept with no
#' 2019 counterpart. Both return FALSE.
#'
#' @param code_2026 character. PSIC Revision 5 code(s) at any level.
#' @return Logical vector the same length as `code_2026`. NA input -> FALSE.
psic_is_repair_migration <- function(code_2026) {
  code <- as.character(code_2026)
  out <- !is.na(code) & startsWith(code, "953")
  unname(out)
}

# ---------------------------------------------------------------------------
# G and J dispositions -- routing 2019 descendants to the right 2026 section
# ---------------------------------------------------------------------------

# Wording evidence used to separate trade from repair inside 2019 division
# 45, which PSA titled "Wholesale and retail trade and repair of motor
# vehicles and motorcycles" and which therefore contains both dispositions
# at every level below itself.
.PSIC_G_REPAIR_PATTERN <- paste(
  "repair", "maintenance", "maintaining", "overhaul", "vulcaniz",
  "washing", "auto-detailing", "detailing", "servicing",
  sep = "|"
)
.PSIC_G_TRADE_PATTERN <- paste(
  "\\bsale\\b", "\\bsales\\b", "selling", "wholesale", "retail",
  "\\btrade\\b", "trading", "dealer",
  sep = "|"
)

#' Cached code -> (label, description) lookup for one edition.
.psic_record_lookup <- function(version) {
  version <- as.character(version)
  key <- paste0("records::", version)
  cached <- .psic_structural_cache[[key]]
  if (!is.null(cached)) return(cached)

  data <- get_classification("psic", version)
  lookup <- list(
    label = setNames(data$label, data$code),
    description = setNames(data$description, data$code)
  )
  assign(key, lookup, envir = .psic_structural_cache)
  lookup
}

.psic_disposition_from_text <- function(txt) {
  if (is.na(txt) || !nzchar(trimws(txt))) return(NA_character_)
  t <- tolower(txt)
  is_repair <- grepl(.PSIC_G_REPAIR_PATTERN, t)
  is_trade <- grepl(.PSIC_G_TRADE_PATTERN, t)
  if (is_repair && !is_trade) return("repair")
  if (is_trade && !is_repair) return("trade")
  NA_character_  # both, or neither -> genuinely undetermined
}

#' Does a 2019 section-G code describe trade or repair?
#'
#' Routes 2019 section-G descendants to 2026 G (trade) versus 2026 T group
#' 953 (repair). The decision uses the record's own evidence, never a
#' hand-typed list of subclass codes:
#'
#'   * divisions 46 and 47 are "Wholesale trade, except of motor vehicles
#'     and motorcycles" and "Retail trade, except of motor vehicles and
#'     motorcycles" -- wholly trade by their own division-level scope, so
#'     every descendant is "trade" on structural evidence alone;
#'   * division 45 mixes both, so its records are judged on their own
#'     label wording (sale / wholesale / retail / trade versus repair /
#'     maintenance / overhaul / vulcanizing / washing), falling back to the
#'     description only when the label says neither.
#'
#' Returns NA rather than guessing when the wording says *both* (e.g. class
#' 4540 "Sale, maintenance and repair of motorcycles and related parts and
#' accessories", and division 45 and section G themselves, which genuinely
#' straddle the split) or neither. Callers should fall through to other
#' evidence in that case.
#'
#' @param code_2019 character(1) or vector of PSIC 2019 codes.
#' @return Character vector the same length as `code_2019`: "trade",
#'   "repair", or NA_character_ (not in section G, not found, or the
#'   evidence is genuinely ambiguous).
psic_g_disposition <- function(code_2019) {
  codes <- as.character(code_2019)
  if (length(codes) == 0L) return(character(0))
  lookup <- .psic_record_lookup("2019")
  out <- rep(NA_character_, length(codes))

  for (i in seq_along(codes)) {
    code <- codes[i]
    if (is.na(code) || !nzchar(code)) next
    if (!code %in% names(lookup$label)) next

    section <- .psic_section_of_code(code, "2019")
    if (is.na(section) || section != "G") next

    division <- .psic_division_of_code(code)
    # Section letter "G" itself has no division: it straddles the split.
    if (is.na(division)) next

    if (division %in% c("46", "47")) {
      out[i] <- "trade"
      next
    }
    if (division != "45") next

    disp <- .psic_disposition_from_text(unname(lookup$label[[code]]))
    if (is.na(disp)) disp <- .psic_disposition_from_text(unname(lookup$description[[code]]))
    out[i] <- disp
  }
  out
}

#' Which 2026 section does a 2019 section-J code land in?
#'
#' The 2019 J -> 2026 J/K split falls exactly on a division boundary, so
#' this is decided on deterministic structural evidence, not wording:
#' 2019 divisions 58 (publishing), 59 (motion picture, video, television
#' production and sound recording) and 60 (programming and broadcasting)
#' stay in 2026 J; 2019 divisions 61 (telecommunications), 62 (computer
#' programming and consultancy) and 63 (information service activities)
#' become 2026 K.
#'
#' Section letter "J" itself returns NA: it straddles the split.
#'
#' @param code_2019 character(1) or vector of PSIC 2019 codes.
#' @return Character vector the same length as `code_2019`: "J", "K", or
#'   NA_character_ (not in section J, or not found).
psic_j_disposition <- function(code_2019) {
  codes <- as.character(code_2019)
  if (length(codes) == 0L) return(character(0))
  lookup <- .psic_record_lookup("2019")
  out <- rep(NA_character_, length(codes))

  for (i in seq_along(codes)) {
    code <- codes[i]
    if (is.na(code) || !nzchar(code)) next
    if (!code %in% names(lookup$label)) next

    section <- .psic_section_of_code(code, "2019")
    if (is.na(section) || section != "J") next

    division <- .psic_division_of_code(code)
    if (is.na(division)) next

    target <- psic_division_section(division, "2026")
    if (is.na(target) || !target %in% c("J", "K")) next
    out[i] <- target
  }
  out
}

# ---------------------------------------------------------------------------
# Small internal code helpers
# ---------------------------------------------------------------------------

#' Two-character division prefix of a PSIC code, or NA for a section letter.
#'
#' Codes below section level are strictly left-prefix nested within an
#' edition (division "45" -> group "451" -> class "4510" -> sub-class
#' "45101"), so the first two characters of any non-section code are its
#' division. Section codes are single letters and have no division.
.psic_division_of_code <- function(code) {
  code <- as.character(code)
  if (is.na(code) || nchar(code) < 2L) return(NA_character_)
  if (!grepl("^[0-9]{2}", code)) return(NA_character_)
  substr(code, 1L, 2L)
}

#' Section letter a PSIC code belongs to, in a given edition.
.psic_section_of_code <- function(code, version) {
  code <- as.character(code)
  if (is.na(code)) return(NA_character_)
  if (grepl("^[A-Z]$", code)) return(code)
  division <- .psic_division_of_code(code)
  if (is.na(division)) return(NA_character_)
  psic_division_section(division, version)
}
