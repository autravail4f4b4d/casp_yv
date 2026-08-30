# The semantic/context evaluation corpus itself is an artifact under test.
#
# Covers sections 33, 34 and 35 of
# SEMANTIC_RETRIEVAL_AND_CONTEXT_CONSISTENCY_HARDENING.md.
#
# A retrieval benchmark is only as trustworthy as its answer key. The
# assertion that matters most here is that EVERY expected code names a row
# that actually exists in the current canonical edition -- a corpus with a
# fabricated or stale code would report a permanent, unfixable failure and
# would eventually be "fixed" by changing the engine to chase a code that
# was never real.

SEM_EVAL_PATHS <- c(
  "data-raw/retrieval_semantic_eval_cases.csv",
  "../../data-raw/retrieval_semantic_eval_cases.csv",
  "../data-raw/retrieval_semantic_eval_cases.csv"
)

sem_eval_path <- function() {
  for (p in SEM_EVAL_PATHS) if (file.exists(p)) return(p)
  NA_character_
}

sem_eval_raw <- function() {
  p <- sem_eval_path()
  utils::read.csv(p, colClasses = "character", stringsAsFactors = FALSE,
                  na.strings = NULL, encoding = "UTF-8")
}

# Spec section 33, verbatim.
SEM_EVAL_CATEGORIES <- c(
  "exact", "lexical_positive", "semantic_paraphrase", "multilingual_local",
  "context_disambiguation", "occupation_vs_industry", "activity_action",
  "education_level", "government_level", "agriculture", "batch_multi_input",
  "clarification", "outsourcing", "confusable_negative", "true_no_code"
)

test_that("there is exactly one semantic evaluation corpus, and it is findable", {
  expect_false(is.na(sem_eval_path()))

  # Section 5.4: no duplicate corpora. A second "final"/"v2"/"new" semantic
  # corpus is the failure mode this guards.
  root <- dirname(sem_eval_path())
  siblings <- list.files(root, pattern = "^retrieval_semantic.*\\.csv$")
  expect_identical(siblings, "retrieval_semantic_eval_cases.csv")
})

test_that("the corpus loads through the shared harness without special-casing", {
  cases <- retrieval_eval_load_cases(sem_eval_path())

  expect_true(is.data.frame(cases))
  expect_gt(nrow(cases), 60L)
  expect_identical(names(cases), RETRIEVAL_EVAL_COLUMNS)
  expect_type(cases$must_find, "logical")
  # Codes are strings. A numeric read would destroy "0112" and "01121".
  expect_type(cases$expected_code, "character")
})

test_that("every query type is one the harness already understands", {
  cases <- retrieval_eval_load_cases(sem_eval_path())
  expect_true(all(cases$query_type %in% RETRIEVAL_EVAL_QUERY_TYPES))
  expect_true(all(cases$language %in% RETRIEVAL_EVAL_LANGUAGES))
  expect_false(any(duplicated(cases$case_id)))
})

test_that("the corpus covers every section 33 category", {
  raw <- sem_eval_raw()
  expect_true("category" %in% names(raw))
  present <- unique(trimws(raw$category))

  missing <- setdiff(SEM_EVAL_CATEGORIES, present)
  expect_identical(missing, character(0),
                   info = paste("uncovered categories:", paste(missing, collapse = ", ")))

  # And no invented category that the spec does not name.
  extra <- setdiff(present, SEM_EVAL_CATEGORIES)
  expect_identical(extra, character(0),
                   info = paste("unrecognised categories:", paste(extra, collapse = ", ")))
})

test_that("negative cases are labelled consistently across both columns", {
  raw <- sem_eval_raw()
  cases <- retrieval_eval_load_cases(sem_eval_path())

  # confusable_negative names a REAL code that must not be returned.
  conf <- cases$query_type == "confusable_negative"
  expect_true(all(!cases$must_find[conf]))
  expect_true(all(nzchar(cases$expected_code[conf])))

  # negative_no_authoritative_code names no code at all.
  none <- cases$query_type == "negative_no_authoritative_code"
  expect_true(all(!cases$must_find[none]))
  expect_true(all(!nzchar(cases$expected_code[none])))

  # Every positive case names a code, or it measures nothing.
  expect_true(all(nzchar(cases$expected_code[cases$must_find])))
})

test_that("every expected code exists in the current canonical edition", {
  skip_if_not(exists("get_classification", mode = "function"))
  cases <- retrieval_eval_load_cases(sem_eval_path())
  named <- cases[nzchar(cases$expected_code), , drop = FALSE]
  expect_gt(nrow(named), 0L)

  for (key in unique(paste(named$system, named$version))) {
    parts <- strsplit(key, " ", fixed = TRUE)[[1]]
    data <- get_classification(parts[1], parts[2])
    sub <- named[named$system == parts[1] & named$version == parts[2], , drop = FALSE]

    hit <- match(sub$expected_code, as.character(data$code))
    bad <- sub$case_id[is.na(hit)]
    expect_identical(bad, character(0),
                     info = paste("codes absent from", key, ":", paste(bad, collapse = ", ")))

    # The recorded level must match the canonical row's own level, so a
    # case cannot quietly expect an aggregate where a detailed code lives.
    ok <- !is.na(hit) & nzchar(sub$expected_level)
    expect_identical(
      as.character(data$level)[hit[ok]], sub$expected_level[ok],
      info = paste("expected_level disagrees with the canonical row in", key)
    )
  }
})

test_that("the section 34 required positives are all present", {
  raw <- sem_eval_raw()
  q <- tolower(trimws(raw$query))

  required <- c(
    "teacher in a private high school", "high school teacher",
    "private high school", "private secondary school",
    "palay farmer", "palay farming", "growing paddy rice", "rice farming",
    "corn farmer", "corn farming", "growing corn", "maize farmer",
    "mayor", "city administrator", "city government",
    "local government unit", "lgu", "national government agency",
    "mananagat", "inland fisherman", "coastal fisherman", "deep-sea fisherman",
    "angkas driver", "grab taxi driver", "food panda bicycle driver",
    "online seller", "vulcanizer", "data scientist"
  )
  missing <- setdiff(required, q)
  expect_identical(missing, character(0),
                   info = paste("missing section 34 positives:",
                                paste(missing, collapse = ", ")))

  # "PSA" is section 34's remaining entry and is deliberately carried as a
  # clarification case, not a positive: a bare agency acronym is an
  # organisation name, not an activity. Its activity twin must exist too.
  expect_true("psa" %in% q)
  expect_true("philippine statistics authority" %in% q)
})

test_that("the section 35 confusable and nonsense negatives are all present", {
  raw <- sem_eval_raw()
  q <- tolower(trimws(raw$query))

  required <- c(
    "professional ai prompt engineer", "carpenter ant", "teacher's pet",
    "rice cooker technician", "corn dog vendor", "security blanket",
    "moon rock trading", "electrician's tape"
  )
  missing <- setdiff(required, q)
  expect_identical(missing, character(0),
                   info = paste("missing section 35 negatives:",
                                paste(missing, collapse = ", ")))

  # Each of them must actually be recorded as a negative. A required
  # negative sitting in the file as must_find=TRUE would invert the safety
  # measurement rather than perform it.
  neg <- raw[q %in% required, , drop = FALSE]
  expect_true(all(toupper(trimws(neg$must_find)) == "FALSE"))
  expect_true(all(neg$query_type %in%
                    c("confusable_negative", "negative_no_authoritative_code")))
})

test_that("every confusable negative names a code that genuinely exists", {
  skip_if_not(exists("get_classification", mode = "function"))
  cases <- retrieval_eval_load_cases(sem_eval_path())
  conf <- cases[cases$query_type == "confusable_negative", , drop = FALSE]
  expect_gt(nrow(conf), 0L)

  # The whole point of a confusable is that the code is real and tempting.
  # A typo'd code here would make the case pass vacuously forever.
  for (i in seq_len(nrow(conf))) {
    data <- get_classification(conf$system[i], conf$version[i])
    expect_true(conf$expected_code[i] %in% as.character(data$code),
                info = paste(conf$case_id[i], "names a non-existent code"))
  }
})

test_that("the corpus is scorable end to end and its metrics are well formed", {
  cases <- retrieval_eval_load_cases(sem_eval_path())
  res <- retrieval_eval_run(cases, k = c(1L, 5L, 10L), limit = 50L)
  m <- res$metrics

  expect_identical(m$n_cases, nrow(cases))
  expect_identical(m$n_errors, 0L)
  expect_true(all(!is.na(c(m$recall_at_1, m$recall_at_5, m$recall_at_10, m$mrr))))
  expect_lte(m$recall_at_1, m$recall_at_5)
  expect_lte(m$recall_at_5, m$recall_at_10)

  # Negative safety on this corpus is the number a semantic change must
  # never be allowed to move downwards. Measured, not aspirational: the
  # confusables are at 100% with the semantic tier off.
  expect_equal(m$confusable_negative_correct, 1)
})
