# Evidence precedence for PSIC 2019 <-> PSIC Revision 5 (2026) correspondence.
#
# WHAT THIS FIXES
# ---------------
# The original build (scripts/build_psic_correspondence.R) searched for a
# target using, in order: the same code, the same 4-digit class family, then
# label similarity inside the same 3-digit group or 2-digit division. Every
# one of those steps is *positional* -- it assumes the digits stayed put --
# and the pipeline had no model at all of how PSA restructured the section
# layer in Revision 5. Three concrete consequences:
#
#   1. 2019 Division 45 ("Wholesale and retail trade AND repair of motor
#      vehicles and motorcycles") does not exist in Revision 5 at all. Trade
#      moved into Divisions 46/47 (Section G); repair moved into Division 95 /
#      Group 953 (Section T). With no 45* prefix to find, all 16 of the 2019
#      sub-classes under Division 45 fell through every branch and were
#      emitted as "discontinued" -- i.e. the artifact asserted that motor
#      vehicle repair and motor vehicle sales ceased to exist as classified
#      activities. They did not; they were relocated.
#   2. Where a label fallback *did* fire, it could put an activity in the
#      wrong economy entirely: the single best unrestricted label match for
#      2019 "45202 Repair of batteries for motor vehicles" is 2026 "27202
#      Manufacture of batteries for vehicles and bicycles" -- Section C,
#      manufacturing -- because "batteries", "for" and "vehicles" are shared
#      words. Fuzzy similarity was allowed to outrank known structural
#      movement.
#   3. Section letters are not comparable across editions. 2019 J split into
#      2026 J (Divisions 58-60) and 2026 K (61-63), and every section from
#      2019 K onward shifted one letter (K->L, L->M, ... U->V). So an
#      identical letter does not mean equivalence, and a changed letter does
#      not mean the activity changed. Nothing in the old pipeline knew that,
#      so deterministic continuity across a letter shift was indistinguishable
#      from a coincidental fuzzy match.
#
# THE PRECEDENCE MODEL
# --------------------
# Every candidate edge is stamped with an `evidence_tier`, numbered to match
# the specification's precedence list exactly (spec sections 3 and 14):
#
#   1  explicit official PSA correspondence record
#   2  deterministic structural relationship between editions
#   3  official UN ISIC Rev.4 <-> Rev.5 correspondence evidence
#   4  deterministic division/group/class/sub-class containment
#   5  exact/normalized code continuity where semantically valid
#   6  label/description similarity, as SUPPORTING evidence only
#   7  suggested algorithmic mapping, when nothing stronger exists
#
# Tier 1 is never produced. The source audit (docs/CORRESPONDENCE_SOURCES.md)
# found no PSA-published 2019<->Revision 5 crosswalk, and none has been
# incorporated into this application, so `provenance` here is only ever
# "derived" or "suggested" -- never "official".
#
# Candidates are returned sorted by tier ascending, so a caller that takes the
# first row always gets the strongest available evidence class, and fuzzy
# similarity can never displace a structural determination. Tier is assigned
# per *edge*, from the strongest evidence that actually supports that specific
# edge -- not from whichever search branch happened to find it.
#
# MULTIPLICITY IS PRESERVED
# -------------------------
# The resolver returns every legitimate target, not a single "best" one. 2019
# "45101 Sale of passenger motor vehicles" genuinely corresponds to both the
# 2026 wholesale target and the 2026 retail target; collapsing that to one row
# would be a statistical falsehood. Callers get 1->1, 1->N, N->1 (detected
# globally by the build script, which is the only layer that sees all sources
# at once), N->M, and zero-row ("discontinued") outcomes.
#
# PURITY
# ------
# `resolve_correspondence_candidates()` is a pure function of its arguments:
# it reads no files, touches no globals it was not handed, and holds no state.
# The structural facts it needs arrive through the `hooks` argument, so tests
# can inject fixtures and the build script can inject the real graph.

# ---------------------------------------------------------------------------
# Evidence tiers
# ---------------------------------------------------------------------------

#' Ordinal evidence tiers, numbered to match the specification's precedence
#' list. Lower is stronger. Tier 1 is defined but never emitted by this
#' codebase (see file header).
CORRESPONDENCE_EVIDENCE_TIERS <- c(
  official_psa_record     = 1L,
  structural_relationship = 2L,
  isic_correspondence     = 3L,
  hierarchy_containment   = 4L,
  code_continuity         = 5L,
  label_similarity        = 6L,
  suggested_algorithmic   = 7L
)

#' Human-readable name for an evidence tier number.
correspondence_evidence_tier_name <- function(tier) {
  nm <- names(CORRESPONDENCE_EVIDENCE_TIERS)[match(tier, CORRESPONDENCE_EVIDENCE_TIERS)]
  ifelse(is.na(nm), "unknown", nm)
}

# ---------------------------------------------------------------------------
# Structural hooks
#
# The authoritative implementations live in R/correspondence/structural_graph.R
# (owned by a separate workstream). This file must remain sourceable and
# testable on its own, so every hook is resolved through `exists()` and falls
# back to a minimal local table when the graph file is absent.
#
# The fallbacks below are NOT an independent second opinion: they encode only
# what the two normalized local datasets themselves say (2026 divisions carry
# an explicit `parent_code` section; 2019 divisions do not, so the 2019
# division->section assignment is the standard PSIC 2019 structure that the
# published section labels in data confirm). When structural_graph.R is
# present its definitions win, unconditionally.
# ---------------------------------------------------------------------------

.precedence_expand_sections <- function(spec) {
  out <- character(0)
  for (sec in names(spec)) {
    divs <- spec[[sec]]
    out[divs] <- sec
  }
  out
}

.precedence_pad2 <- function(x) formatC(x, width = 2, flag = "0")

.PRECEDENCE_DIVISION_SECTION_2019 <- .precedence_expand_sections(list(
  A = .precedence_pad2(1:3),
  B = .precedence_pad2(5:9),
  C = .precedence_pad2(10:33),
  D = "35",
  E = .precedence_pad2(36:39),
  F = .precedence_pad2(41:43),
  G = .precedence_pad2(45:47),
  H = .precedence_pad2(49:53),
  I = .precedence_pad2(55:56),
  J = .precedence_pad2(58:63),
  K = .precedence_pad2(64:66),
  L = "68",
  M = .precedence_pad2(69:75),
  N = .precedence_pad2(77:82),
  O = "84",
  P = "85",
  Q = .precedence_pad2(86:88),
  R = .precedence_pad2(90:93),
  S = .precedence_pad2(94:96),
  T = .precedence_pad2(97:98),
  U = "99"
))

.PRECEDENCE_DIVISION_SECTION_2026 <- .precedence_expand_sections(list(
  A = .precedence_pad2(1:3),
  B = .precedence_pad2(5:9),
  C = .precedence_pad2(10:33),
  D = "35",
  E = .precedence_pad2(36:39),
  F = .precedence_pad2(41:44),
  G = .precedence_pad2(46:47),
  H = .precedence_pad2(49:53),
  I = .precedence_pad2(55:56),
  J = .precedence_pad2(58:60),
  K = .precedence_pad2(61:63),
  L = .precedence_pad2(64:66),
  M = "68",
  N = .precedence_pad2(69:75),
  O = .precedence_pad2(77:82),
  P = "84",
  Q = "85",
  R = .precedence_pad2(86:88),
  S = .precedence_pad2(90:93),
  T = .precedence_pad2(94:96),
  U = .precedence_pad2(97:98),
  V = "99"
))

# 2019 section -> 2026 section(s). G and J are the two genuine splits; from
# 2019 K onward every letter shifts by one because Revision 5 inserted the new
# Section K (Telecommunications / IT) after J.
.PRECEDENCE_SECTION_GRAPH_2019_2026 <- list(
  A = "A", B = "B", C = "C", D = "D", E = "E", F = "F",
  G = c("G", "T"),
  H = "H", I = "I",
  J = c("J", "K"),
  K = "L", L = "M", M = "N", N = "O", O = "P", P = "Q",
  Q = "R", R = "S", S = "T", T = "U", U = "V"
)

.precedence_fallback_division_section <- function(division_code, version) {
  if (length(division_code) != 1L || is.na(division_code)) return(NA_character_)
  tbl <- switch(as.character(version),
    "2019" = .PRECEDENCE_DIVISION_SECTION_2019,
    "2026" = .PRECEDENCE_DIVISION_SECTION_2026,
    NULL
  )
  if (is.null(tbl) || !division_code %in% names(tbl)) return(NA_character_)
  unname(tbl[[division_code]])
}

.precedence_fallback_section_targets <- function(section, from_version = "2019",
                                                  to_version = "2026") {
  if (length(section) != 1L || is.na(section)) return(character(0))
  if (!identical(as.character(from_version), "2019") ||
      !identical(as.character(to_version), "2026")) {
    return(character(0))
  }
  out <- .PRECEDENCE_SECTION_GRAPH_2019_2026[[section]]
  if (is.null(out)) character(0) else out
}

.precedence_fallback_is_repair_migration <- function(code_2026) {
  if (length(code_2026) != 1L || is.na(code_2026)) return(FALSE)
  # Revision 5 Division 95 is the repair-and-maintenance destination; Group
  # 953 within it is specifically motor vehicles and motorcycles.
  startsWith(code_2026, "95")
}

.precedence_fallback_g_disposition <- function(code_2019) {
  if (length(code_2019) != 1L || is.na(code_2019)) return(NA_character_)
  # Divisions 46/47 were already pure trade in 2019 and stayed trade.
  if (startsWith(code_2019, "46") || startsWith(code_2019, "47")) return("trade")
  if (!startsWith(code_2019, "45")) return(NA_character_)
  # Within Division 45: Group 452 is maintenance/repair of motor vehicles;
  # Groups 451 and 453 are sale of vehicles / sale of parts. Group 454 mixes
  # sale AND repair of motorcycles in one group, so it is only resolvable at
  # sub-class level -- 45402 is the repair member, 45401/45403 are sale.
  if (startsWith(code_2019, "452")) return("repair")
  if (startsWith(code_2019, "451") || startsWith(code_2019, "453")) return("trade")
  if (identical(code_2019, "45402")) return("repair")
  if (code_2019 %in% c("45401", "45403")) return("trade")
  # Division 45 itself, Group 454, Class 4540: genuinely mixed. Returning NA
  # is the correct answer -- the caller must fall through to weaker evidence
  # rather than force the whole family into one destination.
  NA_character_
}

.precedence_fallback_j_disposition <- function(code_2019) {
  if (length(code_2019) != 1L || is.na(code_2019)) return(NA_character_)
  div <- substr(code_2019, 1, 2)
  if (div %in% c("58", "59", "60")) return("J")
  if (div %in% c("61", "62", "63")) return("K")
  NA_character_
}

#' Assemble the structural-fact hooks the resolver needs.
#'
#' Each entry prefers the authoritative implementation from
#' R/correspondence/structural_graph.R when that file has been sourced, and
#' otherwise uses the local fallback documented above. Returning them as a
#' plain list keeps `resolve_correspondence_candidates()` a pure function of
#' its arguments and lets tests inject fixtures.
#'
#' @return list of functions: `division_section(division_code, version)`,
#'   `section_targets(section, from_version, to_version)`,
#'   `is_repair_migration(code_2026)`, `g_disposition(code_2019)`,
#'   `j_disposition(code_2019)`.
correspondence_structural_hooks <- function() {
  # NOTE ON THE NAME: this local resolver was originally called `use()`.
  # That collided with renv's dependency scanner, which treats `use(...)`
  # as a package-declaring call (alongside library/require/requireNamespace
  # and renv::use) and harvests its first string argument as a package
  # name. The five structural helper names were therefore reported by
  # `renv::status()` as "used in this project, but not installed" -- five
  # phantom CRAN packages that do not exist. They are ordinary
  # project-local functions from R/correspondence/structural_graph.R.
  # Renaming this one local closure fixes the false positives; the helper
  # names themselves are part of the structural contract and are unchanged.
  resolve_correspondence_helper <- function(name, fallback) {
    if (exists(name, mode = "function")) get(name, mode = "function") else fallback
  }
  list(
    division_section    = resolve_correspondence_helper("psic_division_section", .precedence_fallback_division_section),
    section_targets     = resolve_correspondence_helper("psic_section_targets", .precedence_fallback_section_targets),
    is_repair_migration = resolve_correspondence_helper("psic_is_repair_migration", .precedence_fallback_is_repair_migration),
    g_disposition       = resolve_correspondence_helper("psic_g_disposition", .precedence_fallback_g_disposition),
    j_disposition       = resolve_correspondence_helper("psic_j_disposition", .precedence_fallback_j_disposition)
  )
}

# ---------------------------------------------------------------------------
# Small helpers
# ---------------------------------------------------------------------------

#' Section letter for a PSIC code at any level.
#'
#' A section-level code IS its own letter; everything below section is located
#' by its 2-digit division prefix. Returns NA when the version's division map
#' does not recognise the prefix (a legitimate "I do not know", which the
#' resolver treats as "fall through to weaker evidence", never as "no match").
correspondence_code_section <- function(code, version, hooks = correspondence_structural_hooks()) {
  if (length(code) != 1L || is.na(code) || !nzchar(code)) return(NA_character_)
  if (grepl("^[A-Za-z]$", code)) return(toupper(code))
  if (nchar(code) < 2L) return(NA_character_)
  sec <- hooks$division_section(substr(code, 1, 2), version)
  if (length(sec) != 1L) return(NA_character_)
  as.character(sec)
}

.precedence_chr <- function(x, default = NA_character_) {
  if (is.null(x) || length(x) == 0L) return(default)
  as.character(x[[1]])
}

.precedence_field <- function(row, name, default = NA_character_) {
  if (is.null(row)) return(default)
  if (!name %in% names(row)) return(default)
  .precedence_chr(row[[name]], default)
}

#' Derive the canonical level name from PSIC code width, used only when a
#' caller supplies rows without an explicit `level`.
.precedence_level_from_code <- function(code) {
  if (is.na(code)) return(NA_character_)
  switch(as.character(nchar(code)),
    "1" = "section",
    "2" = "division",
    "3" = "group",
    "4" = "class",
    "5" = "sub-class",
    NA_character_
  )
}

# ---------------------------------------------------------------------------
# The resolver
# ---------------------------------------------------------------------------

#' Rank every legitimate 2026 counterpart for one 2019 PSIC row, by evidence
#' precedence.
#'
#' Pure function: no file access, no global mutation. All structural facts
#' arrive via `hooks`; all ISIC facts arrive via `isic_class_targets` /
#' `isic_supported`, which the build script precomputes once.
#'
#' @param source_row a one-row data frame or a named list describing the 2019
#'   entry. Required: `code`, `label`. Optional: `level`, `description`.
#' @param targets a data frame of candidate 2026 entries at the level the
#'   caller wants matched. Required: `code`, `label`. Optional: `level`,
#'   `description`, and `section` (the 2026 section letter -- supplied
#'   directly it is used as-is, otherwise it is derived through `hooks`).
#' @param from_version,to_version character(1) edition labels.
#' @param hooks structural-fact hooks, see `correspondence_structural_hooks()`.
#' @param isic_class_targets character vector of ISIC Rev.5 class codes the
#'   official UN table maps this source's class to, from
#'   `isic_bridge_class_targets()`. Empty vector = no ISIC evidence.
#' @param isic_supported optional `function(source_code, target_code)`
#'   returning logical(1) -- the both-sides-conformance-gated corroboration
#'   from `isic_bridge_supported()`. NULL = unavailable.
#' @param max_candidates integer(1), cap on returned rows. The cap exists to
#'   stop a weak label fan-out exploding; it is applied AFTER precedence
#'   ordering, so it can only ever discard the weakest candidates.
#'
#' @return a tibble, ordered strongest-evidence-first, with columns:
#'   \describe{
#'     \item{source_code, source_level, source_label}{echoed from `source_row`}
#'     \item{target_code, target_level, target_label}{the matched 2026 entry}
#'     \item{evidence_tier}{integer 2..7, the precedence tier justifying this
#'       edge (1 is never emitted: no official PSA crosswalk exists)}
#'     \item{evidence_class}{tier name, e.g. "structural_relationship"}
#'     \item{structural_rule}{machine key for the structural movement applied,
#'       or NA when none applied}
#'     \item{relation_evidence}{short human-readable justification}
#'     \item{relation_hint}{suggested relation_type: "unchanged", "renamed",
#'       "reclassified", "split", "complex" or "possible". A hint only -- the
#'       build script owns "merged" (needs a global view) and "discontinued"
#'       (zero rows returned) and may override.}
#'     \item{provenance}{"derived" or "suggested" -- never "official"}
#'     \item{confidence}{"high", "moderate" or "low"}
#'     \item{confidence_score}{double, from `score_correspondence()`}
#'     \item{method}{machine-readable search method key}
#'     \item{hierarchy}{"same_class"/"same_group"/"same_division"/"none"}
#'     \item{label_similarity}{double, normalized-token Jaccard}
#'     \item{exact_code}{logical}
#'   }
#'   Zero rows means "no defensible target": the caller should emit a
#'   "discontinued" row.
resolve_correspondence_candidates <- function(source_row,
                                               targets,
                                               from_version = "2019",
                                               to_version = "2026",
                                               hooks = correspondence_structural_hooks(),
                                               isic_class_targets = character(0),
                                               isic_supported = NULL,
                                               max_candidates = 5L) {
  src_code  <- .precedence_field(source_row, "code")
  src_label <- .precedence_field(source_row, "label")
  src_level <- .precedence_field(source_row, "level", .precedence_level_from_code(src_code))
  src_desc  <- .precedence_field(source_row, "description")

  if (is.na(src_code) || is.null(targets) || nrow(targets) == 0L) {
    return(.precedence_empty_result())
  }

  t_code  <- as.character(targets$code)
  t_label <- as.character(targets$label)
  t_level <- if ("level" %in% names(targets)) as.character(targets$level) else
    vapply(t_code, .precedence_level_from_code, character(1), USE.NAMES = FALSE)
  t_desc  <- if ("description" %in% names(targets)) as.character(targets$description) else
    rep(NA_character_, length(t_code))
  t_section <- if ("section" %in% names(targets)) {
    as.character(targets$section)
  } else {
    vapply(t_code, correspondence_code_section, character(1),
           version = to_version, hooks = hooks, USE.NAMES = FALSE)
  }

  # -- Step 1: deterministic structural restriction of the target space ------
  restriction <- .precedence_structural_restriction(
    src_code = src_code,
    from_version = from_version, to_version = to_version,
    t_code = t_code, t_section = t_section,
    hooks = hooks
  )
  allowed <- restriction$allowed
  # A structural rule that eliminates every candidate is a rule that does not
  # apply to this data. Spec section 4: stop that mapping path, do not force
  # the edge -- fall back to the unrestricted space at a weaker tier.
  if (length(allowed) == 0L) {
    allowed <- seq_along(t_code)
    restriction <- list(allowed = allowed, rule = NA_character_,
                        redistribution = FALSE, rationale = NA_character_)
  }

  # -- Step 2: candidate generation inside the allowed space -----------------
  gen <- .precedence_generate_candidates(
    src_code = src_code, src_label = src_label,
    t_code = t_code, t_label = t_label,
    allowed = allowed,
    structurally_restricted = !is.na(restriction$rule),
    isic_class_targets = isic_class_targets
  )
  if (length(gen$idx) == 0L) return(.precedence_empty_result())

  # -- Step 3: tier, score and justify each surviving edge -------------------
  rows <- lapply(seq_along(gen$idx), function(k) {
    i <- gen$idx[k]
    exact <- identical(t_code[i], src_code)
    hier <- if (exact) "same_class" else hierarchy_relation(src_code, t_code[i])
    sim <- jaccard_token_similarity(src_label, t_label[i])
    near <- is_near_identical_title(src_label, t_label[i])
    isic_ok <- isTRUE(.precedence_isic_ok(isic_supported, src_code, t_code[i]))
    isic_gen <- length(isic_class_targets) > 0L &&
      substr(t_code[i], 1, 4) %in% isic_class_targets

    tier <- .precedence_tier(
      rule = restriction$rule, redistribution = restriction$redistribution,
      exact = exact, hier = hier, isic_ok = isic_ok, isic_gen = isic_gen,
      near = near, sim = sim
    )

    sc <- score_correspondence(
      exact_code = exact,
      source_code = src_code, target_code = t_code[i],
      source_label = src_label, target_label = t_label[i],
      source_description = src_desc, target_description = t_desc[i],
      isic_bridge_supported = isic_ok,
      structural_supported = tier == CORRESPONDENCE_EVIDENCE_TIERS[["structural_relationship"]]
    )

    list(
      source_code = src_code, source_level = src_level, source_label = src_label,
      target_code = t_code[i], target_level = t_level[i], target_label = t_label[i],
      evidence_tier = tier,
      evidence_class = correspondence_evidence_tier_name(tier),
      structural_rule = restriction$rule,
      relation_evidence = .precedence_evidence_text(
        tier = tier, rationale = restriction$rationale, exact = exact,
        src_code = src_code, target_code = t_code[i], hier = hier,
        isic_ok = isic_ok, isic_gen = isic_gen, near = near, sim = sim,
        method = gen$method
      ),
      provenance = .precedence_provenance(tier),
      confidence = .precedence_confidence(tier, exact, hier, near),
      confidence_score = as.double(sc$score),
      method = gen$method,
      hierarchy = hier,
      label_similarity = as.double(sim),
      exact_code = exact
    )
  })

  out <- .precedence_bind(rows)

  # -- Step 4: precedence ordering, then the cap -----------------------------
  ord <- order(out$evidence_tier, -out$confidence_score, -out$label_similarity, out$target_code)
  out <- out[ord, , drop = FALSE]
  if (nrow(out) > max_candidates) out <- out[seq_len(max_candidates), , drop = FALSE]

  # -- Step 5: relation hints, computed over the surviving set ---------------
  out$relation_hint <- .precedence_relation_hints(out, restriction$redistribution)
  out <- out[, .PRECEDENCE_RESULT_COLUMNS, drop = FALSE]
  rownames(out) <- NULL
  tibble::as_tibble(out)
}

.PRECEDENCE_RESULT_COLUMNS <- c(
  "source_code", "source_level", "source_label",
  "target_code", "target_level", "target_label",
  "evidence_tier", "evidence_class", "structural_rule",
  "relation_evidence", "relation_hint",
  "provenance", "confidence", "confidence_score",
  "method", "hierarchy", "label_similarity", "exact_code"
)

.precedence_empty_result <- function() {
  tibble::tibble(
    source_code = character(0), source_level = character(0), source_label = character(0),
    target_code = character(0), target_level = character(0), target_label = character(0),
    evidence_tier = integer(0), evidence_class = character(0), structural_rule = character(0),
    relation_evidence = character(0), relation_hint = character(0),
    provenance = character(0), confidence = character(0), confidence_score = double(0),
    method = character(0), hierarchy = character(0),
    label_similarity = double(0), exact_code = logical(0)
  )
}

.precedence_bind <- function(rows) {
  cols <- names(rows[[1]])
  out <- lapply(cols, function(cl) {
    v <- lapply(rows, function(r) r[[cl]])
    unlist(v, use.names = FALSE)
  })
  names(out) <- cols
  as.data.frame(out, stringsAsFactors = FALSE)
}

.precedence_isic_ok <- function(isic_supported, src_code, target_code) {
  if (is.null(isic_supported) || !is.function(isic_supported)) return(FALSE)
  res <- tryCatch(isic_supported(src_code, target_code), error = function(e) FALSE)
  isTRUE(res)
}

# ---------------------------------------------------------------------------
# Step 1 detail: structural restriction
# ---------------------------------------------------------------------------

#' Narrow the 2026 target space using deterministic between-edition structure.
#'
#' Three distinct rules, in the order they are checked:
#'
#'  * **Section G trade/repair redistribution.** 2019 Section G bundled trade
#'    with repair of motor vehicles and motorcycles. Revision 5 Section G is
#'    trade only (Divisions 46-47); repair migrated to Section T, Division 95,
#'    Group 953. A source classified "repair" is restricted to the repair
#'    destination, "trade" to the trade destination. A source the disposition
#'    hook cannot classify (Division 45 as a whole, Group 454, Class 4540 --
#'    all genuinely mixed) returns NA and is deliberately NOT forced either
#'    way: it falls through to weaker evidence. This is the specific defect
#'    guard the spec calls out -- do not send every former Division 45
#'    descendant to T.
#'  * **2019 J -> 2026 J/K split.** Descendants in the 58-60 concept space go
#'    to 2026 J, descendants in 61-63 to 2026 K.
#'  * **Section-letter mapping.** Everything else uses the section graph. Note
#'    this covers both unchanged letters (A->A) and shifted letters (K->L),
#'    and the two cases are treated identically on purpose: the letter itself
#'    carries no information, only the graph edge does.
#'
#' @return list(allowed = integer vector of row indices into `t_code`,
#'   rule = character(1) key or NA, redistribution = logical(1) TRUE when the
#'   rule moved the activity to a different section than a naive same-letter
#'   reading would give, rationale = character(1) or NA).
.precedence_structural_restriction <- function(src_code, from_version, to_version,
                                               t_code, t_section, hooks) {
  none <- list(allowed = seq_along(t_code), rule = NA_character_,
               redistribution = FALSE, rationale = NA_character_)

  src_section <- correspondence_code_section(src_code, from_version, hooks)
  if (is.na(src_section)) return(none)

  if (identical(src_section, "G")) {
    disp <- .precedence_call_chr(hooks$g_disposition, src_code)
    if (identical(disp, "repair")) {
      keep <- which(vapply(t_code, function(cd) isTRUE(hooks$is_repair_migration(cd)),
                            logical(1), USE.NAMES = FALSE))
      # Prefer Group 953 (motor vehicles and motorcycles specifically) when it
      # is represented, rather than all of Division 95 (which also holds
      # computer, household-goods and intermediation repair).
      in953 <- keep[startsWith(t_code[keep], "953")]
      if (length(in953) > 0L) keep <- in953
      return(list(
        allowed = keep, rule = "g_repair_migration_to_2026_section_t",
        redistribution = TRUE,
        rationale = paste(
          "2019 Section G bundled trade with repair of motor vehicles and",
          "motorcycles; in Revision 5 repair and maintenance migrated to",
          "Section T, Division 95, Group 953. This source is a repair",
          "activity, so its counterpart must lie in that destination."
        )
      ))
    }
    if (identical(disp, "trade")) {
      keep <- which(!is.na(t_section) & t_section == "G")
      return(list(
        allowed = keep, rule = "g_trade_retained_in_2026_section_g",
        redistribution = TRUE,
        rationale = paste(
          "Revision 5 Section G is trade only (Divisions 46-47). This source",
          "is a sales/trade activity, so its counterpart must lie in the",
          "Revision 5 trade structure, not in the migrated repair structure."
        )
      ))
    }
    return(none)  # genuinely mixed -- do not force a destination
  }

  if (identical(src_section, "J")) {
    disp <- .precedence_call_chr(hooks$j_disposition, src_code)
    if (!is.na(disp) && nzchar(disp)) {
      keep <- which(!is.na(t_section) & t_section == disp)
      return(list(
        allowed = keep,
        rule = sprintf("j_split_to_2026_section_%s", tolower(disp)),
        redistribution = TRUE,
        rationale = sprintf(paste(
          "2019 Section J split in Revision 5 into Section J (Divisions",
          "58-60) and Section K (Divisions 61-63). This source belongs to the",
          "%s concept space, so its counterpart lies in Revision 5 Section %s."
        ), if (identical(disp, "J")) "58-60" else "61-63", disp)
      ))
    }
    return(none)
  }

  tgt_sections <- tryCatch(
    as.character(hooks$section_targets(src_section, from_version, to_version)),
    error = function(e) character(0)
  )
  tgt_sections <- tgt_sections[!is.na(tgt_sections)]
  if (length(tgt_sections) == 0L) return(none)

  keep <- which(!is.na(t_section) & t_section %in% tgt_sections)
  shifted <- !identical(sort(unique(tgt_sections)), src_section)
  list(
    allowed = keep,
    rule = if (shifted) {
      sprintf("section_letter_shift_%s_to_%s", src_section, paste(tgt_sections, collapse = "+"))
    } else {
      sprintf("section_continuity_%s", src_section)
    },
    redistribution = FALSE,
    rationale = if (shifted) {
      sprintf(paste(
        "Revision 5 renumbered the section layer: %s section %s corresponds to",
        "%s section %s. The letter changed but the activity did not, so this",
        "is deterministic structural continuity, not a coincidental match."
      ), from_version, src_section, to_version, paste(tgt_sections, collapse = "/"))
    } else {
      sprintf(paste(
        "%s section %s corresponds to %s section %s. Identical letters were",
        "verified against the section graph, not assumed."
      ), from_version, src_section, to_version, paste(tgt_sections, collapse = "/"))
    }
  )
}

.precedence_call_chr <- function(f, x) {
  if (!is.function(f)) return(NA_character_)
  res <- tryCatch(f(x), error = function(e) NA_character_)
  if (length(res) != 1L) return(NA_character_)
  as.character(res)
}

# ---------------------------------------------------------------------------
# Step 2 detail: candidate generation inside the allowed space
# ---------------------------------------------------------------------------

#' Find candidate targets, strongest search method first, inside the already
#' structurally-restricted index set.
#'
#' @return list(idx = integer indices into `t_code`, method = character(1)).
.precedence_generate_candidates <- function(src_code, src_label, t_code, t_label,
                                            allowed, structurally_restricted,
                                            isic_class_targets) {
  empty <- list(idx = integer(0), method = NA_character_)
  if (length(allowed) == 0L) return(empty)

  # (a) exact code continuity
  hit <- allowed[t_code[allowed] == src_code]
  if (length(hit) > 0L) return(list(idx = hit, method = "exact_code_match"))

  # (b) same 4-digit class family
  if (nchar(src_code) >= 4L) {
    hit <- allowed[substr(t_code[allowed], 1, 4) == substr(src_code, 1, 4)]
    if (length(hit) > 0L) return(list(idx = hit, method = "class_prefix_continuity"))
  }

  # (c) official UN ISIC Rev.4 -> Rev.5 class targets. This is the branch the
  #     old pipeline could never reach, because it only ever corroborated
  #     candidates positional search had already produced.
  if (length(isic_class_targets) > 0L && nchar(src_code) >= 4L) {
    hit <- allowed[substr(t_code[allowed], 1, 4) %in% isic_class_targets]
    hit <- .precedence_label_filter(src_label, t_label, hit,
                                     structurally_restricted, window = FALSE)
    if (length(hit) > 0L) return(list(idx = hit, method = "isic_rev4_rev5_class_bridge"))
  }

  # (d) same 3-digit group family
  if (nchar(src_code) >= 3L) {
    hit <- allowed[substr(t_code[allowed], 1, 3) == substr(src_code, 1, 3)]
    if (length(hit) > 0L) return(list(idx = hit, method = "group_prefix_continuity"))
  }

  # (e) label similarity, inside whatever space is left
  hit <- .precedence_label_filter(src_label, t_label, allowed,
                                   structurally_restricted, window = TRUE)
  if (length(hit) > 0L) {
    return(list(idx = hit, method = if (structurally_restricted) {
      "structural_scope_label_similarity"
    } else {
      "unrestricted_label_similarity"
    }))
  }

  empty
}

#' Keep candidates whose label clears the applicable similarity floor, ordered
#' best-first, optionally trimmed to a near-tie window below the best.
.precedence_label_filter <- function(src_label, t_label, idx, structurally_restricted,
                                     window = TRUE) {
  if (length(idx) == 0L) return(integer(0))
  floor_val <- if (structurally_restricted) {
    CORRESPONDENCE_SIMILARITY_THRESHOLDS$structural_candidate_minimum
  } else {
    CORRESPONDENCE_SIMILARITY_THRESHOLDS$candidate_minimum
  }
  sims <- vapply(t_label[idx], function(l) jaccard_token_similarity(src_label, l),
                  numeric(1), USE.NAMES = FALSE)
  keep <- sims >= floor_val
  if (!any(keep)) return(integer(0))
  idx <- idx[keep]
  sims <- sims[keep]
  ord <- order(-sims)
  idx <- idx[ord]
  sims <- sims[ord]
  if (isTRUE(window)) {
    idx <- idx[sims >= (sims[1] - CORRESPONDENCE_SIMILARITY_THRESHOLDS$candidate_window)]
  }
  idx
}

# ---------------------------------------------------------------------------
# Step 3 detail: tier, provenance, confidence, justification
# ---------------------------------------------------------------------------

#' Assign the precedence tier justifying one specific edge.
#'
#' Tier 2 is claimed only when structural evidence genuinely determined the
#' destination:
#'   * a redistribution rule (Section G trade/repair, 2019 J -> 2026 J/K) --
#'     these move the activity to a section a naive reading would never pick,
#'     so the rule itself is the evidence; or
#'   * a section mapping (shifted or not) that is *corroborated* by code
#'     continuity or containment. A section edge on its own is not enough to
#'     claim tier 2 for a specific sub-class, because a section contains
#'     hundreds of them.
#'
#' Label similarity can therefore never reach tier 2, and never displaces a
#' structural determination.
.precedence_tier <- function(rule, redistribution, exact, hier, isic_ok, isic_gen,
                             near, sim) {
  tiers <- CORRESPONDENCE_EVIDENCE_TIERS
  has_rule <- !is.na(rule)
  containment <- hier %in% c("same_class", "same_group")

  if (has_rule && (isTRUE(redistribution) || isTRUE(exact) || containment)) {
    return(tiers[["structural_relationship"]])
  }
  if (isTRUE(isic_ok) || isTRUE(isic_gen)) return(tiers[["isic_correspondence"]])
  if (containment) return(tiers[["hierarchy_containment"]])
  if (isTRUE(exact)) return(tiers[["code_continuity"]])
  if (isTRUE(near)) return(tiers[["label_similarity"]])
  tiers[["suggested_algorithmic"]]
}

#' Provenance from tier.
#'
#' Tier 1 ("official") is unreachable: no PSA-published 2019<->Revision 5
#' crosswalk has been incorporated into this application, so this function
#' cannot return "official" for any input. Tiers 2-5 rest on authoritative
#' structure (published edition structures, the official UN ISIC table,
#' deterministic containment/continuity) and are therefore "derived". Tier 6
#' is label evidence and tier 7 is a pure algorithmic guess; both are
#' "suggested", which the schema and the UI treat as never overriding a
#' derived mapping.
.precedence_provenance <- function(tier) {
  if (tier <= CORRESPONDENCE_EVIDENCE_TIERS[["code_continuity"]]) "derived" else "suggested"
}

#' Qualitative confidence from tier plus the corroborating signals present.
#'
#' Deliberately NOT `bucket_confidence(score)`: the whole point of this repair
#' is that a deterministic structural continuity across a section-letter shift
#' must not be reported as a low-confidence fuzzy match, and conversely that a
#' high label score inside a weak tier must not be dressed up as certainty.
#' `confidence_score` is still carried alongside for transparency.
.precedence_confidence <- function(tier, exact, hier, near) {
  tiers <- CORRESPONDENCE_EVIDENCE_TIERS
  if (tier == tiers[["structural_relationship"]]) {
    # Section destination is deterministic. "high" additionally requires that
    # the *specific* entry is pinned down by code continuity or an unchanged
    # title; otherwise the section is certain but the member is inferred.
    return(if (isTRUE(exact) || isTRUE(near) || identical(hier, "same_class")) "high" else "moderate")
  }
  if (tier == tiers[["isic_correspondence"]]) {
    return(if (identical(hier, "same_class") || isTRUE(near)) "high" else "moderate")
  }
  if (tier == tiers[["hierarchy_containment"]]) {
    return(if (identical(hier, "same_class")) "high" else "moderate")
  }
  if (tier == tiers[["code_continuity"]]) return("high")
  if (tier == tiers[["label_similarity"]]) return("moderate")
  "low"
}

.precedence_evidence_text <- function(tier, rationale, exact, src_code, target_code,
                                      hier, isic_ok, isic_gen, near, sim, method) {
  parts <- character(0)
  if (tier == CORRESPONDENCE_EVIDENCE_TIERS[["structural_relationship"]] && !is.na(rationale)) {
    parts <- c(parts, rationale)
  }
  parts <- c(parts, if (isTRUE(exact)) {
    sprintf("Code '%s' is unchanged across editions.", src_code)
  } else {
    sprintf("Code '%s' -> '%s' (%s).", src_code, target_code, gsub("_", " ", hier))
  })
  if (isTRUE(isic_ok)) {
    parts <- c(parts, "Corroborated by the official UN ISIC Rev.4->Rev.5 class correspondence.")
  } else if (isTRUE(isic_gen)) {
    parts <- c(parts, "Target class named by the official UN ISIC Rev.4->Rev.5 correspondence for this source class.")
  }
  parts <- c(parts, sprintf(
    "Label evidence %s (normalized-token similarity %.2f)%s.",
    if (isTRUE(near)) "near-identical" else "supporting only", sim,
    if (tier >= CORRESPONDENCE_EVIDENCE_TIERS[["label_similarity"]]) {
      "; no stronger structural or positional evidence was available"
    } else {
      ""
    }
  ))
  parts <- c(parts, sprintf("Search method: %s.", method))
  paste(parts, collapse = " ")
}

# ---------------------------------------------------------------------------
# Step 5 detail: relation hints
# ---------------------------------------------------------------------------

#' Suggest a `relation_type` for each surviving edge.
#'
#' The build script keeps final authority: it alone sees every source at once,
#' so it alone can detect "merged" (N->1), and it alone emits "discontinued"
#' (which this function expresses by returning zero rows). Everything else is
#' decidable from the candidate set for a single source.
.precedence_relation_hints <- function(out, redistribution) {
  n <- nrow(out)
  vapply(seq_len(n), function(i) {
    tier <- out$evidence_tier[i]
    if (n > 1L) {
      return(if (tier <= CORRESPONDENCE_EVIDENCE_TIERS[["code_continuity"]]) "split" else "complex")
    }
    if (isTRUE(out$exact_code[i])) {
      return(if (out$label_similarity[i] >= CORRESPONDENCE_SIMILARITY_THRESHOLDS$near_identical_title) {
        "unchanged"
      } else {
        "renamed"
      })
    }
    if (isTRUE(redistribution)) return("reclassified")
    if (tier <= CORRESPONDENCE_EVIDENCE_TIERS[["code_continuity"]]) "renamed" else "possible"
  }, character(1))
}
