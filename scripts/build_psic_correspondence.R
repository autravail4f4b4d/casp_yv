# Build-time pipeline: PSIC 2019 <-> PSIC Revision 5 (2026) correspondence.
#
# Produces data/psic_2019_to_2026_correspondence.rds (the canonical
# correspondence tibble, see R/correspondence/schema.R) and
# data/psic_2019_to_2026_correspondence_metadata.rds (a build-metadata
# sidecar, mirroring data/psic_2026_metadata.rds's pattern).
#
# This is a build-time-only script. The runtime service layer
# (R/correspondence/service.R) only ever readRDS()s the artifacts this
# script produces -- there is no PSA or UN network dependency anywhere in
# the request path, matching the same offline-runtime rule as PSIC
# Revision 5 itself (docs/DATA_SOURCES.md).
#
# Source audit: docs/CORRESPONDENCE_SOURCES.md documents that no official
# PSA PSIC 2019<->Revision 5 crosswalk exists as of this build (Revision 5
# was only approved 21 May 2026 / released 5 August 2026). Every mapping
# produced here therefore carries provenance "derived" or "suggested",
# never "official" -- see the guard test in
# tests/testthat/test-correspondence-build.R.
#
# ALGORITHM (see R/correspondence/scoring.R for the scoring model this
# leans on, and R/correspondence/isic_bridge.R for the optional UN ISIC
# corroboration signal)
# -----------------------------------------------------------------------
# Primary coverage is at the sub-class level (the finest, most useful
# lookup granularity) and is EXHAUSTIVE: every PSIC 2019 sub-class code
# gets at least one output row, and every PSIC 2026 sub-class code with no
# 2019 counterpart gets a "new" row. For each 2019 sub-class code, in
# priority order:
#
#   1. Exact code match in 2026            -> bucket "exact_or_prefix"
#   2. No exact match, but >=1 2026        -> bucket "exact_or_prefix"
#      sub-class shares the same 4-digit      (class-prefix continuity is
#      class-code family                      strong deterministic
#                                              hierarchy evidence)
#   3. No class-prefix candidate; fall      -> bucket "fallback"
#      back to label-similarity search         (label-driven, weaker
#      restricted first to the same 3-digit     evidence -> "suggested")
#      group family, then the same 2-digit
#      division family if the group yields
#      nothing above the similarity floor
#   4. Nothing clears the similarity floor  -> "discontinued", no target
#
# Within bucket "exact_or_prefix": exactly one candidate -> "unchanged"
# (near-identical title) or "renamed" (title changed); more than one
# candidate -> "split" (one row per candidate). A post-process pass then
# looks for 2026 codes that are the *sole* "exact_or_prefix" candidate for
# more than one distinct 2019 source code, and relabels those specific rows
# "merged" (kept scoped to hierarchy-derived evidence only, not to
# label-similarity "fallback" guesses -- see file-level comment further
# down at the merge-detection step for why).
#
# Within bucket "fallback": exactly one surviving candidate -> "possible";
# more than one comparable candidate -> "complex". Provenance is always
# "suggested" for this bucket (pure/mostly label-similarity-driven, per
# spec section 16).
#
# Higher levels (division/group/class; section is skipped -- see
# docs/CORRESPONDENCE_SOURCES.md for why section-level pairing was judged
# not worth the added assumption) get a lightweight supplementary pass:
# only clean exact-code matches are emitted ("unchanged"/"renamed"); no
# split/merge/discontinued/new bookkeeping at those levels. This is a
# deliberate scope decision -- sub-class exhaustiveness is what the spec's
# test plan (section 27) requires; higher levels are a bonus, not a
# promise.
#
# Run from the repository root:
#   Rscript scripts/build_psic_correspondence.R

suppressPackageStartupMessages({
  library(tibble)
  library(dplyr)
})

source("R/schema.R")
source("R/adapters/adapter_phscs.R")
source("R/correspondence/schema.R")
source("R/correspondence/scoring.R")
source("R/correspondence/isic_bridge.R")

OUT_DATA_PATH <- "data/psic_2019_to_2026_correspondence.rds"
OUT_META_PATH <- "data/psic_2019_to_2026_correspondence_metadata.rds"
PSIC_2026_PATH <- "data/psic_2026.rds"

`%||%` <- function(a, b) if (is.null(a) || (length(a) == 1 && is.na(a))) b else a

# ---------------------------------------------------------------------------
# 1. Load both editions
# ---------------------------------------------------------------------------

message("Loading PSIC 2019 (via phscs) and PSIC Revision 5 / 2026 (local artifact)...")

psic19 <- phscs_get("psic", "2019")
if (!file.exists(PSIC_2026_PATH)) {
  stop(sprintf("PSIC 2026 runtime artifact missing at %s -- run scripts/build_psic_2026.R first.", PSIC_2026_PATH), call. = FALSE)
}
psic26 <- readRDS(PSIC_2026_PATH)

sub19 <- psic19[psic19$level == "sub-class", , drop = FALSE]
sub26 <- psic26[psic26$level == "sub-class", , drop = FALSE]
class19 <- psic19[psic19$level == "class", , drop = FALSE]
class26 <- psic26[psic26$level == "class", , drop = FALSE]

class19_label_by_code <- stats::setNames(class19$label, class19$code)
class26_label_by_code <- stats::setNames(class26$label, class26$code)

message(sprintf(
  "2019: %d sub-classes, %d classes. 2026: %d sub-classes, %d classes.",
  nrow(sub19), nrow(class19), nrow(sub26), nrow(class26)
))

bridge <- load_isic_bridge()
if (is.null(bridge)) {
  message("UN ISIC Rev.4<->Rev.5 bridge not available (missing workbook or readxl) -- proceeding without it.")
} else {
  message(sprintf(
    "UN ISIC Rev.4<->Rev.5 bridge loaded: %d ISIC Rev.4 class codes with correspondence rows.",
    length(bridge$bridge_4to5)
  ))
}

# ---------------------------------------------------------------------------
# 2. Candidate indices over PSIC 2026 sub-classes
# ---------------------------------------------------------------------------

sub26$prefix4 <- substr(sub26$code, 1, 4)
sub26$prefix3 <- substr(sub26$code, 1, 3)
sub26$prefix2 <- substr(sub26$code, 1, 2)

idx_by_code   <- stats::setNames(seq_len(nrow(sub26)), sub26$code)
idx_by_prefix4 <- split(seq_len(nrow(sub26)), sub26$prefix4)
idx_by_prefix3 <- split(seq_len(nrow(sub26)), sub26$prefix3)
idx_by_prefix2 <- split(seq_len(nrow(sub26)), sub26$prefix2)

.safe_lookup <- function(named_vec, key) {
  if (is.na(key) || !key %in% names(named_vec)) return(NA_character_)
  unname(named_vec[[key]])
}

isic_supported_for <- function(source_code, target_code) {
  sc4 <- substr(source_code, 1, 4)
  tc4 <- substr(target_code, 1, 4)
  isic_bridge_supported(
    bridge, sc4, tc4,
    .safe_lookup(class19_label_by_code, sc4),
    .safe_lookup(class26_label_by_code, tc4)
  )
}

# ---------------------------------------------------------------------------
# 3. Per-source-code matching (sub-class level)
# ---------------------------------------------------------------------------

make_row <- function(source_row, target_row, relation_type, provenance,
                      confidence, confidence_score, method, evidence,
                      bucket = NA_character_, singleton = NA) {
  tibble::tibble(
    source_system  = "psic",
    source_version = "2019",
    source_code    = if (is.null(source_row)) NA_character_ else source_row$code,
    source_level   = if (is.null(source_row)) NA_character_ else source_row$level,
    source_label   = if (is.null(source_row)) NA_character_ else source_row$label,
    target_system  = "psic",
    target_version = "2026",
    target_code    = if (is.null(target_row)) NA_character_ else target_row$code,
    target_level   = if (is.null(target_row)) NA_character_ else target_row$level,
    target_label   = if (is.null(target_row)) NA_character_ else target_row$label,
    relation_type    = relation_type,
    provenance       = provenance,
    confidence       = confidence,
    confidence_score = as.double(confidence_score),
    method           = method,
    evidence         = evidence,
    review_status    = "auto",
    notes            = NA_character_,
    .bucket          = bucket,
    .singleton       = singleton
  )
}

rows <- vector("list", nrow(sub19))

for (i in seq_len(nrow(sub19))) {
  s <- sub19[i, ]
  exact_idx <- if (s$code %in% names(idx_by_code)) unname(idx_by_code[[s$code]]) else NULL

  if (!is.null(exact_idx)) {
    cand_idx <- exact_idx
    bucket <- "exact_or_prefix"
  } else {
    cand_idx <- idx_by_prefix4[[substr(s$code, 1, 4)]]
    bucket <- if (!is.null(cand_idx) && length(cand_idx) > 0) "exact_or_prefix" else NA_character_
  }

  fallback_level <- NA_character_
  if (is.na(bucket)) {
    idx3 <- idx_by_prefix3[[substr(s$code, 1, 3)]]
    pool_idx <- idx3
    fallback_level <- "group"
    if (is.null(pool_idx) || length(pool_idx) == 0) {
      pool_idx <- idx_by_prefix2[[substr(s$code, 1, 2)]]
      fallback_level <- "division"
    }
    if (!is.null(pool_idx) && length(pool_idx) > 0) {
      pool <- sub26[pool_idx, , drop = FALSE]
      sims <- vapply(pool$label, function(l) jaccard_token_similarity(s$label, l), numeric(1))
      keep <- sims >= CORRESPONDENCE_SIMILARITY_THRESHOLDS$candidate_minimum
      if (any(keep)) {
        pool <- pool[keep, , drop = FALSE]
        sims <- sims[keep]
        ord <- order(-sims)
        pool <- pool[ord, , drop = FALSE]
        sims <- sims[ord]
        keep2 <- sims >= (sims[1] - 0.15)
        n_keep <- min(5L, sum(keep2))
        cand_idx <- pool_idx[keep][ord][keep2][seq_len(n_keep)]
        bucket <- "fallback"
      }
    }
  }

  if (is.na(bucket)) {
    # No candidate found by any method: discontinued.
    rows[[i]] <- make_row(
      source_row = s, target_row = NULL,
      relation_type = "discontinued", provenance = "derived",
      confidence = "moderate", confidence_score = NA_real_,
      method = "no_match_exhaustive_search",
      evidence = sprintf(
        "No 2026 sub-class shares code '%s', its class prefix '%s', or a label above the similarity floor (%.2f) within its group or division.",
        s$code, substr(s$code, 1, 4), CORRESPONDENCE_SIMILARITY_THRESHOLDS$candidate_minimum
      ),
      bucket = "none", singleton = NA
    )
    next
  }

  cands <- sub26[cand_idx, , drop = FALSE]
  is_singleton <- nrow(cands) == 1L

  cand_rows <- vector("list", nrow(cands))
  for (j in seq_len(nrow(cands))) {
    t <- cands[j, ]
    exact_code <- identical(t$code, s$code)
    sc <- score_correspondence(
      exact_code = exact_code,
      source_code = s$code, target_code = t$code,
      source_label = s$label, target_label = t$label,
      source_description = s$description, target_description = t$description,
      isic_bridge_supported = isic_supported_for(s$code, t$code)
    )

    if (bucket == "exact_or_prefix") {
      provenance <- "derived"
      if (is_singleton) {
        relation <- if (exact_code) {
          if (sc$near_identical_title) "unchanged" else "renamed"
        } else {
          "renamed"
        }
      } else {
        relation <- "split"
      }
      method <- if (exact_code) "exact_code_match" else "class_prefix_continuity"
      evidence <- if (exact_code) {
        sprintf(
          "Exact code match ('%s'). Normalized labels %s.%s",
          s$code, if (sc$near_identical_title) "identical/near-identical" else "differ",
          if (isTRUE(isic_supported_for(s$code, t$code))) " Corroborated by UN ISIC Rev.4->Rev.5 class bridge." else ""
        )
      } else {
        sprintf(
          "Code changed within the same 4-digit class family ('%s' -> '%s', both under class '%s'). %d candidate(s) in this family.%s",
          s$code, t$code, substr(s$code, 1, 4), nrow(cands),
          if (isTRUE(isic_supported_for(s$code, t$code))) " Corroborated by UN ISIC Rev.4->Rev.5 class bridge." else ""
        )
      }
    } else {
      provenance <- "suggested"
      relation <- if (nrow(cands) == 1L) "possible" else "complex"
      method <- sprintf("%s_label_similarity", fallback_level)
      evidence <- sprintf(
        "No shared code family; matched by normalized label-token similarity (%.2f) within the same %s ('%s').%s",
        jaccard_token_similarity(s$label, t$label), fallback_level,
        substr(s$code, 1, if (fallback_level == "group") 3 else 2),
        if (isTRUE(isic_supported_for(s$code, t$code))) " Also corroborated by UN ISIC Rev.4->Rev.5 class bridge." else ""
      )
    }

    cand_rows[[j]] <- make_row(
      source_row = s, target_row = t,
      relation_type = relation, provenance = provenance,
      confidence = sc$confidence, confidence_score = sc$score,
      method = method, evidence = evidence,
      bucket = bucket, singleton = is_singleton
    )
  }
  rows[[i]] <- dplyr::bind_rows(cand_rows)
}

sub_rows <- dplyr::bind_rows(rows)

# ---------------------------------------------------------------------------
# 4. Merge detection: relabel "exact_or_prefix" singleton rows whose target
#    is shared by more than one distinct 2019 source code as "merged".
#
#    Scoped deliberately to hierarchy-derived (exact_or_prefix) singleton
#    rows only -- NOT to "fallback"/suggested rows or to a source's own
#    "split" fan-out candidates -- so "merged" always reflects genuine
#    exact-code/class-prefix continuity evidence on both the many source
#    codes and the one target, never a coincidental label-similarity
#    overlap. A source that is itself split across multiple targets, one of
#    which happens to also be a merge target for another source, keeps its
#    own "split" label on that row rather than being force-relabeled
#    "complex" -- documented as an accepted simplification (see file header).
# ---------------------------------------------------------------------------

singleton_ab <- sub_rows[sub_rows$.bucket == "exact_or_prefix" & sub_rows$.singleton, , drop = FALSE]
target_counts <- table(singleton_ab$target_code)
merged_targets <- names(target_counts[target_counts > 1])

is_merge_row <- sub_rows$.bucket == "exact_or_prefix" & sub_rows$.singleton &
  sub_rows$target_code %in% merged_targets
sub_rows$relation_type[is_merge_row] <- "merged"
sub_rows$evidence[is_merge_row] <- paste0(
  sub_rows$evidence[is_merge_row],
  " Multiple 2019 sub-classes converge on this single 2026 sub-class."
)

sub_rows$.bucket <- NULL
sub_rows$.singleton <- NULL

# ---------------------------------------------------------------------------
# 5. "New" rows: 2026 sub-classes with no 2019 source anywhere above.
# ---------------------------------------------------------------------------

used_targets <- unique(sub_rows$target_code[!is.na(sub_rows$target_code)])
new_codes <- setdiff(sub26$code, used_targets)
new_rows <- if (length(new_codes) > 0) {
  new_pool <- sub26[match(new_codes, sub26$code), , drop = FALSE]
  dplyr::bind_rows(lapply(seq_len(nrow(new_pool)), function(k) {
    t <- new_pool[k, ]
    make_row(
      source_row = NULL, target_row = t,
      relation_type = "new", provenance = "derived",
      confidence = "moderate", confidence_score = NA_real_,
      method = "new_in_2026_no_2019_counterpart",
      evidence = sprintf("No 2019 sub-class exhaustively matched to '%s' by any method above.", t$code),
      bucket = "none", singleton = NA
    )
  }))
} else {
  NULL
}
if (!is.null(new_rows)) {
  new_rows$.bucket <- NULL
  new_rows$.singleton <- NULL
}

# ---------------------------------------------------------------------------
# 6. Supplementary higher-level pass: division/group/class exact matches only.
# ---------------------------------------------------------------------------

higher_level_rows <- list()
for (lvl in c("division", "group", "class")) {
  l19 <- psic19[psic19$level == lvl, , drop = FALSE]
  l26 <- psic26[psic26$level == lvl, , drop = FALSE]
  common <- intersect(l19$code, l26$code)
  if (length(common) == 0) next
  for (cd in common) {
    s <- l19[l19$code == cd, , drop = FALSE][1, ]
    t <- l26[l26$code == cd, , drop = FALSE][1, ]
    sc <- score_correspondence(
      exact_code = TRUE,
      source_code = s$code, target_code = t$code,
      source_label = s$label, target_label = t$label,
      source_description = s$description, target_description = t$description,
      isic_bridge_supported = FALSE
    )
    relation <- if (sc$near_identical_title) "unchanged" else "renamed"
    higher_level_rows[[length(higher_level_rows) + 1L]] <- make_row(
      source_row = s, target_row = t,
      relation_type = relation, provenance = "derived",
      confidence = sc$confidence, confidence_score = sc$score,
      method = "exact_code_match",
      evidence = sprintf("Exact code match at %s level ('%s'). Normalized labels %s.",
                          lvl, cd, if (sc$near_identical_title) "identical/near-identical" else "differ"),
      bucket = "none", singleton = NA
    )
  }
}
higher_rows_df <- if (length(higher_level_rows) > 0) dplyr::bind_rows(higher_level_rows) else NULL
if (!is.null(higher_rows_df)) {
  higher_rows_df$.bucket <- NULL
  higher_rows_df$.singleton <- NULL
}

# ---------------------------------------------------------------------------
# 7. Assemble, validate, save
# ---------------------------------------------------------------------------

correspondence <- dplyr::bind_rows(sub_rows, new_rows, higher_rows_df)
correspondence <- correspondence[, CORRESPONDENCE_SCHEMA_COLUMNS]
for (col in setdiff(CORRESPONDENCE_SCHEMA_COLUMNS, "confidence_score")) {
  correspondence[[col]] <- as.character(correspondence[[col]])
}
correspondence$confidence_score <- as.double(correspondence$confidence_score)

validate_correspondence_tibble(correspondence)

dir.create(dirname(OUT_DATA_PATH), recursive = TRUE, showWarnings = FALSE)
saveRDS(correspondence, OUT_DATA_PATH)

metadata <- list(
  built_at = as.character(Sys.time()),
  source_versions = list(
    psic_2019 = "phscs::get_psic(version = \"2019\")",
    psic_2026 = PSIC_2026_PATH
  ),
  isic_bridge = list(
    used = !is.null(bridge),
    source_url = ISIC_BRIDGE_SOURCE_URL,
    local_path = ISIC_BRIDGE_XLSX_PATH
  ),
  scoring = list(
    weights = CORRESPONDENCE_SCORE_WEIGHTS,
    confidence_thresholds = CORRESPONDENCE_CONFIDENCE_THRESHOLDS,
    similarity_thresholds = CORRESPONDENCE_SIMILARITY_THRESHOLDS
  ),
  row_counts = list(
    total = nrow(correspondence),
    by_relation_type = as.list(table(correspondence$relation_type)),
    by_provenance = as.list(table(correspondence$provenance)),
    by_confidence = as.list(table(correspondence$confidence))
  ),
  psic_2019_subclass_count = nrow(sub19),
  psic_2026_subclass_count = nrow(sub26),
  psic_2019_subclasses_discontinued = sum(sub_rows$relation_type == "discontinued"),
  psic_2026_subclasses_new = length(new_codes),
  method_summary = paste(
    "Deterministic, code/hierarchy/label-similarity matching at PSIC",
    "sub-class level (exhaustive), with a lightweight exact-code-only",
    "supplementary pass at division/group/class level. No generative LLM",
    "used as a mapping engine. See scripts/build_psic_correspondence.R",
    "header comment and docs/CORRESPONDENCE_SOURCES.md for full method."
  )
)
saveRDS(metadata, OUT_META_PATH)

# ---------------------------------------------------------------------------
# 8. Console validation report
# ---------------------------------------------------------------------------

message("\n=== PSIC 2019<->2026 correspondence build report ===")
message(sprintf("Total rows: %d", nrow(correspondence)))
message("By relation_type:")
print(table(correspondence$relation_type))
message("By provenance:")
print(table(correspondence$provenance))
message("By confidence:")
print(table(correspondence$confidence))
message(sprintf(
  "2019 sub-classes with zero match (discontinued): %d / %d",
  sum(sub_rows$relation_type == "discontinued"), nrow(sub19)
))
message(sprintf(
  "2026 sub-classes with no 2019 counterpart (new): %d / %d",
  length(new_codes), nrow(sub26)
))
message(sprintf("Saved: %s", OUT_DATA_PATH))
message(sprintf("Saved: %s", OUT_META_PATH))
