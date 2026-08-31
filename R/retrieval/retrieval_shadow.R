# Semantic mode and shadow telemetry.
#
# WHAT THIS FILE IS FOR
# -----------------------------------------------------------------
# The semantic tier is measured in this release and authoritative in
# none of it. This file holds the two things that make that statement
# checkable rather than aspirational:
#
#   1. `retrieval_semantic_mode()` -- one explicit three-state switch,
#      `off` / `shadow` / `active`, that decides whether semantic
#      candidates may reach fusion at all.
#   2. An internal, bounded telemetry ring that records what the
#      semantic tier WOULD have proposed, so a future activation
#      decision can be argued from measurement instead of intuition.
#
# CONFIGURATION IS REUSED, NOT REINVENTED
# -----------------------------------------------------------------
# The provider already reads `RETRIEVAL_EMBEDDING_ENABLED/_URL/_MODEL/
# _API_KEY/_TIMEOUT` (see retrieval_embedding_provider.R). Nothing here
# duplicates that. Exactly one variable is added, in the same family and
# read with the same helper:
#
#   RETRIEVAL_SEMANTIC_MODE   "off" | "shadow" | "active"   (default "off")
#
# The two settings answer different questions and are deliberately
# orthogonal:
#
#   RETRIEVAL_EMBEDDING_ENABLED  CAN we obtain a vector? (transport)
#   RETRIEVAL_SEMANTIC_MODE      MAY the result carry weight? (authority)
#
# Keeping them separate is what lets `shadow` be measured with an
# injected `embed_fn` in a test with no endpoint, and equally lets a
# fully-configured endpoint sit at `off` in production.
#
# `active` IS NAMED BUT NOT REACHABLE
# -----------------------------------------------------------------
# Release rule (spec 40): for `pre-staging-v10`, semantic shadow is
# allowed and semantic authority is forbidden. `active` therefore exists
# as a named state -- so that the eventual activation is a one-constant
# change reviewed on its merits, not a redesign -- but
# `RETRIEVAL_SEMANTIC_ACTIVE_PERMITTED` is FALSE, and any request for
# `active` is clamped down to `shadow`. There is no environment variable
# that can lift that clamp; it takes a source change and a code review.

# The complete mode vocabulary. Anything outside it is not a mode.
RETRIEVAL_SEMANTIC_MODES <- c("off", "shadow", "active")

# The repository default. Must stay "off": a checkout with no
# configuration must run the deterministic engine and nothing else.
RETRIEVAL_SEMANTIC_DEFAULT_MODE <- "off"

# The v10 release gate. FALSE means `active` cannot be entered at
# runtime by any configuration. Flipping this is the activation
# decision itself and must not be done on mock evidence -- see
# `scripts/evaluate_retrieval.R --semantic` for what live evidence the
# decision needs.
RETRIEVAL_SEMANTIC_ACTIVE_PERMITTED <- FALSE

# How many shadow observations are retained. The ring exists so a long
# Shiny session cannot grow an unbounded log of user queries in memory;
# the oldest record is dropped once the cap is reached. Sized for a
# diagnostic window, not for an audit trail -- shadow telemetry is
# deliberately NOT durable.
RETRIEVAL_SHADOW_MAX_RECORDS <- 200L

# Default depth of the recorded semantic shortlist. 10 because the
# benchmark reports Recall@1/@5/@10 and the deterministic answer's rank
# is only interesting inside that window.
RETRIEVAL_SHADOW_TOP_K <- 10L

#' Resolve the effective semantic mode.
#'
#' @param requested character(1) or NULL. NULL reads
#'   `RETRIEVAL_SEMANTIC_MODE` from the environment. Supplying a value
#'   is how tests and the benchmark harness pin a mode without touching
#'   process-wide state.
#'
#' @return One of "off", "shadow". Never "active" while
#'   `RETRIEVAL_SEMANTIC_ACTIVE_PERMITTED` is FALSE. An unrecognised
#'   value degrades to the default rather than erroring: a typo in a
#'   deployment variable must fail closed, not take the app down.
retrieval_semantic_mode <- function(requested = NULL) {
  m <- if (is.null(requested)) {
    .retrieval_env_chr("RETRIEVAL_SEMANTIC_MODE", RETRIEVAL_SEMANTIC_DEFAULT_MODE)
  } else {
    requested
  }
  m <- suppressWarnings(as.character(m))
  if (length(m) != 1L || is.na(m)) return(RETRIEVAL_SEMANTIC_DEFAULT_MODE)
  m <- tolower(trimws(m))
  if (!nzchar(m) || !m %in% RETRIEVAL_SEMANTIC_MODES) {
    return(RETRIEVAL_SEMANTIC_DEFAULT_MODE)
  }
  if (identical(m, "active") && !isTRUE(RETRIEVAL_SEMANTIC_ACTIVE_PERMITTED)) {
    return("shadow")
  }
  m
}

#' The mode as CONFIGURED, before the `active` clamp.
#'
#' Diagnostics only. It exists so an operator who set `active` can be
#' told their setting was recognised and deliberately held at `shadow`,
#' rather than silently seeing "shadow" and assuming a typo.
retrieval_semantic_mode_requested <- function() {
  m <- tolower(trimws(.retrieval_env_chr("RETRIEVAL_SEMANTIC_MODE",
                                         RETRIEVAL_SEMANTIC_DEFAULT_MODE)))
  if (!nzchar(m) || !m %in% RETRIEVAL_SEMANTIC_MODES) RETRIEVAL_SEMANTIC_DEFAULT_MODE else m
}

#' May a semantic candidate influence the deterministic answer?
#'
#' The single predicate every authority decision must consult. It is
#' FALSE for every reachable configuration of this release.
retrieval_semantic_is_authoritative <- function(mode = retrieval_semantic_mode()) {
  isTRUE(RETRIEVAL_SEMANTIC_ACTIVE_PERMITTED) && identical(mode, "active")
}

#' Is the semantic tier being measured (run, recorded, discarded)?
retrieval_shadow_enabled <- function(mode = retrieval_semantic_mode()) {
  identical(mode, "shadow")
}

# ---------------------------------------------------------------------
# The telemetry ring
# ---------------------------------------------------------------------
#
# In-memory, process-local, bounded, resettable, and never rendered.
# It holds normalized queries, which are user text, so it is treated the
# same way as any other transient query state: never written to disk,
# never returned through a model-facing tool, never placed in a UI
# output. `tests/testthat/test-semantic-shadow.R` asserts that no UI or
# assistant source file references any function in this file.

.retrieval_shadow_state <- new.env(parent = emptyenv())
.retrieval_shadow_state$records <- list()
.retrieval_shadow_state$seq <- 0L
.retrieval_shadow_state$dropped <- 0L

#' Discard every shadow observation.
#'
#' Called between benchmark arms and at the start of a measurement run.
#' Also the mechanism a session uses to drop query text it no longer
#' needs.
retrieval_shadow_reset <- function() {
  .retrieval_shadow_state$records <- list()
  .retrieval_shadow_state$seq <- 0L
  .retrieval_shadow_state$dropped <- 0L
  invisible(NULL)
}

#' How many observations are currently retained.
retrieval_shadow_count <- function() length(.retrieval_shadow_state$records)

#' How many observations have been evicted by the ring bound.
retrieval_shadow_dropped <- function() .retrieval_shadow_state$dropped

#' Every retained observation, oldest first. Internal diagnostic use.
retrieval_shadow_records <- function() .retrieval_shadow_state$records

#' The most recent observation, or NULL.
retrieval_shadow_last <- function() {
  n <- length(.retrieval_shadow_state$records)
  if (n == 0L) return(NULL)
  .retrieval_shadow_state$records[[n]]
}

.retrieval_shadow_chr1 <- function(x, default = NA_character_) {
  if (is.null(x) || length(x) < 1L) return(default)
  v <- as.character(x)[1L]
  if (is.na(v)) default else v
}

#' Record one semantic observation.
#'
#' A no-op returning NULL when the mode is not `shadow`, so the caller
#' pays nothing at all with the tier off -- no allocation, no
#' normalization, no list growth.
#'
#' `semantic_authority_applied` is written by this constructor and has no
#' setter. It is FALSE in every record this function can produce, which
#' is the point: the field is an assertion about the release, not a
#' variable.
#'
#' @param query character(1) raw query; stored NORMALIZED.
#' @param system,version character(1) or NULL.
#' @param codes,scores,ranks the semantic shortlist, parallel vectors.
#' @param deterministic_code character(1) or NULL -- the authoritative
#'   answer the deterministic engine actually produced, when the caller
#'   knows it. `retrieval_shadow_annotate()` can supply it later.
#' @param context_compatible character(1): "compatible", "incompatible"
#'   or "unknown".
#' @param provider_status character(1): "ok", "no_index", "no_query",
#'   "provider_unavailable" or "error".
#' @param origin character(1): where the observation was taken --
#'   "fusion" (the engine's own call, discarded) or "probe" (an
#'   out-of-band measurement).
#' @param mode the resolved mode; supplied by the caller so a benchmark
#'   can pin it.
#'
#' @return The record id (integer) invisibly, or NULL when not recording.
retrieval_shadow_record <- function(query,
                                    system = NULL, version = NULL,
                                    codes = character(0),
                                    scores = numeric(0),
                                    ranks = integer(0),
                                    deterministic_code = NULL,
                                    context_compatible = "unknown",
                                    provider_status = "ok",
                                    origin = "fusion",
                                    mode = retrieval_semantic_mode()) {
  if (!retrieval_shadow_enabled(mode)) return(NULL)

  # Never let telemetry break retrieval. Any failure here is silently a
  # lost measurement, which is a diagnostic loss and nothing more.
  tryCatch({
    q <- if (exists("retrieval_normalize", mode = "function")) {
      retrieval_normalize(.retrieval_shadow_chr1(query, ""))
    } else {
      .retrieval_shadow_chr1(query, "")
    }
    if (length(q) != 1L || is.na(q)) q <- NA_character_

    codes <- as.character(codes)
    scores <- suppressWarnings(as.numeric(scores))
    ranks <- suppressWarnings(as.integer(ranks))
    n <- length(codes)
    if (length(scores) != n) scores <- rep(NA_real_, n)
    if (length(ranks) != n) ranks <- seq_len(n)

    det <- .retrieval_shadow_chr1(deterministic_code)
    ctx <- .retrieval_shadow_chr1(context_compatible, "unknown")
    if (!ctx %in% c("compatible", "incompatible", "unknown")) ctx <- "unknown"

    .retrieval_shadow_state$seq <- .retrieval_shadow_state$seq + 1L
    rec <- list(
      id = .retrieval_shadow_state$seq,
      time = Sys.time(),
      mode = .retrieval_shadow_chr1(mode, "shadow"),
      origin = .retrieval_shadow_chr1(origin, "fusion"),
      normalized_query = q,
      system = .retrieval_shadow_chr1(system),
      version = .retrieval_shadow_chr1(version),
      deterministic_code = det,
      deterministic_rank = .retrieval_shadow_rank_of(det, codes),
      semantic_codes = codes,
      semantic_scores = scores,
      semantic_ranks = ranks,
      semantic_top1_code = if (n > 0L) codes[1L] else NA_character_,
      semantic_top1_score = if (n > 0L) scores[1L] else NA_real_,
      context_compatible = ctx,
      provider_status = .retrieval_shadow_chr1(provider_status, "ok"),
      # Invariant, not a setting. See spec 26 and 40.
      semantic_authority_applied = FALSE
    )

    .retrieval_shadow_state$records <-
      c(.retrieval_shadow_state$records, list(rec))
    over <- length(.retrieval_shadow_state$records) - RETRIEVAL_SHADOW_MAX_RECORDS
    if (over > 0L) {
      .retrieval_shadow_state$records <-
        .retrieval_shadow_state$records[-seq_len(over)]
      .retrieval_shadow_state$dropped <-
        .retrieval_shadow_state$dropped + as.integer(over)
    }

    invisible(rec$id)
  }, error = function(e) NULL)
}

# Rank of `code` within the shortlist, or NA when absent/unknown.
.retrieval_shadow_rank_of <- function(code, codes) {
  if (is.null(code) || length(code) != 1L || is.na(code) || !nzchar(code)) {
    return(NA_integer_)
  }
  hit <- match(code, as.character(codes))
  if (is.na(hit)) NA_integer_ else as.integer(hit)
}

#' Attach the deterministic answer to an observation after the fact.
#'
#' The engine's semantic call happens BEFORE the deterministic result
#' exists, so the two halves of a spec-26 record are necessarily written
#' at different moments. This closes the record and recomputes the
#' deterministic answer's rank within the semantic shortlist.
#'
#' @param deterministic_code character(1).
#' @param context_compatible optional override.
#' @param id record id; defaults to the most recent observation.
#'
#' @return TRUE if a record was updated, FALSE otherwise.
retrieval_shadow_annotate <- function(deterministic_code,
                                      context_compatible = NULL,
                                      id = NULL) {
  recs <- .retrieval_shadow_state$records
  if (length(recs) == 0L) return(FALSE)

  pos <- if (is.null(id)) {
    length(recs)
  } else {
    match(as.integer(id)[1L], vapply(recs, function(r) r$id, integer(1)))
  }
  if (is.na(pos) || length(pos) != 1L) return(FALSE)

  rec <- recs[[pos]]
  rec$deterministic_code <- .retrieval_shadow_chr1(deterministic_code)
  rec$deterministic_rank <- .retrieval_shadow_rank_of(rec$deterministic_code,
                                                      rec$semantic_codes)
  if (!is.null(context_compatible)) {
    ctx <- .retrieval_shadow_chr1(context_compatible, "unknown")
    if (!ctx %in% c("compatible", "incompatible", "unknown")) ctx <- "unknown"
    rec$context_compatible <- ctx
  }
  # Re-asserted on every write. Nothing may set it TRUE.
  rec$semantic_authority_applied <- FALSE

  .retrieval_shadow_state$records[[pos]] <- rec
  TRUE
}

#' A flat, one-row-per-observation view. Internal diagnostic use.
#'
#' Vectors are summarised to their head; the full shortlist stays in
#' `retrieval_shadow_records()`. Raw embedding vectors are never stored
#' anywhere, so there is nothing here to leak.
retrieval_shadow_summary <- function() {
  recs <- .retrieval_shadow_state$records
  if (length(recs) == 0L) {
    return(data.frame(
      id = integer(0), origin = character(0), system = character(0),
      version = character(0), normalized_query = character(0),
      deterministic_code = character(0), deterministic_rank = integer(0),
      semantic_top1_code = character(0), semantic_top1_score = numeric(0),
      n_semantic = integer(0), context_compatible = character(0),
      provider_status = character(0), semantic_authority_applied = logical(0),
      stringsAsFactors = FALSE
    ))
  }
  g <- function(f, default) vapply(recs, function(r) {
    v <- r[[f]]
    if (is.null(v) || length(v) != 1L) default else v
  }, default)
  data.frame(
    id = g("id", NA_integer_),
    origin = g("origin", NA_character_),
    system = g("system", NA_character_),
    version = g("version", NA_character_),
    normalized_query = g("normalized_query", NA_character_),
    deterministic_code = g("deterministic_code", NA_character_),
    deterministic_rank = g("deterministic_rank", NA_integer_),
    semantic_top1_code = g("semantic_top1_code", NA_character_),
    semantic_top1_score = g("semantic_top1_score", NA_real_),
    n_semantic = vapply(recs, function(r) length(r$semantic_codes), integer(1)),
    context_compatible = g("context_compatible", NA_character_),
    provider_status = g("provider_status", NA_character_),
    semantic_authority_applied = g("semantic_authority_applied", NA),
    stringsAsFactors = FALSE
  )
}

#' Does every retained observation still assert non-authority?
#'
#' Cheap enough to call from a test after any amount of activity. TRUE on
#' an empty ring.
retrieval_shadow_invariants_hold <- function() {
  recs <- .retrieval_shadow_state$records
  if (length(recs) == 0L) return(TRUE)
  all(vapply(recs, function(r) identical(r$semantic_authority_applied, FALSE),
             logical(1)))
}

#' Measure the semantic tier OUT OF BAND for one query.
#'
#' This is the shadow path proper: it is called ALONGSIDE the
#' deterministic engine, never inside it, so there is no code path by
#' which its result can reach fusion, `selected_code`, `allowed_codes`,
#' clarification status or current-edition verification. The strongest
#' guarantee available is a structural one, and this is it -- the caller
#' receives a record id, not candidates.
#'
#' A no-op returning NULL when the mode is not `shadow`.
#'
#' @param query character(1).
#' @param index a loaded embedding index, or NULL.
#' @param deterministic_codes character vector -- the codes the
#'   deterministic engine returned, best first. Only used to compute the
#'   authoritative answer's rank within the semantic shortlist.
#' @param system,version character(1) or NULL; enforced against the index.
#' @param top_k depth of the recorded shortlist.
#' @param config,embed_fn passed through to the semantic search.
#' @param context_compatible caller's context verdict, when known.
#' @param mode resolved mode; pin it in a benchmark.
#'
#' @return The record id invisibly, or NULL.
retrieval_shadow_observe <- function(query, index,
                                     deterministic_codes = character(0),
                                     system = NULL, version = NULL,
                                     top_k = RETRIEVAL_SHADOW_TOP_K,
                                     config = NULL, embed_fn = NULL,
                                     context_compatible = "unknown",
                                     mode = retrieval_semantic_mode()) {
  if (!retrieval_shadow_enabled(mode)) return(NULL)
  if (!exists("retrieval_semantic_search", mode = "function")) return(NULL)

  res <- tryCatch(
    retrieval_semantic_search(query, index, top_k = top_k,
                              system = system, version = version,
                              config = config, embed_fn = embed_fn),
    error = function(e) NULL
  )

  status <- if (is.null(index)) {
    "no_index"
  } else if (is.null(res) || !is.data.frame(res) || nrow(res) == 0L) {
    # Cannot be distinguished from "the provider worked and nothing
    # cleared the floor" at this level, and the honest label says so.
    "provider_unavailable_or_empty"
  } else {
    "ok"
  }

  codes <- if (is.data.frame(res) && nrow(res) > 0L) as.character(res$code) else character(0)
  scores <- if (is.data.frame(res) && nrow(res) > 0L) as.numeric(res$semantic_score) else numeric(0)
  ranks <- if (is.data.frame(res) && nrow(res) > 0L) as.integer(res$semantic_rank) else integer(0)

  det <- if (length(deterministic_codes) > 0L) as.character(deterministic_codes)[1L] else NULL

  retrieval_shadow_record(
    query = query, system = system, version = version,
    codes = codes, scores = scores, ranks = ranks,
    deterministic_code = det,
    context_compatible = context_compatible,
    provider_status = status,
    origin = "probe",
    mode = mode
  )
}
