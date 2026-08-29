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

suppressWarnings(suppressMessages({
  for (f in sort(list.files("R", pattern = "[.]R$", recursive = TRUE, full.names = TRUE))) {
    if (!grepl("^R/ui/", f)) source(f)
  }
}))

args <- commandArgs(trailingOnly = TRUE)
profile <- if (length(args) >= 1L && nzchar(args[1])) args[1] else "current"
corpus_path <- if (length(args) >= 2L && nzchar(args[2])) args[2] else NULL

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

rule <- function(ch = "-", n = 78) cat(strrep(ch, n), "\n", sep = "")

cases <- retrieval_eval_load_cases(corpus_path)
search_fn <- resolve_search_fn(profile)

rule("=")
cat(sprintf("Retrieval evaluation  |  profile: %s  |  cases: %d\n", profile, nrow(cases)))
cat(sprintf("Corpus: %s  |  run: %s\n",
            if (is.null(corpus_path)) "data-raw/retrieval_eval_cases.csv" else corpus_path,
            format(Sys.time(), "%Y-%m-%d %H:%M:%S")))
rule("=")

result <- retrieval_eval_run(cases, search_fn = search_fn, k = c(1L, 3L, 5L))
m <- result$metrics
pc <- result$per_case

cat("\nOVERALL\n")
rule()
cat(sprintf("  Recall@1          %s\n", fmt_pct(m$recall_at_1)))
cat(sprintf("  Recall@3          %s\n", fmt_pct(m$recall_at_3)))
cat(sprintf("  Recall@5          %s\n", fmt_pct(m$recall_at_5)))
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

print_breakdown <- function(by, title) {
  tab <- retrieval_eval_breakdown(pc, by = by, k = c(1L, 3L, 5L))
  cat(sprintf("\n%s\n", title))
  rule()
  cat(sprintf("  %-32s %4s %8s %8s %8s %8s %8s\n",
              by, "n", "R@1", "R@3", "R@5", "MRR", "neg-ok"))
  for (i in seq_len(nrow(tab))) {
    cat(sprintf("  %-32s %4d %8s %8s %8s %8s %8s\n",
                tab$group[i], tab$n[i],
                fmt_pct(tab$recall_at_1[i]), fmt_pct(tab$recall_at_3[i]),
                fmt_pct(tab$recall_at_5[i]), fmt_num(tab$mrr[i]),
                fmt_pct(tab$negative_correct[i])))
  }
}

print_breakdown("query_type", "BY QUERY TYPE")
print_breakdown("language", "BY LANGUAGE")
print_breakdown("system", "BY SYSTEM")

failed <- pc[!pc$passed, , drop = FALSE]
cat(sprintf("\nFAILING CASES (%d)\n", nrow(failed)))
rule()
if (nrow(failed) == 0L) {
  cat("  none\n")
} else {
  for (i in seq_len(nrow(failed))) {
    cat(sprintf("  %-14s %-8s %-30s expected=%-16s rank=%s%s\n",
                failed$case_id[i], failed$query_type[i],
                substr(failed$query[i], 1, 30),
                ifelse(nzchar(failed$expected_code[i]), failed$expected_code[i], "(none)"),
                ifelse(is.na(failed$rank[i]), "not found", as.character(failed$rank[i])),
                ifelse(is.na(failed$error[i]), "", paste0("  ERROR: ", failed$error[i]))))
  }
}

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
