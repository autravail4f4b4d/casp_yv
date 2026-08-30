# Build-time construction of the OPTIONAL semantic retrieval index.
#
# Invoke from the repository root:
#   Rscript scripts/build_retrieval_embeddings.R
#   Rscript scripts/build_retrieval_embeddings.R psoc psic
#   Rscript scripts/build_retrieval_embeddings.R --dry-run     # documents only
#
# OUTPUT
# -----------------------------------------------------------------
#   data/retrieval_embeddings_<system>_<version>.rds
#
# System and version come from `classification_registry()`, exactly as in
# scripts/build_retrieval_ngram_index.R, so the artifact filename matches
# the one `retrieval_index_get("embeddings", system, version)` looks for at
# runtime. Deriving them from a data/ filename instead would produce
# `..._ptscs_2025_v2_1.rds` where the runtime asks for
# `..._ptscs_2025-v2.1.rds`, and the index would silently never load.
#
# This script is a no-op unless an operator has configured an embedding
# endpoint (see R/retrieval/retrieval_embedding_provider.R for the
# environment contract). With no endpoint it prints a notice and exits 0:
# an unconfigured semantic tier is a supported, expected state, not a
# build failure, and CI must not go red because an optional tier is off.
#
# `--dry-run` needs no endpoint. It constructs and reports the SEMANTIC
# DOCUMENTS and their provenance without embedding anything, which is how
# a document-recipe change is reviewed before any provider is paid.
#
# NO MOCK ARTIFACT IS EVER WRITTEN HERE. A deterministic stand-in encoder
# is useful for benchmarking (see scripts/evaluate_retrieval.R, which
# builds one in memory) but an .rds under data/ is loaded by the running
# application, and a fake semantic tier that looks real to the app is
# exactly the silent-substitution failure the classification rules forbid.
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

# Batch size for provider calls. Small enough to stay under typical
# request-body and per-request token limits on hosted endpoints.
BUILD_EMBEDDING_BATCH <- 64L

# Overridable so a dry run can be pointed at a scratch directory without
# writing into the repository's data/ artifacts.
RETRIEVAL_EMBEDDING_OUTPUT_DIR <- Sys.getenv("RETRIEVAL_EMBEDDING_OUTPUT_DIR", "data")

msg <- function(...) cat(..., "\n", sep = "")

# Same loader as scripts/build_retrieval_ngram_index.R: source the non-UI
# service layer so the canonical repository is reachable without starting
# Shiny. The PSA survey-guidance constants under R/assistant/ come along
# with it, which is what lets the PSOC and PSIC recipes use them.
load_application <- function() {
  if (exists("get_classification", mode = "function")) return(invisible(NULL))
  for (f in sort(list.files("R", pattern = "[.]R$", recursive = TRUE,
                            full.names = TRUE))) {
    if (!grepl("^R/ui/", f)) source(f)
  }
  for (fn in c("get_classification", "classification_registry", "retrieval_corpus",
               "retrieval_embedding_documents", "retrieval_embeddings_build",
               "retrieval_embeddings_index_is_valid")) {
    if (!exists(fn, mode = "function")) {
      stop("[build_retrieval_embeddings] Required function ", fn,
           "() is unavailable after sourcing R/.", call. = FALSE)
    }
  }
  invisible(NULL)
}

output_path_for <- function(system, version) {
  file.path(RETRIEVAL_EMBEDDING_OUTPUT_DIR,
            sprintf("retrieval_embeddings_%s_%s.rds", system, version))
}

# Current editions only, from the registry -- the same target set the
# n-gram builder uses, so the two index families never disagree about
# which edition is indexed.
embedding_targets <- function(filter = character(0)) {
  reg <- classification_registry()
  out <- lapply(seq_len(nrow(reg)), function(i) {
    list(system = reg$id[[i]], version = reg$current_version[[i]])
  })
  if (length(filter)) {
    out <- Filter(function(t) t$system %in% filter, out)
  }
  out
}

# A compact report of what the recipe actually found, printed for every
# build and every dry run. Coverage is the review surface: if
# `survey_guidance` reads 0 on PSOC, the guidance constants were not
# loaded, and the document recipe silently degraded to label + hierarchy.
report_documents <- function(system, version, docs) {
  p <- docs$provenance
  n <- length(docs$text)
  pct <- function(x) if (n == 0L) "  n/a" else sprintf("%5.1f%%", 100 * sum(x) / n)
  chars <- nchar(docs$text)

  msg("    recipe            : ", docs$recipe, " v", docs$doc_recipe_version)
  msg("    documents         : ", n)
  msg("    chars  median/max : ", stats::median(chars), " / ", max(chars))
  if (is.data.frame(p) && nrow(p) == n && n > 0L) {
    msg("    current label     : ", pct(p$current_label_used))
    msg("    description       : ", pct(p$current_description_used))
    msg("    hierarchy parent  : ", pct(p$hierarchy_used))
    msg("    level             : ", pct(p$classification_level_used))
    msg("    survey guidance   : ", pct(p$survey_guidance_used),
        "  (", sum(p$survey_guidance_used), " rows)")
    msg("    curated terms     : ", pct(p$curated_terminology_used),
        "  (", sum(p$curated_terminology_used), " rows)")
    msg("    historical text   : ", pct(p$historical_activity_text_used),
        "  (", sum(p$historical_activity_text_used), " rows, code NEVER carried)")
  }
}

main <- function() {
  args <- commandArgs(trailingOnly = TRUE)
  dry_run <- any(args %in% c("--dry-run", "-n"))
  filter <- args[!grepl("^-", args)]

  load_application()
  cfg <- retrieval_embedding_config()

  msg("Retrieval semantic index build")
  msg("  enabled  : ", cfg$enabled)
  msg("  provider : ", {
    id <- retrieval_embedding_provider_id(cfg)
    if (nzchar(id)) id else "<unset>"
  })
  msg("  api key  : ", if (cfg$has_key) "present" else "absent")  # value never printed
  msg("  timeout  : ", cfg$timeout, "s")
  msg("  schema   : index v", RETRIEVAL_EMBEDDING_INDEX_VERSION,
      " / doc recipe v", RETRIEVAL_EMBEDDING_DOC_RECIPE_VERSION)
  msg("  mode     : ", if (dry_run) "dry run (documents only, no embeddings)" else "build")

  if (!dry_run && !retrieval_embedding_available(cfg)) {
    msg("")
    msg("Semantic tier not configured; skipping.")
    msg("Set RETRIEVAL_EMBEDDING_ENABLED=true plus RETRIEVAL_EMBEDDING_URL and")
    msg("RETRIEVAL_EMBEDDING_MODEL to build the optional semantic index.")
    msg("Run with --dry-run to review the semantic documents without a provider.")
    msg("Hybrid retrieval will continue to run on its lexical, fuzzy and")
    msg("n-gram tiers. This is not an error.")
    return(invisible(0L))
  }

  targets <- embedding_targets(filter)
  if (length(targets) == 0L) {
    msg("No registered classification systems matched; nothing to do.")
    return(invisible(0L))
  }

  built <- 0L
  for (t in targets) {
    msg("")
    msg("  --- ", t$system, " ", t$version, " ---")

    data <- tryCatch(get_classification(t$system, t$version), error = function(e) NULL)
    if (is.null(data) || nrow(data) == 0L) {
      msg("    skip: get_classification() returned no rows")
      next
    }

    corpus <- retrieval_corpus(data)
    if (corpus$n == 0L) {
      msg("    skip: empty corpus")
      next
    }

    docs <- retrieval_embedding_documents(data, system = t$system, version = t$version)
    report_documents(t$system, t$version, docs)
    if (dry_run) next

    msg("    embedding ", corpus$n, " documents ...")
    index <- retrieval_embeddings_build(
      corpus, config = cfg, batch_size = BUILD_EMBEDDING_BATCH,
      data = data, system = t$system, version = t$version, documents = docs
    )

    if (is.null(index)) {
      # A failed build leaves any existing artifact untouched. Writing a
      # partial or empty index would be worse than having none.
      msg("    FAILED: provider returned no usable embeddings; ",
          "existing artifact (if any) left unchanged")
      next
    }

    # Verify before writing, and again after reloading. A stale or
    # misaligned index resolves candidates to the wrong canonical records
    # with full confidence, so it must never reach data/ unchecked.
    if (!retrieval_embeddings_index_is_valid(index, corpus,
                                             system = t$system, version = t$version)) {
      msg("    FAILED: freshly built index does not validate against its own corpus")
      next
    }

    out_path <- output_path_for(t$system, t$version)
    saveRDS(index, out_path)

    reloaded <- retrieval_embeddings_load(out_path)
    if (is.null(reloaded) ||
        !retrieval_embeddings_index_is_valid(reloaded, corpus,
                                             system = t$system, version = t$version)) {
      msg("    FAILED: reloaded index does not validate; removing ", out_path)
      unlink(out_path)
      next
    }

    msg("    wrote ", out_path, "  (", index$n_docs, " x ", index$dim,
        ", model ", index$model, ", ",
        sprintf("%.1f MB", file.info(out_path)$size / 1024^2), ")")
    built <- built + 1L
  }

  msg("")
  if (dry_run) {
    msg("Dry run complete. No embeddings requested, no artifact written.")
  } else {
    msg("Done. ", built, " semantic index artifact(s) written.")
  }
  invisible(0L)
}

if (identical(environment(), globalenv())) {
  main()
}
