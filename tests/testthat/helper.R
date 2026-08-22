# Sources every R/ file so testthat sees the full service layer without
# launching Shiny. Adapters/registry/search files are additive — new files
# dropped into R/ are picked up automatically.
#
# testthat::test_dir() chdirs into tests/testthat while running, so the
# repository root is one level up from this helper's own directory.
repo_root <- normalizePath(file.path(getwd(), "..", ".."))
r_files <- list.files(file.path(repo_root, "R"), pattern = "\\.R$", recursive = TRUE, full.names = TRUE)
invisible(lapply(sort(r_files), source))
