# Build-time construction of the OPTIONAL semantic retrieval index.
#
# Invoke from the repository root:
#   Rscript scripts/build_retrieval_embeddings.R
#   Rscript scripts/build_retrieval_embeddings.R psoc_2022 psic_2026
#
# OUTPUT
# -----------------------------------------------------------------
#   data/retrieval_embeddings_<system>_<version>.rds
#
# This script is a no-op unless an operator has configured an embedding
# endpoint (see R/retrieval/retrieval_embedding_provider.R for the
# environment contract). With no endpoint it prints a notice and exits 0:
# an unconfigured semantic tier is a supported, expected state, not a
# build failure, and CI must not go red because an optional tier is off.
#
# The artifacts this writes are OPTIONAL runtime inputs. Search, Dual
# Search, PSIC Correspondence and RM all function without them.
#
# WHAT DEPLOYING THIS FOR REAL ACTUALLY REQUIRES
# -----------------------------------------------------------------
# There is no in-process embedding model and no Python runtime in this
# application, so "turning on semantic search" means standing up and
# operating an HTTP embedding service (self-hosted text-embeddings-
# inference / vLLM, or a managed embeddings API), pointing
# RETRIEVAL_EMBEDDING_URL at it, and re-running this script every time the
# classification data is rebuilt. That is a real operational commitment.
# Do not enable this tier before an evaluation shows it recovers queries
# the lexical + fuzzy + n-gram tiers actually miss.

suppressWarnings({
  source(file.path("R", "retrieval", "retrieval_normalize.R"))
  source(file.path("R", "retrieval", "retrieval_corpus.R"))
  source(file.path("R", "retrieval", "retrieval_embedding_provider.R"))
  source(file.path("R", "retrieval", "retrieval_embeddings.R"))
})

# Batch size for provider calls. Small enough to stay under typical
# request-body and per-request token limits on hosted endpoints.
BUILD_EMBEDDING_BATCH <- 64L

msg <- function(...) cat(..., "\n", sep = "")

# Canonical artifacts are read straight off disk rather than through the
# repository layer: this script must not depend on Shiny or on the app's
# startup path just to produce an optional artifact.
.discover_sources <- function(args) {
  if (length(args) > 0L) return(args)
  files <- list.files("data", pattern = "\\.rds$", full.names = FALSE)
  files <- files[!grepl("_metadata\\.rds$", files)]
  files <- files[!grepl("^(assistant_|retrieval_)", files)]
  sub("\\.rds$", "", files)
}

main <- function() {
  cfg <- retrieval_embedding_config()

  msg("Retrieval semantic index build")
  msg("  enabled : ", cfg$enabled)
  msg("  url     : ", if (nzchar(cfg$url)) cfg$url else "<unset>")
  msg("  model   : ", if (nzchar(cfg$model)) cfg$model else "<unset>")
  msg("  api key : ", if (cfg$has_key) "present" else "absent")  # value never printed
  msg("  timeout : ", cfg$timeout, "s")

  if (!retrieval_embedding_available(cfg)) {
    msg("")
    msg("Semantic tier not configured; skipping.")
    msg("Set RETRIEVAL_EMBEDDING_ENABLED=true plus RETRIEVAL_EMBEDDING_URL and")
    msg("RETRIEVAL_EMBEDDING_MODEL to build the optional semantic index.")
    msg("Hybrid retrieval will continue to run on its lexical, fuzzy and")
    msg("n-gram tiers. This is not an error.")
    return(invisible(0L))
  }

  sources <- .discover_sources(commandArgs(trailingOnly = TRUE))
  if (length(sources) == 0L) {
    msg("No canonical classification artifacts found under data/; nothing to do.")
    return(invisible(0L))
  }

  built <- 0L
  for (src in sources) {
    in_path <- file.path("data", paste0(src, ".rds"))
    if (!file.exists(in_path)) {
      msg("  skip ", src, ": ", in_path, " not found")
      next
    }

    data <- tryCatch(readRDS(in_path), error = function(e) NULL)
    if (is.null(data) || !is.data.frame(data) || !all(c("code", "label") %in% names(data))) {
      msg("  skip ", src, ": not a canonical classification table")
      next
    }

    corpus <- retrieval_corpus(data)
    if (corpus$n == 0L) {
      msg("  skip ", src, ": empty corpus")
      next
    }

    msg("  embedding ", src, " (", corpus$n, " documents) ...")
    index <- retrieval_embeddings_build(
      corpus, config = cfg, batch_size = BUILD_EMBEDDING_BATCH
    )

    if (is.null(index)) {
      # A failed build leaves any existing artifact untouched. Writing a
      # partial or empty index would be worse than having none.
      msg("  FAILED ", src, ": provider returned no usable embeddings; ",
          "existing artifact (if any) left unchanged")
      next
    }

    out_path <- file.path("data", paste0("retrieval_embeddings_", src, ".rds"))
    saveRDS(index, out_path)
    msg("  wrote ", out_path, "  (", index$n_docs, " x ", index$dim, ", model ",
        index$model, ")")
    built <- built + 1L
  }

  msg("")
  msg("Done. ", built, " semantic index artifact(s) written.")
  invisible(0L)
}

if (identical(environment(), globalenv())) {
  main()
}
