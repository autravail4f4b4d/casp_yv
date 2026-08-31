# G2 -- contextual resolver convergence.
#
# This is the module that makes the structural defect UNREPRESENTABLE.
#
# `assistant_code_occupation_and_activity()` takes `occupation` and
# `establishment_activity` as two separate arguments. There is no single
# free-text field, so the model physically cannot send one undifferentiated
# sentence to both systems the way the shipped build did -- and if it
# supplies only an occupation, the PSIC half deterministically returns a
# real-world clarification question instead of a guessed code.
#
# Pipeline per slot (both halves share the SAME hybrid retrieval engine --
# nothing here re-implements search):
#
#   slot phrase
#     -> controlled expansion            (assistant_expand_query)
#     -> hybrid retrieval, per expansion (search_classification)
#     -> union, de-duplicated, rank-preserving
#     -> context consistency gate        (assistant_context_filter)
#     -> hierarchy annotation            (assistant_hierarchy_annotate)
#     -> coding-level policy             (assistant_coding_level)
#     -> canonical verification          (get_classification_entry)
#
# Every presented code is a canonical repository row. Nothing in this file
# can mint one.

# How many candidates to keep per slot after filtering.
ASSISTANT_SLOT_CANDIDATE_LIMIT <- 6L

#' Retrieve, filter and rank verified candidates for ONE slot.
#'
#' @param system character(1) "psoc" or "psic" (any registered id works).
#' @param phrase character(1) the slot phrase.
#' @param version character(1) or NULL.
#' @param prefer_detailed logical(1). When TRUE and both an ancestor and
#'   its most-specific descendant survive, the detailed one is ranked
#'   first -- the occupation-coding default (spec 3.1: "target detailed
#'   coding level = Unit Group / 4-digit PSOC").
#'
#' @return list(system, version, query, expansions, total_before_filter,
#'   rejected_incompatible, count, candidates = list of row lists).
assistant_slot_candidates <- function(system, phrase, version = NULL,
                                      prefer_detailed = TRUE,
                                      limit = ASSISTANT_SLOT_CANDIDATE_LIMIT) {
  system_chr <- .assistant_scalar_chr(system)
  phrase_chr <- .assistant_scalar_chr(phrase)
  if (is.null(system_chr) || is.null(phrase_chr)) {
    return(.assistant_empty_slot(system_chr, NA_character_, NA_character_, character(0)))
  }
  version_chr <- .assistant_resolve_version(system_chr, version)
  limit_int <- .assistant_clamp_limit(limit)

  expansions <- assistant_expand_query(phrase_chr)

  # Union of the ordinary hybrid search over each expansion, first
  # occurrence wins so the user's own wording outranks an expansion.
  acc <- NULL
  for (q in expansions) {
    hit <- tryCatch(
      search_classification(system_chr, version_chr, q, limit = 25L),
      error = function(e) NULL
    )
    if (is.null(hit) || nrow(hit) == 0L) next
    acc <- if (is.null(acc)) hit else rbind(acc, hit)
  }
  # Codes named only in a canonical EXAMPLE list are invisible to lexical
  # retrieval; pull them in explicitly so they can compete.
  by_example <- assistant_codes_matching_examples(system_chr, version_chr, phrase_chr)

  # PSA survey coding guidance (occupation side only -- the manual's PSIC
  # codes are a different, incompatible vintage and are never used as
  # codes; see R/assistant/assistant_survey_guidance.R).
  guidance_codes <- if (identical(system_chr, "psoc")) {
    assistant_survey_psoc_evidence(phrase_chr, version_chr)
  } else {
    character(0)
  }

  inject <- unique(c(by_example$code, guidance_codes))
  if (length(inject) > 0L) {
    all_rows <- tryCatch(get_classification(system_chr, version_chr, level = NULL),
                         error = function(e) NULL)
    if (!is.null(all_rows)) {
      extra <- all_rows[as.character(all_rows$code) %in% inject, , drop = FALSE]
      if (nrow(extra) > 0L) {
        acc <- if (is.null(acc)) extra else rbind(acc, extra)
      }
    }
  }

  if (is.null(acc) || nrow(acc) == 0L) {
    return(.assistant_empty_slot(system_chr, version_chr, phrase_chr, expansions))
  }
  acc <- acc[!duplicated(acc$code), , drop = FALSE]
  before <- nrow(acc)

  # Canonical example-occupation evidence (C7). Computed BEFORE the context
  # gate so that a candidate whose official example list names the phrase
  # survives even when its LABEL shares no token with it -- e.g. "mayor"
  # against 1111 LEGISLATORS.
  ex_score <- vapply(
    as.character(acc$code),
    function(cd) assistant_code_example_score(system_chr, version_chr, cd, phrase_chr),
    integer(1)
  )

  # Survey-manual occupational evidence is the strongest signal available:
  # it is PSA's own published coding decision for that exact wording, and
  # every code was re-verified against the current edition before arriving
  # here. It admits a candidate past the context gate for the same reason
  # example evidence does -- the manual names occupations whose canonical
  # LABEL shares no token with the user's wording ("Angkas driver" ->
  # TRANSPORT NETWORK VEHICLE SERVICE MOTORCYCLE DRIVERS).
  is_guidance <- as.character(acc$code) %in% guidance_codes

  keep_ex <- ex_score > ASSISTANT_EXAMPLE_SCORE_NONE
  filtered <- assistant_context_filter(acc, expansions)
  keep_ctx <- as.character(acc$code) %in% as.character(filtered$code)
  keep <- keep_ctx | keep_ex | is_guidance

  # W2 -- controlled-facet compatibility veto (R/assistant/assistant_compat.R).
  #
  # The gate above asks "is this candidate RELATED to the wording?" and
  # cannot reject a candidate that is related but contradictory: "palay
  # farming" -> Rice MILLING, "private high school" -> Private PRE-PRIMARY
  # education, "teacher" -> TEACHERS' AIDES all pass it honestly. This
  # second, narrower gate rejects only a direct contradiction along a
  # closed facet vocabulary (activity action, education level, occupation
  # role), and only when BOTH sides state a value.
  #
  # Survey-manual codes are exempt: PSA's own published decision for an
  # exact phrase outranks this heuristic, exactly as it already outranks
  # the context gate above. Applied HERE rather than inside any one
  # retrieval tier so it covers lexical, fuzzy, n-gram and (when enabled)
  # semantic candidates uniformly -- spec 19 requires that cosine
  # similarity cannot buy its way past a contradiction.
  keep <- keep & assistant_compat_keep(acc, expansions, exempt = is_guidance)

  ex_score <- ex_score[keep]
  is_guidance <- is_guidance[keep]
  acc <- acc[keep, , drop = FALSE]
  rejected <- before - nrow(acc)
  if (nrow(acc) == 0L) {
    out <- .assistant_empty_slot(system_chr, version_chr, phrase_chr, expansions)
    out$total_before_filter <- before
    out$rejected_incompatible <- rejected
    return(out)
  }

  acc <- assistant_hierarchy_annotate(acc)

  roles <- vapply(seq_len(nrow(acc)), function(i) {
    lv <- assistant_coding_level(system_chr, version_chr, acc$code[[i]])
    if (isTRUE(lv$found)) lv$coding_role else NA_character_
  }, character(1))
  levels_disp <- vapply(seq_len(nrow(acc)), function(i) {
    assistant_level_display(acc$level[[i]])
  }, character(1))
  acc$coding_role <- roles
  acc$level_display <- levels_disp
  acc$example_evidence <- ex_score

  # BHW-2 -- provenance of the evidence that put this candidate here.
  # "current_label" means the CURRENT edition's own label/description
  # carried the match. "archived_example" means the match came from an
  # example-occupation list borrowed from an archived edition (see
  # R/assistant/assistant_occupation_examples.R), which is allowed to
  # generate and rank candidates but is NEVER authoritative on its own:
  # `code`, `label` and `version` below are always the CURRENT edition's
  # canonical values, re-read from the repository, and the archived label
  # is never shown to anyone.
  acc$survey_guidance <- is_guidance
  acc$evidence_source <- ifelse(
    is_guidance, "survey_guidance",
    ifelse(ex_score > ASSISTANT_EXAMPLE_SCORE_NONE, "archived_example", "current_label")
  )

  # Ranking, strongest evidence first:
  #   1. canonical example-occupation evidence (exact beats subset)
  #   2. detailed coding level ahead of aggregate hierarchy codes
  #   3. original retrieval rank
  # `order` is stable, so equally-scored rows keep retrieval order.
  # Residual/negated categories ("NON-residential", "... n.e.c.", "Other
  # ...") rank below the affirmative sibling that names the thing directly,
  # unless the user asked for the residual wording themselves.
  acc$residual_match <- vapply(seq_len(nrow(acc)), function(i) {
    assistant_is_residual_match(expansions, acc$label[[i]])
  }, logical(1))

  # W2 -- the mirror image of a residual marker: a NARROWER sibling
  # carrying a qualifier the user never asked for ("... TECHNICAL AND
  # VOCATIONAL secondary education", "... for children WITH special
  # needs"). Ranked below the plain reading for the same reason, and by
  # the same mechanism, as the residual markers above.
  acc$unasked_specialization <- vapply(seq_len(nrow(acc)), function(i) {
    assistant_compat_specialization_penalty(expansions, acc$label[[i]])
  }, integer(1))

  # How much of the user's own wording each candidate actually answers.
  # Used to rank, and below to decide whether a set of siblings is a REAL
  # ambiguity or one the user already resolved by their choice of words.
  acc$query_coverage <- vapply(seq_len(nrow(acc)), function(i) {
    assistant_compat_coverage(expansions, acc$label[[i]])
  }, integer(1))

  # An ancestor of another surviving candidate is never the better answer
  # than the descendant it contains -- it is strictly less specific about
  # the same thing. Measured need: once the government-tier veto correctly
  # removed 84112/84113 for a NATIONAL context, the survivors were the
  # Section P, the Division 84 and the Group 8411, all aggregates with
  # identical query coverage, and retrieval order alone selected the
  # Section. 8411 is the canonical ceiling; P is three levels above it.
  # `hierarchy_role` alone is not sufficient here. It links only parents
  # that are THEMSELVES in the candidate set, so a chain broken by an
  # unretrieved intermediate goes undetected: for the PSA set the rows were
  # P, 84, 8411 and 84119, and because the Group 841 sitting between 84 and
  # 8411 was never retrieved, 84 came back "standalone" and still outranked
  # 8411. `.assistant_ancestor_of_other()` walks the FULL canonical chain,
  # so an ancestor is demoted whether or not the intervening levels happen
  # to have been retrieved.
  # Descendant COUNT, not a flag: a flag cannot separate a Section from the
  # Class three levels below it when both are ancestors. Ascending order
  # therefore prefers the narrowest ancestor. The within-set role still
  # contributes, so a chain the shortlist happens to contain intact is
  # ranked identically to one it does not.
  is_ancestor <- .assistant_ancestor_of_other(
    as.character(acc$code), system_chr, version_chr
  ) + as.integer(!is.na(acc$hierarchy_role) & acc$hierarchy_role == "ancestor")
  # Last specificity tiebreaker. Two aggregates can tie on every key above
  # -- the Division 84 and the Class 8411 have identical query coverage --
  # and without this, retrieval order alone decides between a whole PSIC
  # sector and the canonical ceiling for the context.
  depth <- .assistant_canonical_depth(
    as.character(acc$code), system_chr, version_chr
  )
  is_detailed <- !is.na(acc$coding_role) & acc$coding_role == "detailed"
  ord <- if (isTRUE(prefer_detailed)) {
    order(!acc$survey_guidance, -acc$example_evidence, acc$residual_match,
          acc$unasked_specialization, -acc$query_coverage,
          !is_detailed, is_ancestor, -depth, seq_len(nrow(acc)))
  } else {
    order(!acc$survey_guidance, -acc$example_evidence, acc$residual_match,
          acc$unasked_specialization, -acc$query_coverage,
          is_ancestor, -depth, seq_len(nrow(acc)))
  }
  acc <- acc[ord, , drop = FALSE]
  acc <- utils::head(acc, limit_int)

  # Aggregate-vs-detailed clarification (C2-C5). When two or more sibling
  # detailed codes under the SAME canonical parent survive, the slot text
  # does not determine which one applies: report the shared parent as the
  # supported aggregate and ask, rather than promoting an arbitrary child.
  # A parent with exactly ONE detailed child (PSIC 0113 -> 01130) produces
  # no siblings and therefore no clarification -- the contrast that proves
  # this reads the canonical hierarchy instead of always asking.
  # Ambiguity is judged on the AFFIRMATIVE candidates only. If some
  # siblings match the wording directly and others only match as a
  # residual/negated category, the user has already distinguished them and
  # there is nothing left to ask.
  #
  # An unasked-for SPECIALIZATION is a weaker signal than a residual marker
  # and is deliberately NOT excluded here. It stays a RANKING signal only
  # (see `ord` above), so the plain reading is offered first, but it no
  # longer silently deletes the alternatives. Spec 20 is explicit about the
  # difference: "teacher in a private high school" must not descend to
  # 85312 while 85314 (with special needs) and 85322/85324 (technical and
  # vocational) remain current, compatible and genuinely possible -- the
  # user said none of those words, but they also said nothing that RULES
  # THEM OUT, and a residual marker is the only case where the wording
  # itself does. The correct answer there is the supported parent plus one
  # real-world question, not a confident leaf.
  #
  # The cases that must still settle without asking are separated by
  # stronger, orthogonal evidence and are unaffected: 41001 vs 41002
  # NON-residential by the residual marker, and 86121 Private GENERAL
  # hospital vs 86122 mental / 86123 maternity by query coverage below.
  affirmative <- !acc$residual_match
  amb_pool <- if (any(affirmative)) acc[affirmative, , drop = FALSE] else acc

  # A sibling that answers STRICTLY LESS of the user's wording than
  # another is not a real alternative to ask about. "private general
  # hospital" covers three tokens in 86121 Private GENERAL hospital and
  # only two in 86122 Private MENTAL hospital, so there is nothing to ask.
  # Where the user's wording genuinely does not discriminate -- "growing
  # paddy rice" against irrigated / rainfed / upland -- every sibling
  # scores the same, the pool is untouched, and the question is still
  # asked. Aggregates are exempt: the supported parent must stay in the
  # pool for `.assistant_supported_aggregate()` to find it.
  if (nrow(amb_pool) > 1L && !is.null(amb_pool$query_coverage)) {
    is_agg <- !is.na(amb_pool$coding_role) & amb_pool$coding_role != "detailed"
    best <- max(amb_pool$query_coverage[!is_agg], -Inf)
    if (is.finite(best)) {
      amb_pool <- amb_pool[is_agg | amb_pool$query_coverage >= best, , drop = FALSE]
    }
  }
  amb <- assistant_ambiguity_check(amb_pool)
  supported_aggregate <- .assistant_supported_aggregate(amb_pool, amb)

  # Only a genuine "one shared parent, several detailed children, and the
  # parent itself is verified" shape is worth asking about. Two further
  # suppressions, both measured:
  #   * a set of leaves with no single retrieved parent produced a
  #     clarification with nothing to fall back to (aggregate = NA);
  #   * an EXACT canonical example match already settles the code, so
  #     asking would be noise ("mayor" -> 1111).
  settled_by_example <- nrow(acc) > 0L &&
    (max(acc$example_evidence) >= ASSISTANT_EXAMPLE_SCORE_EXACT ||
       isTRUE(acc$survey_guidance[[1L]]))

  # A third settlement: the user named a DETAILED category exactly. Asking
  # "which of these?" after "growing of rice in upland" -- whose top hit is
  # 01123 Growing of rice in upland, label-for-label -- would be asking
  # them to repeat themselves. Restricted to a detailed top hit on purpose:
  # "growing of rice" also matches a label exactly, but that label is the
  # 0112 Class, and that case genuinely does need the subclass question.
  settled_by_exact_label <- nrow(acc) > 0L &&
    identical(as.character(acc$coding_role[[1L]]), "detailed") &&
    identical(.assistant_norm_text(acc$label[[1L]]), .assistant_norm_text(phrase_chr))

  needs_detail <- isTRUE(amb$ambiguous) &&
    !is.na(supported_aggregate) &&
    !settled_by_example &&
    !settled_by_exact_label

  list(
    system = system_chr,
    version = version_chr,
    query = phrase_chr,
    expansions = expansions,
    total_before_filter = before,
    rejected_incompatible = rejected,
    count = nrow(acc),
    detail_clarification_needed = needs_detail,
    detail_clarification_question = if (needs_detail) amb$clarifying_question else NA_character_,
    detail_options = if (needs_detail) amb$options else list(),
    supported_aggregate_code = if (needs_detail) supported_aggregate else NA_character_,
    candidates = .assistant_rows(
      acc,
      c("system", "version", "level", "level_display", "code", "label",
        "status", "coding_role", "hierarchy_role", "hierarchy_of",
        "example_evidence", "survey_guidance", "evidence_source")
    )
  )
}

# One empty-slot shape, so every early return carries the same fields and
# a caller never has to test for a missing one.
.assistant_empty_slot <- function(system, version, query, expansions) {
  list(
    system = system, version = version, query = query,
    expansions = expansions, total_before_filter = 0L,
    rejected_incompatible = 0L, count = 0L,
    detail_clarification_needed = FALSE,
    detail_clarification_question = NA_character_,
    detail_options = list(),
    supported_aggregate_code = NA_character_,
    candidates = list()
  )
}

# The canonical parent shared by an ambiguous set of detailed siblings --
# the level that IS supported by what the user actually said. NA when the
# set is not ambiguous or the parent was not itself retrieved.
.assistant_supported_aggregate <- function(rows, amb) {
  if (!isTRUE(amb$ambiguous) || length(amb$options) == 0L) return(NA_character_)
  option_codes <- vapply(amb$options, function(o) o$code, character(1))
  parents <- unique(as.character(rows$parent_code[rows$code %in% option_codes]))
  parents <- parents[!is.na(parents)]
  if (length(parents) != 1L) return(NA_character_)
  if (!parents %in% as.character(rows$code)) return(NA_character_)
  parents
}

#' Code an occupation and (separately) an establishment's activity.
#'
#' THE contextual coding entry point. `occupation` -> PSOC only;
#' `establishment_activity` -> PSIC only. They are never combined, and one
#' is never used to infer the other.
#'
#' @param occupation character(1) or NULL -- what the PERSON does.
#' @param establishment_activity character(1) or NULL -- what the
#'   ESTABLISHMENT mainly does. Omit when the user has not said.
#' @param psoc_version,psic_version character(1) or NULL.
#'
#' @return list(occupation = <slot result or NULL>,
#'   industry = <slot result or NULL>, context_known,
#'   needs_psic_clarification, clarification_question, clarification_reason,
#'   guidance).
assistant_code_occupation_and_activity <- function(occupation = NULL,
                                                   establishment_activity = NULL,
                                                   psoc_version = NULL,
                                                   psic_version = NULL) {
  impl <- function() {
    slots <- assistant_slot_contract(occupation, establishment_activity)

    occ_res <- if (!is.na(slots$occupation_query)) {
      assistant_slot_candidates("psoc", slots$occupation_query,
                                version = psoc_version, prefer_detailed = TRUE)
    } else {
      NULL
    }

    ind_res <- if (slots$context_known) {
      assistant_slot_candidates("psic", slots$psic_activity_query,
                                version = psic_version, prefer_detailed = TRUE)
    } else {
      NULL
    }

    # The probe is chosen from what the user actually said: a refused
    # general description gets the manual's "that is too general" probe, a
    # government context gets the provincial/city/municipal question, an
    # agency arrangement gets the who-pays-the-wage question, and silence
    # gets the plain establishment question.
    clarification <- if (slots$needs_psic_clarification) {
      if (isTRUE(slots$activity_too_vague) ||
          assistant_activity_mentions_outsourcing(slots$supplied_activity) ||
          assistant_activity_mentions_government(slots$supplied_activity)) {
        assistant_activity_probe_question(slots$supplied_activity, slots$occupation_query)
      } else {
        assistant_establishment_question(slots$occupation_query)
      }
    } else {
      NA_character_
    }

    guidance <- paste(
      "PSOC classifies the person's occupation; PSIC classifies the",
      "establishment's principal economic activity. They are independent:",
      "an occupation never determines an establishment's PSIC on its own.",
      "Present them as two separate results, each with its own level and",
      "coding role, and never label the PSIC a 'corresponding code' for the",
      "occupation."
    )

    list(
      occupation = occ_res,
      industry = ind_res,
      context_known = slots$context_known,
      activity_too_vague = isTRUE(slots$activity_too_vague),
      activity_outsourced = isTRUE(slots$activity_outsourced),
      needs_psic_clarification = slots$needs_psic_clarification,
      clarification_question = clarification,
      clarification_reason = slots$clarification_reason,
      context_probe = slots$context_probe,
      guidance = guidance
    )
  }
  .assistant_tool_try(impl(), "assistant_code_occupation_and_activity")
}
