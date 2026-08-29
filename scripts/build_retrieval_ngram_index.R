# Build-time construction of the character n-gram TF-IDF retrieval indexes.
#
# Invoke from the repository root:
#   Rscript scripts/build_retrieval_ngram_index.R
#
# OUTPUTS
# -----------------------------------------------------------------
#   data/retrieval_ngram_<system>_<version>.rds
#
# Each artifact is a "retrieval_ngram_index" (see R/retrieval/retrieval_ngram.R)
# built over `retrieval_corpus(get_classification(system, version))`.
#
# WHY THIS IS A BUILD STEP AT ALL
# -----------------------------------------------------------------
# Indexing the 24,180-row PSCC corpus cuts 2.3 M gram instances and sorts
# them. That is seconds of work -- perfectly fine once, unacceptable on a
# Shiny session start and unthinkable per keystroke. The query function
# does no building, so the cost has to land here.
#
# STALENESS IS THE REAL HAZARD
# -----------------------------------------------------------------
# A retrieval index is a *derived* artifact whose `idx` values are row
# offsets into the canonical classification table. If the classification
# artifact is rebuilt and the index is not, those offsets silently point
# at different records and the application returns confidently wrong
# codes. Every index therefore carries a corpus fingerprint, this script
# verifies it immediately after building, and the runtime is expected to
# call `retrieval_ngram_index_is_valid()` before trusting a loaded index.
#
# Nothing here mutates canonical data: the corpus is a read-only
# projection and the classification artifacts are never written.
#
# FAILURE POLICY
# -----------------------------------------------------------------
# Each system is built inside tryCatch so one unavailable classification
# cannot abort the others -- a partial set of indexes is useful, and the
# retrieval layer is expected to degrade to its other tiers where an index
# is missing. The script still exits non-zero if anything failed, so CI
# does not read a partial build as a success.

# ---------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------

# system / version pairs to index. Current editions only: archived
# editions are served by the deterministic tiers and do not justify the
# artifact weight until the hybrid tier is actually wired to them.
#
# EVERY registered system's current edition is indexed, not a hand-picked
# subset. The n-gram tier is the cheap one (2-3ms per query even on the
# 24,180-row PSCC index); the expensive edit-distance tier is skipped on a
# large corpus only WHEN an n-gram index exists to cover it. So a system
# without an index is the slow case, not the fast one -- PSGC measured
# +352ms per query unindexed versus roughly zero once indexed. Indexing
# everything is both faster and more uniform than choosing favourites.
# A function, not a constant: the registry is only callable after the R/
# files have been sourced, which happens further down in this script.
retrieval_ngram_targets <- function() {
  reg <- classification_registry()
  lapply(seq_len(nrow(reg)), function(i) {
    list(system = reg$id[[i]], version = reg$current_version[[i]])
  })
}

# Overridable so a dry run can be pointed at a scratch directory without
# writing into the repository's data/ artifacts.
RETRIEVAL_NGRAM_OUTPUT_DIR <- Sys.getenv("RETRIEVAL_NGRAM_OUTPUT_DIR", "data")

# A smoke query per system, used only to prove the built index answers.
# These are ordinary user phrasings, not assertions about correct codes --
# this script never validates a classification result.
RETRIEVAL_NGRAM_SMOKE <- c(
  psoc = "heavy truck driver",
  psic = "retail sale of rice",
  pscc = "fresh banana"
)

log_step <- function(...) cat("[build_retrieval_ngram_index] ", ..., "\n", sep = "")

fail <- function(...) stop(paste0("[build_retrieval_ngram_index] ", ...), call. = FALSE)

# ---------------------------------------------------------------------
# Application code
# ---------------------------------------------------------------------

# Same loader as scripts/build_assistant_assets.R: source the non-UI
# service layer so the canonical repository is reachable without starting
# Shiny.
load_application <- function() {
  if (exists("get_classification", mode = "function")) return(invisible(NULL))
  for (f in sort(list.files("R", pattern = "[.]R$", recursive = TRUE,
                            full.names = TRUE))) {
    if (!grepl("^R/ui/", f)) source(f)
  }
  for (fn in c("get_classification", "retrieval_corpus", "retrieval_ngram_build",
               "retrieval_ngram_index_is_valid", "retrieval_ngram_candidates")) {
    if (!exists(fn, mode = "function")) {
      fail("Required function ", fn, "() is unavailable after sourcing R/.")
    }
  }
  invisible(NULL)
}

output_path_for <- function(system, version) {
  file.path(RETRIEVAL_NGRAM_OUTPUT_DIR,
            sprintf("retrieval_ngram_%s_%s.rds", system, version))
}

# ---------------------------------------------------------------------
# Builder
# ---------------------------------------------------------------------

build_one <- function(system, version) {
  log_step("--- ", system, " ", version, " ---")

  started <- Sys.time()
  data <- get_classification(system, version)
  if (is.null(data) || nrow(data) == 0L) {
    fail("get_classification('", system, "', '", version, "') returned no rows. ",
         "An index over an empty corpus would be useless -- fix the artifact first.")
  }
  corpus <- retrieval_corpus(data)
  corpus_secs <- as.numeric(difftime(Sys.time(), started, units = "secs"))

  index_started <- Sys.time()
  index <- retrieval_ngram_build(corpus, system = system, version = version)
  build_secs <- as.numeric(difftime(Sys.time(), index_started, units = "secs"))

  # The fingerprint must match the corpus it was just built from. If this
  # fails the checksum is broken, and a broken staleness check is worse
  # than no staleness check.
  if (!retrieval_ngram_index_is_valid(index, corpus)) {
    fail("The freshly built ", system, " ", version,
         " index does not validate against its own corpus.")
  }

  if (index$n_docs != nrow(data)) {
    fail("Index documents (", index$n_docs, ") != classification rows (",
         nrow(data), ").")
  }

  # Smoke query: proves the artifact answers, and gives the report a real
  # per-query timing rather than a claim.
  smoke <- unname(RETRIEVAL_NGRAM_SMOKE[system])
  query_secs <- NA_real_
  smoke_hits <- NA_integer_
  smoke_top <- NA_character_
  if (!is.na(smoke)) {
    q_started <- Sys.time()
    cand <- retrieval_ngram_candidates(smoke, index, top_k = 50L)
    query_secs <- as.numeric(difftime(Sys.time(), q_started, units = "secs"))
    smoke_hits <- nrow(cand)
    if (smoke_hits > 0L) {
      smoke_top <- sprintf("%s  %s  (cos %.3f)",
                           data$code[cand$idx[[1L]]],
                           data$label[cand$idx[[1L]]],
                           cand$score[[1L]])
    }
  }

  path <- output_path_for(system, version)
  dir.create(dirname(path), showWarnings = FALSE, recursive = TRUE)
  save_started <- Sys.time()
  saveRDS(index, path)
  save_secs <- as.numeric(difftime(Sys.time(), save_started, units = "secs"))

  load_started <- Sys.time()
  reloaded <- readRDS(path)
  load_secs <- as.numeric(difftime(Sys.time(), load_started, units = "secs"))
  if (!retrieval_ngram_index_is_valid(reloaded, corpus)) {
    fail("The reloaded ", system, " ", version, " index does not validate. ",
         "Serialization lost something.")
  }

  bytes <- file.size(path)
  mem_bytes <- as.numeric(utils::object.size(index))

  log_step("documents        : ", index$n_docs)
  log_step("grams (", index$n_min, "-", index$n_max, ")     : ", index$n_grams)
  log_step("postings         : ", index$n_postings,
           "  (", sprintf("%.1f", index$n_postings / index$n_docs),
           " per document)")
  log_step("density          : ",
           sprintf("%.4f%%", 100 * index$n_postings /
                     (as.numeric(index$n_docs) * index$n_grams)),
           " of a dense doc x gram matrix")
  log_step("corpus build     : ", sprintf("%.2f s", corpus_secs))
  log_step("index build      : ", sprintf("%.2f s", build_secs))
  log_step("smoke query      : ", if (is.na(smoke)) "(none)" else
    sprintf("'%s' -> %d hit(s) in %.1f ms", smoke, smoke_hits, 1000 * query_secs))
  if (!is.na(smoke_top)) log_step("  top candidate  : ", smoke_top)
  log_step("in-memory size   : ", format(bytes_human(mem_bytes)))
  log_step("wrote ", path, " (", bytes, " bytes, ", bytes_human(bytes), ")")
  log_step("  save ", sprintf("%.2f s", save_secs),
           " / load ", sprintf("%.2f s", load_secs))

  invisible(list(
    system = system, version = version, path = path,
    n_docs = index$n_docs, n_grams = index$n_grams,
    n_postings = index$n_postings,
    bytes = bytes, mem_bytes = mem_bytes,
    corpus_secs = corpus_secs, build_secs = build_secs,
    query_secs = query_secs, load_secs = load_secs
  ))
}

bytes_human <- function(n) {
  if (!is.finite(n)) return("NA")
  units <- c("B", "KB", "MB", "GB")
  i <- 1L
  while (n >= 1024 && i < length(units)) {
    n <- n / 1024
    i <- i + 1L
  }
  sprintf("%.1f %s", n, units[i])
}

# ---------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------

main <- function() {
  log_step("build started ", format(Sys.time(), "%Y-%m-%d %H:%M:%S"))
  if (!dir.exists("R")) {
    fail("Run this script from the repository root (expected R/ here). ",
         "Current working directory: ", getwd())
  }
  load_application()
  log_step("output directory: ", RETRIEVAL_NGRAM_OUTPUT_DIR)
  targets <- retrieval_ngram_targets()

  results <- list()
  failures <- character(0)

  for (target in targets) {
    label <- paste(target$system, target$version)
    res <- tryCatch(
      build_one(target$system, target$version),
      error = function(e) {
        # One classification being unavailable must not cost the others
        # their index.
        cat("[build_retrieval_ngram_index] FAILED ", label, ": ",
            conditionMessage(e), "\n", sep = "")
        NULL
      }
    )
    if (is.null(res)) failures <- c(failures, label) else results[[label]] <- res
  }

  log_step("--- summary ---")
  if (length(results) > 0) {
    cat(sprintf(
      "  %-14s %9s %9s %11s %10s %9s %9s\n",
      "system", "n_docs", "n_grams", "n_postings", "bytes", "build_s", "query_ms"
    ))
    for (r in results) {
      cat(sprintf(
        "  %-14s %9d %9d %11d %10d %9.2f %9.1f\n",
        paste(r$system, r$version), r$n_docs, r$n_grams, r$n_postings,
        r$bytes, r$build_secs, 1000 * r$query_secs
      ))
    }
  }
  log_step("built ", length(results), "/", length(targets),
           " index/indexes")

  if (length(failures) > 0) {
    log_step("FAILED: ", paste(failures, collapse = ", "))
    quit(status = 1L, save = "no")
  }
  log_step("build finished OK")
  invisible(results)
}

if (sys.nframe() == 0L || identical(environment(), globalenv())) {
  main()
}
