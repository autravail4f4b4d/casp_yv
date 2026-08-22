# Run the full testthat suite. Invoke from the repository root:
#   Rscript scripts/run_tests.R
stopifnot(dir.exists("R"), dir.exists("tests/testthat"))
testthat::test_dir("tests/testthat", stop_on_failure = FALSE)
