# Score a retrieval engine against an evaluation corpus, defaulting to
# data-raw/retrieval_eval_cases.csv.
#
# Run from the repository root:
#
#   Rscript scripts/evaluate_retrieval.R              # current engine, dev corpus
#   Rscript scripts/evaluate_retrieval.R baseline     # pre-hybrid engine
#   Rscript scripts/evaluate_retrieval.R current      # same as no argument
#   Rscript scripts/evaluate_retrieval.R hybrid       # a future named profile
#   Rscript scripts/evaluate_retrieval.R current data-raw/retrieval_eval_holdout_cases.csv
#                                                      # score against a different corpus
#                                                      # (e.g. the independent holdout set)
#
#   Rscript scripts/evaluate_retrieval.R --semantic
#   Rscript scripts/evaluate_retrieval.R --semantic data-raw/retrieval_semantic_eval_cases.csv
#                                                      # semantic OFF vs ON comparison
#
# The second argument exists so a holdout corpus, built after the retrieval
# thresholds were already fixed, can be scored WITHOUT copying it over the
# development corpus or duplicating this script. It changes nothing about
# how a case is scored -- only which CSV is loaded.
#
# Profiles
# --------
#   current   whatever search_classification_result() does right now. This is
#             the number that moves as the milestone lands.
#   baseline  the six-tier whole-query literal engine that shipped before the
#             hybrid milestone, reproduced inside R/retrieval/retrieval_eval.R
#             so the "before" figures stay reproducible after R/search.R is
#             replaced.
#   <other>   resolved through retrieval_search_fn_for_profile(profile) if the
#             convergence owner has defined one, so the hybrid engine can be
#             scored without editing this script.
#
# --semantic mode
# ---------------
# Runs the SAME engine twice over the same corpus, changing exactly one
# thing: whether an embedding index is handed to
# `search_classification_data_result()`. Everything else -- corpus, n-gram
# index, thresholds, evidence gate, fusion weights -- is held constant, so
# the delta is attributable to the semantic tier and to nothing else.
#
# THE ENCODER IS A DETERMINISTIC LOCAL STAND-IN, NOT A LANGUAGE MODEL.
# No embedding provider is configured in this environment (see
# R/retrieval/retrieval_embedding_provider.R). Rather than skip the
# comparison, this mode builds the index with a hashed character-n-gram
# vectoriser that runs offline and returns the same vectors on every run.
# It exercises the whole semantic PATH -- document construction, index
# schema, fingerprinting, cosine search, RRF fusion, the evidence gate --
# at full corpus scale, and it measures real latency and real memory.
#
# WHAT IT CANNOT MEASURE is semantic recall. A hashed n-gram encoder has no
# notion that "maize" means "corn" or that "LGU" means a local government
# unit, so ANY recall improvement it shows is lexical, and any recall it
# fails to show is not evidence against a real multilingual encoder. Every
# number this mode prints is labelled MOCK for that reason, and the
# live-provider benchmark is deferred to staging per spec section 56.
#
# Set RETRIEVAL_EMBEDDING_ENABLED / _URL / _MODEL and pass --live to run
# the same comparison against a real endpoint.

suppressWarnings(suppressMessages({
  for (f in sort(list.files("R", pattern = "[.]R$", recursive = TRUE, full.names = TRUE))) {
    if (!grepl("^R/ui/", f)) source(f)
  }
}))

args <- commandArgs(trailingOnly = TRUE)
flags <- args[grepl("^--", args)]
positional <- args[!grepl("^--", args)]

semantic_mode <- "--semantic" %in% flags
live_mode <- "--live" %in% flags

profile <- if (length(positional) >= 1L && nzchar(positional[1])) positional[1] else "current"
corpus_path <- if (length(positional) >= 2L && nzchar(positional[2])) positional[2] else NULL
# In --semantic mode the first positional is the corpus, not a profile:
# there is only one engine under comparison and naming a profile would be
# meaningless.
if (semantic_mode && length(positional) >= 1L && file.exists(positional[1])) {
  corpus_path <- positional[1]
  profile <- "current"
}
if (semantic_mode && is.null(corpus_path)) {
  default_semantic <- "data-raw/retrieval_semantic_eval_cases.csv"
  if (file.exists(default_semantic)) corpus_path <- default_semantic
}

# Recall cut-offs. Section 36 asks for @1/@5/@10; @3 is retained because
# the pre-existing hybrid milestone reports it.
EVAL_K <- c(1L, 3L, 5L, 10L)
EVAL_LIMIT <- 50L

resolve_search_fn <- function(profile) {
  if (identical(profile, "current")) return(retrieval_eval_default_search_fn)
  if (identical(profile, "baseline")) return(retrieval_eval_legacy_search_fn)
  if (exists("retrieval_search_fn_for_profile", mode = "function")) {
    fn <- get("retrieval_search_fn_for_profile", mode = "function")(profile)
    if (is.function(fn)) return(fn)
  }
  stop(sprintf(
    paste0("Unknown retrieval profile '%s'. Known profiles: current, baseline. ",
           "Any other profile must be exposed as ",
           "retrieval_search_fn_for_profile(profile)."),
    profile
  ), call. = FALSE)
}

fmt_pct <- function(x) if (is.na(x)) "    n/a" else sprintf("%6.1f%%", 100 * x)
fmt_num <- function(x) if (is.na(x)) "    n/a" else sprintf("%7.3f", x)
fmt_ms  <- function(x) if (is.na(x)) "    n/a" else sprintf("%6.1fms", x)
fmt_delta <- function(a, b) {
  if (is.na(a) || is.na(b)) return("      .")
  d <- b - a
  if (abs(d) < 1e-12) return("       0")
  sprintf("%+7.1f", 100 * d)
}

rule <- function(ch = "-", n = 78) cat(strrep(ch, n), "\n", sep = "")

# ---------------------------------------------------------------------
# The deterministic offline stand-in encoder
# ---------------------------------------------------------------------
#
# A hashed character-n-gram bag. Character n-grams rather than word tokens
# so that morphology and misspelling produce partially overlapping vectors
# rather than orthogonal ones -- otherwise the mock index would contribute
# strictly less than the existing n-gram tier and the comparison would be
# uninformative by construction.
#
# Deterministic: the same text always maps to the same vector, in this
# process and the next. No RNG, no seed to remember.
mock_embedder <- function(dim = 256L, n = 4L) {
  force(dim); force(n)
  function(texts) {
    texts <- as.character(texts)
    texts[is.na(texts)] <- ""
    m <- matrix(0, nrow = length(texts), ncol = dim)
    for (i in seq_along(texts)) {
      s <- texts[i]
      if (!nzchar(s)) { m[i, 1L] <- 1; next }
      s <- paste0(" ", s, " ")
      cps <- utf8ToInt(s)
      len <- length(cps)
      if (len < n) { m[i, (sum(cps) %% dim) + 1L] <- 1; next }
      # Rolling polynomial hash over character n-grams.
      for (p in seq_len(len - n + 1L)) {
        g <- cps[p:(p + n - 1L)]
        h <- 0
        for (c in g) h <- (h * 131 + c) %% 1048573
        b <- (h %% dim) + 1L
        m[i, b] <- m[i, b] + 1
      }
    }
    m
  }
}

# ---------------------------------------------------------------------
# The ORACLE encoder: an upper bound, not a benchmark
# ---------------------------------------------------------------------
#
# A PERFECT encoder. Every document gets a deterministic near-orthogonal
# unit vector, and every evaluation query is mapped exactly onto the vector
# of the document the corpus says is correct. Cosine is then 1.000 for the
# right row and ~0 for every other, so the semantic tier returns the
# expected code at semantic rank 1 for every positive case.
#
# This exists to answer one question the mock encoder cannot:
#
#   IF the embedding model were flawless, would the surrounding retrieval
#   pipeline deliver the code?
#
# If recall does not move under the oracle, the bottleneck is downstream of
# the encoder -- in fusion, thresholding or gating -- and buying a better
# embedding model would change nothing. That is a structural finding, and
# it is worth far more than any mock recall number.
#
# ORACLE FIGURES ARE NOT ACHIEVABLE PERFORMANCE. No real encoder is
# perfect. Read them only as a ceiling.
.oracle_vec <- function(i, dim) {
  j <- seq_len(dim)
  # Deterministic, spread across the sphere, no RNG and no seed to carry.
  v <- sin(as.numeric(i) * 7919 + j * 104729) + cos(as.numeric(i) * 15485863 + j * 31)
  v / sqrt(sum(v * v))
}

oracle_embedder <- function(dim, doc_row, query_row) {
  force(dim); force(doc_row); force(query_row)
  function(texts) {
    texts <- as.character(texts)
    texts[is.na(texts)] <- ""
    m <- matrix(0, nrow = length(texts), ncol = dim)
    for (i in seq_along(texts)) {
      r <- doc_row[[texts[i]]]
      if (is.null(r)) r <- query_row[[texts[i]]]
      # An unmapped text (a negative case, or a query with no expected
      # code) gets a zero vector, which scores 0 against everything and
      # contributes no candidate. That is the correct oracle behaviour:
      # a perfect encoder does not invent a neighbour for nonsense.
      if (!is.null(r) && !is.na(r)) m[i, ] <- .oracle_vec(r, dim)
    }
    m
  }
}

# Build the two lookup tables the oracle needs, as hashed environments.
oracle_maps <- function(cases, system, version, data, docs) {
  doc_row <- new.env(hash = TRUE, parent = emptyenv())
  for (i in seq_along(docs$text)) assign(docs$text[i], i, envir = doc_row)

  query_row <- new.env(hash = TRUE, parent = emptyenv())
  sel <- which(cases$system == system & cases$version == version &
                 nzchar(cases$expected_code) & cases$must_find)
  for (i in sel) {
    r <- match(cases$expected_code[i], as.character(data$code))
    if (is.na(r)) next
    q <- retrieval_normalize(cases$query[i])
    if (is.na(q) || !nzchar(q)) next
    assign(q, r, envir = query_row)
  }
  list(doc_row = doc_row, query_row = query_row)
}

# ---------------------------------------------------------------------
# A search function with an explicitly controlled semantic tier
# ---------------------------------------------------------------------
#
# Mirrors `search_classification_result()`'s wiring (R/repository.R) but
# takes the embedding index from an argument instead of from disk, so OFF
# and ON differ in exactly one input.

eval_state <- new.env(parent = emptyenv())

# QUERY-TIME provider injection.
#
# `search_classification_data_result()` -> `retrieval_hybrid_candidates()`
# calls `retrieval_embeddings_candidates(query, index, top_k)` with no
# `embed_fn`, so at query time the tier goes through the real provider
# entry point, `retrieval_embed_texts()`. A benchmark that only injected an
# encoder at BUILD time would therefore embed the corpus with a stand-in
# and then fail to embed the query at all -- the semantic tier would look
# inert for a reason that has nothing to do with semantics.
#
# The stand-in is installed AT THE PROVIDER BOUNDARY instead, which is
# exactly where a real endpoint sits. Nothing in the engine is patched, and
# the production call path is exercised unchanged. `active$fn` is swapped
# per system so the oracle's per-system mapping stays correct.
embed_provider <- new.env(parent = emptyenv())
embed_provider$fn <- NULL

install_provider_shim <- function() {
  assign(
    "retrieval_embed_texts",
    function(texts, config = NULL) {
      f <- embed_provider$fn
      if (is.null(f)) return(NULL)
      f(texts)
    },
    envir = globalenv()
  )
  invisible(NULL)
}

# `arm` is one of "det" (no semantic tier), "mock", "live", "oracle". It is
# part of the cache key because otherwise whichever arm ran first would
# decide whether an embedding index exists, and the comparison would
# silently measure the same engine twice.
eval_prepare <- function(system, version, arm, embed_factory = NULL, config = NULL) {
  key <- paste(system, version, arm, sep = "::")
  if (!is.null(eval_state[[key]])) return(eval_state[[key]])

  data <- get_classification(system, version, level = NULL)
  corpus <- retrieval_corpus(data)
  ngram_index <- retrieval_index_for("ngram", system, version, corpus)

  st <- list(data = data, corpus = corpus, ngram_index = ngram_index,
             embedding_index = NULL, docs = NULL, arm = arm,
             build_secs = NA_real_, index_bytes = NA_real_,
             query_ms = NA_real_)

  if (!identical(arm, "det")) {
    docs <- retrieval_embedding_documents(data, system = system, version = version)
    embed_fn <- if (is.null(embed_factory)) NULL else embed_factory(system, version, data, docs)

    t0 <- Sys.time()
    index <- retrieval_embeddings_build(
      corpus, config = config, embed_fn = embed_fn, batch_size = 256L,
      data = data, system = system, version = version, documents = docs
    )
    st$build_secs <- as.numeric(difftime(Sys.time(), t0, units = "secs"))
    st$docs <- docs
    if (!is.null(index)) {
      # The same gate the application applies before trusting an artifact.
      if (!retrieval_embeddings_index_is_valid(index, corpus,
                                               system = system, version = version)) {
        cat(sprintf("  WARNING: built index for %s %s failed validation; treating as absent\n",
                    system, version))
        index <- NULL
      }
    }
    st$embedding_index <- index
    st$embed_fn <- embed_fn
    st$index_bytes <- if (is.null(index)) NA_real_ else as.numeric(utils::object.size(index))

    # Isolated semantic-query latency: index load is already paid, so this
    # is the per-query cost of embedding plus the brute-force cosine.
    if (!is.null(index)) {
      probe <- c("high school teacher", "maize farmer", "local government unit")
      t1 <- Sys.time()
      for (p in probe) {
        retrieval_semantic_search(p, index, top_k = 10L, system = system,
                                  version = version, embed_fn = embed_fn)
      }
      st$query_ms <- 1000 * as.numeric(difftime(Sys.time(), t1, units = "secs")) / length(probe)
    }
  }

  eval_state[[key]] <- st
  st
}

make_search_fn <- function(arm, embed_factory = NULL, config = NULL) {
  force(arm); force(embed_factory); force(config)
  function(system, version, query, limit = EVAL_LIMIT) {
    st <- eval_prepare(system, version, arm, embed_factory = embed_factory,
                       config = config)
    # Point the provider shim at this system's stand-in encoder before the
    # engine reaches the semantic tier. NULL for the live arm, which uses
    # the real provider, and for the deterministic arm, which has no index.
    embed_provider$fn <- if (identical(arm, "live")) NULL else st$embed_fn
    res <- search_classification_data_result(
      st$data, query, level = NULL, limit = limit, hybrid = TRUE,
      ngram_index = st$ngram_index,
      embedding_index = st$embedding_index,
      corpus = st$corpus
    )
    as.character(res$data$code)
  }
}

# ---------------------------------------------------------------------
# Reporting
# ---------------------------------------------------------------------

print_overall <- function(m, label) {
  cat(sprintf("\n%s\n", label))
  rule()
  cat(sprintf("  Recall@1          %s\n", fmt_pct(m$recall_at_1)))
  cat(sprintf("  Recall@3          %s\n", fmt_pct(m$recall_at_3)))
  cat(sprintf("  Recall@5          %s\n", fmt_pct(m$recall_at_5)))
  cat(sprintf("  Recall@10         %s\n", fmt_pct(m$recall_at_10)))
  cat(sprintf("  MRR               %s\n", fmt_num(m$mrr)))
  cat(sprintf("  Negative correct  %s\n", fmt_pct(m$negative_correct)))
  if (m$n_confusable_negative > 0L) {
    cat(sprintf("    confusable-negative correct  %s  (n=%d)\n",
                fmt_pct(m$confusable_negative_correct), m$n_confusable_negative))
  }
  if (m$n_true_no_code > 0L) {
    cat(sprintf("    true-no-code correct         %s  (n=%d)\n",
                fmt_pct(m$true_no_code_correct), m$n_true_no_code))
  }
  cat(sprintf("  Cases             %d  (%d positive / %d negative)\n",
              m$n_cases, m$n_positive, m$n_negative))
  cat(sprintf("  Engine errors     %d\n", m$n_errors))
  cat(sprintf("  Latency p50       %s\n", fmt_ms(m$latency_p50_ms)))
  cat(sprintf("  Latency p95       %s\n", fmt_ms(m$latency_p95_ms)))
}

print_breakdown <- function(pc, by, title) {
  tab <- retrieval_eval_breakdown(pc, by = by, k = EVAL_K)
  cat(sprintf("\n%s\n", title))
  rule()
  cat(sprintf("  %-32s %4s %8s %8s %8s %8s %8s\n",
              by, "n", "R@1", "R@5", "R@10", "MRR", "neg-ok"))
  for (i in seq_len(nrow(tab))) {
    cat(sprintf("  %-32s %4d %8s %8s %8s %8s %8s\n",
                tab$group[i], tab$n[i],
                fmt_pct(tab$recall_at_1[i]), fmt_pct(tab$recall_at_5[i]),
                fmt_pct(tab$recall_at_10[i]), fmt_num(tab$mrr[i]),
                fmt_pct(tab$negative_correct[i])))
  }
}

print_failures <- function(pc, title = "FAILING CASES") {
  failed <- pc[!pc$passed, , drop = FALSE]
  cat(sprintf("\n%s (%d)\n", title, nrow(failed)))
  rule()
  if (nrow(failed) == 0L) {
    cat("  none\n")
    return(invisible(NULL))
  }
  for (i in seq_len(nrow(failed))) {
    cat(sprintf("  %-14s %-8s %-34s expected=%-16s rank=%s%s\n",
                failed$case_id[i], failed$query_type[i],
                substr(failed$query[i], 1, 34),
                ifelse(nzchar(failed$expected_code[i]), failed$expected_code[i], "(none)"),
                ifelse(is.na(failed$rank[i]), "not found", as.character(failed$rank[i])),
                ifelse(is.na(failed$error[i]), "", paste0("  ERROR: ", failed$error[i]))))
  }
}

# `retrieval_eval_load_cases()` projects the corpus onto its own fixed
# column set, which is what keeps the loader stable. The semantic corpus
# carries one extra column, `category`, so it is read back here and joined
# on case_id rather than by changing that contract.
attach_category <- function(pc, path) {
  if (is.null(path) || !file.exists(path)) return(pc)
  raw <- tryCatch(
    utils::read.csv(path, colClasses = "character", stringsAsFactors = FALSE,
                    na.strings = NULL, encoding = "UTF-8"),
    error = function(e) NULL
  )
  if (is.null(raw) || !"category" %in% names(raw)) return(pc)
  pc$category <- raw$category[match(pc$case_id, raw$case_id)]
  pc$category[is.na(pc$category) | !nzchar(pc$category)] <- "(uncategorised)"
  pc
}

# ---------------------------------------------------------------------
# Semantic OFF vs ON
# ---------------------------------------------------------------------

run_semantic_comparison <- function(cases, corpus_path) {
  cfg <- retrieval_embedding_config()
  use_live <- live_mode && retrieval_embedding_available(cfg)
  install_provider_shim()

  if (live_mode && !use_live) {
    cat("\n  --live requested but no embedding endpoint is configured; ")
    cat("running the MOCK and ORACLE arms instead.\n")
  }

  arms <- list(
    list(key = "det", label = "OFF", desc = "no semantic tier",
         factory = NULL, config = NULL),
    list(key = "mock", label = "MOCK",
         desc = "deterministic hashed character-4-gram encoder, 256 dims",
         factory = function(system, version, data, docs) mock_embedder(dim = 256L, n = 4L),
         config = list(enabled = TRUE, url = "mock://local",
                       model = "mock-char4gram-256", timeout = 0, has_key = FALSE)),
    list(key = "oracle", label = "ORACLE",
         desc = "perfect encoder -- upper bound on what the pipeline can deliver",
         factory = function(system, version, data, docs) {
           maps <- oracle_maps(cases, system, version, data, docs)
           oracle_embedder(256L, maps$doc_row, maps$query_row)
         },
         config = list(enabled = TRUE, url = "oracle://local",
                       model = "oracle-upper-bound-256", timeout = 0, has_key = FALSE))
  )
  if (use_live) {
    arms <- c(arms, list(list(
      key = "live", label = "LIVE",
      desc = sprintf("real provider (%s)", retrieval_embedding_provider_id(cfg)),
      factory = NULL, config = cfg
    )))
  }

  rule("=")
  cat("SEMANTIC OFF vs ON\n")
  cat(sprintf("Corpus  : %s  |  cases: %d\n",
              if (is.null(corpus_path)) "data-raw/retrieval_eval_cases.csv" else corpus_path,
              nrow(cases)))
  cat(sprintf("Run     : %s\n", format(Sys.time(), "%Y-%m-%d %H:%M:%S")))
  for (a in arms) cat(sprintf("Arm     : %-7s %s\n", a$label, a$desc))
  rule("=")

  if (!use_live) {
    cat("\n  READ THIS BEFORE QUOTING ANY NUMBER BELOW.\n")
    cat("  MOCK has no semantics. It cannot know that 'maize' means 'corn' or that\n")
    cat("  'LGU' is a local government unit, so it measures the semantic PATH --\n")
    cat("  documents, schema, fusion, gating, latency, memory -- at full corpus\n")
    cat("  scale, and nothing about semantic recall.\n")
    cat("  ORACLE is not achievable performance either. It is a CEILING: the query\n")
    cat("  is placed exactly on the correct document's vector, so if recall still\n")
    cat("  does not move, the limit is the pipeline and not the encoder.\n")
    cat("  The live-provider benchmark is deferred to staging (spec section 56).\n")
  }

  runs <- list()
  for (a in arms) {
    retrieval_embedding_cache_reset()
    runs[[a$key]] <- retrieval_eval_run(
      cases,
      search_fn = make_search_fn(a$key, embed_factory = a$factory, config = a$config),
      k = EVAL_K, limit = EVAL_LIMIT
    )
  }
  embed_provider$fn <- NULL

  base <- runs[["det"]]$metrics
  labels <- vapply(arms, function(a) a$label, character(1))
  keys <- vapply(arms, function(a) a$key, character(1))

  cat("\nHEADLINE\n")
  rule()
  cat(sprintf("  %-24s", "metric"))
  for (l in labels) cat(sprintf(" %10s", l))
  cat("\n")
  metric_row <- function(name, key, fmt = fmt_pct) {
    cat(sprintf("  %-24s", name))
    for (k in keys) cat(sprintf(" %10s", fmt(runs[[k]]$metrics[[key]])))
    cat("\n")
  }
  metric_row("Recall@1", "recall_at_1")
  metric_row("Recall@5", "recall_at_5")
  metric_row("Recall@10", "recall_at_10")
  metric_row("MRR", "mrr", fmt_num)
  metric_row("Negative correct", "negative_correct")
  metric_row("  confusable-negative", "confusable_negative_correct")
  metric_row("  true-no-code", "true_no_code_correct")
  metric_row("Latency p50", "latency_p50_ms", fmt_ms)
  metric_row("Latency p95", "latency_p95_ms", fmt_ms)

  cat("\n  Deltas vs OFF, in percentage points:\n")
  for (k in keys[-1]) {
    m <- runs[[k]]$metrics
    cat(sprintf("    %-8s R@1 %s   R@5 %s   R@10 %s   MRR %s   neg %s\n",
                k,
                fmt_delta(base$recall_at_1, m$recall_at_1),
                fmt_delta(base$recall_at_5, m$recall_at_5),
                fmt_delta(base$recall_at_10, m$recall_at_10),
                fmt_delta(base$mrr, m$mrr),
                fmt_delta(base$negative_correct, m$negative_correct)))
  }

  # Index cost, measured rather than assumed.
  cat("\nSEMANTIC INDEX COST (measured)\n")
  rule()
  cat(sprintf("  %-22s %7s %5s %9s %10s %11s %11s\n",
              "system::arm", "docs", "dim", "build s", "index MB", "doc chars", "query ms"))
  for (key in sort(ls(eval_state))) {
    st <- eval_state[[key]]
    if (is.null(st$embedding_index)) next
    idx <- st$embedding_index
    cat(sprintf("  %-22s %7d %5d %9.2f %10.2f %11d %11.2f\n",
                key, idx$n_docs, idx$dim, st$build_secs,
                st$index_bytes / 1024^2,
                as.integer(stats::median(nchar(st$docs$text))),
                st$query_ms))
  }

  # Category movement: where the tier helped and where it hurt.
  pcs <- lapply(runs, function(r) attach_category(r$per_case, corpus_path))
  if ("category" %in% names(pcs[["det"]])) {
    cat("\nBY CATEGORY  (spec section 33)  -- Recall@5 per arm\n")
    rule()
    cat(sprintf("  %-24s %4s", "category", "n"))
    for (l in labels) cat(sprintf(" %9s", l))
    cat("\n")
    for (g in sort(unique(pcs[["det"]]$category))) {
      n_g <- sum(pcs[["det"]]$category == g)
      cat(sprintf("  %-24s %4d", g, n_g))
      for (k in keys) {
        sub <- pcs[[k]][pcs[[k]]$category == g, , drop = FALSE]
        mm <- retrieval_eval_metrics(sub, k = EVAL_K)
        val <- if (is.na(mm$recall_at_5)) mm$negative_correct else mm$recall_at_5
        cat(sprintf(" %9s", fmt_pct(val)))
      }
      cat("\n")
    }
    cat("  (negative-only categories show negative-correct instead of Recall@5)\n")
  }

  # Per-case movement is the honest place to look: an unchanged headline
  # can hide equal numbers of gains and losses.
  for (k in keys[-1]) {
    a_pc <- pcs[["det"]]; b_pc <- pcs[[k]]
    moved <- which(a_pc$passed != b_pc$passed |
                     (!is.na(a_pc$rank) != !is.na(b_pc$rank)) |
                     (!is.na(a_pc$rank) & !is.na(b_pc$rank) & a_pc$rank != b_pc$rank))
    cat(sprintf("\nOFF -> %s : CASES WHOSE RANK OR OUTCOME MOVED (%d of %d)\n",
                toupper(k), length(moved), nrow(a_pc)))
    rule()
    if (!length(moved)) {
      cat("  none -- the semantic tier changed no ranking on this corpus\n")
    } else {
      for (i in moved) {
        cat(sprintf("  %-12s %-34s OFF rank=%-9s %s rank=%-9s %s\n",
                    a_pc$case_id[i], substr(a_pc$query[i], 1, 34),
                    ifelse(is.na(a_pc$rank[i]), "none", as.character(a_pc$rank[i])),
                    toupper(k),
                    ifelse(is.na(b_pc$rank[i]), "none", as.character(b_pc$rank[i])),
                    if (a_pc$passed[i] && !b_pc$passed[i]) "REGRESSION"
                    else if (!a_pc$passed[i] && b_pc$passed[i]) "gain" else ""))
      }
    }
  }

  print_overall(base, "SEMANTIC OFF -- full metrics")
  print_failures(runs[["det"]]$per_case, "SEMANTIC OFF -- failing cases")

  cat("\nACCEPTANCE (spec section 38)\n")
  rule()
  best_key <- if (use_live) "live" else "mock"
  b <- runs[[best_key]]$metrics
  o <- runs[["oracle"]]$metrics
  gain <- !is.na(b$recall_at_5) && !is.na(base$recall_at_5) && b$recall_at_5 > base$recall_at_5
  safe <- (is.na(base$negative_correct) || is.na(b$negative_correct) ||
             b$negative_correct >= base$negative_correct)
  oracle_gain <- !is.na(o$recall_at_5) && !is.na(base$recall_at_5) &&
    o$recall_at_5 > base$recall_at_5
  cat(sprintf("  recall improved (%s)     : %s\n", best_key, if (gain) "yes" else "no"))
  cat(sprintf("  negative safety preserved  : %s\n", if (safe) "yes" else "NO -- BLOCKING"))
  cat(sprintf("  oracle ceiling above OFF   : %s\n", if (oracle_gain) "yes" else "NO"))
  if (!oracle_gain) {
    cat("\n  STRUCTURAL FINDING. A PERFECT encoder moved nothing. The semantic tier\n")
    cat("  cannot contribute through the current pipeline, so no embedding model,\n")
    cat("  however good, would change these numbers. Fix the pipeline before\n")
    cat("  procuring an encoder.\n")
  }
  cat(sprintf("  verdict                    : %s\n",
              if (!oracle_gain) "BLOCKED -- pipeline, not encoder"
              else if (!use_live) "INCONCLUSIVE -- mock encoder cannot demonstrate semantic recall"
              else if (gain && safe) "semantic ON is a candidate for enablement"
              else "keep semantic OFF"))
  cat("\n  Default remains RETRIEVAL_EMBEDDING_ENABLED=false regardless of the\n")
  cat("  numbers above. Section 38 forbids enabling on a recall gain alone.\n\n")

  invisible(runs)
}

# ---------------------------------------------------------------------
# Single-profile run (the original behaviour)
# ---------------------------------------------------------------------

run_single_profile <- function(cases, corpus_path, profile) {
  search_fn <- resolve_search_fn(profile)

  rule("=")
  cat(sprintf("Retrieval evaluation  |  profile: %s  |  cases: %d\n", profile, nrow(cases)))
  cat(sprintf("Corpus: %s  |  run: %s\n",
              if (is.null(corpus_path)) "data-raw/retrieval_eval_cases.csv" else corpus_path,
              format(Sys.time(), "%Y-%m-%d %H:%M:%S")))
  rule("=")

  result <- retrieval_eval_run(cases, search_fn = search_fn, k = EVAL_K,
                               limit = EVAL_LIMIT)
  pc <- attach_category(result$per_case, corpus_path)

  print_overall(result$metrics, "OVERALL")
  print_breakdown(pc, "query_type", "BY QUERY TYPE")
  print_breakdown(pc, "language", "BY LANGUAGE")
  print_breakdown(pc, "system", "BY SYSTEM")
  if ("category" %in% names(pc)) print_breakdown(pc, "category", "BY CATEGORY (spec section 33)")
  print_failures(pc)

  errs <- pc[!is.na(pc$error), , drop = FALSE]
  if (nrow(errs)) {
    cat(sprintf("\nENGINE ERRORS (%d)\n", nrow(errs)))
    rule()
    for (i in seq_len(nrow(errs))) {
      cat(sprintf("  %-14s %s\n", errs$case_id[i], errs$error[i]))
    }
  }

  cat("\n")
  invisible(result)
}

cases <- retrieval_eval_load_cases(corpus_path)

result <- if (semantic_mode) {
  run_semantic_comparison(cases, corpus_path)
} else {
  run_single_profile(cases, corpus_path, profile)
}

invisible(result)
