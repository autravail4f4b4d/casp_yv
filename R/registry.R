# Classification system registry.
#
# `classification_registry()` introspects the adapters (R/adapters/*.R) --
# it never hardcodes a second copy of the version/level tables that live
# in those adapters, so the registry can't drift out of sync with them.

# For phscs-backed systems: pick the version whose adapter_phscs::phscs_metadata()
# reports status == "current"; fall back to the first known version if none
# is marked current (shouldn't happen given the adapter's own status rules,
# but keeps this function total).
.phscs_current_version <- function(system, versions) {
  statuses <- vapply(versions, function(v) phscs_metadata(system, v)$status, character(1))
  current <- versions[statuses == "current"]
  if (length(current) >= 1L) current[[1]] else versions[[1]]
}

# PSIC is special: the phscs package only contains the archived 2019
# edition, but PSA's current edition is PSIC Revision 5 (2026), supplied by
# a THIRD, sibling-owned source: R/adapters/adapter_psic_2026.R (backed by
# data/psic_2026.rds), exposing psic2026_versions()/psic2026_levels()/
# psic2026_get()/psic2026_metadata(). Every call into it is still wrapped
# in tryCatch + an `exists()` guard: that file is owned by a separate,
# independently-evolving workstream, and its runtime artifact
# (data/psic_2026.rds) is read from disk lazily and can throw if missing
# or corrupt -- if any of that fails for any reason, this registry
# degrades to reporting just the phscs-sourced psic 2019 edition rather
# than erroring the whole registry.
.psic_versions <- function() {
  versions <- phscs_versions("psic")
  extra <- tryCatch(
    {
      if (exists("psic2026_versions", mode = "function")) {
        as.character(psic2026_versions())
      } else {
        character(0)
      }
    },
    error = function(e) character(0)
  )
  unique(c(versions, extra))
}

.psic_current_version <- function(versions) {
  current <- tryCatch(
    {
      if (exists("psic2026_metadata", mode = "function")) {
        meta <- psic2026_metadata()
        if (identical(meta$status, "current")) meta$version else NULL
      } else {
        NULL
      }
    },
    error = function(e) NULL
  )
  if (!is.null(current) && current %in% versions) {
    return(current)
  }
  # PSIC 2026 adapter unavailable, or it didn't report itself as current:
  # every phscs-sourced psic version is archived, so there is no genuinely
  # "current" psic version this registry can introspect on its own.
  # Report the phscs-sourced version so the field is never empty.
  .phscs_current_version("psic", versions)
}

.psic_levels <- function(version) {
  extra <- tryCatch(
    {
      if (exists("psic2026_levels", mode = "function")) as.character(psic2026_levels()) else character(0)
    },
    error = function(e) character(0)
  )
  if (length(extra) > 0L) {
    return(extra)
  }
  # PSIC 2026 adapter unavailable: fall back to the phscs-sourced 2019
  # level vocabulary, which is the same set (section/division/group/class/
  # sub-class) PSIC 2026 is expected to use.
  phscs_levels("psic", "2019")
}

# PSOC follows the exact same pattern as PSIC above: phscs only contains the
# archived 2012 edition, while PSA's current edition is the "2022 Updates to
# the 2012 PSOC", supplied by a THIRD, sibling-owned source:
# R/adapters/adapter_psoc_2022.R (backed by data/psoc_2022.rds), exposing
# psoc2022_versions()/psoc2022_levels()/psoc2022_get()/psoc2022_metadata().
# Same tryCatch + exists() degrade-gracefully guards as PSIC.
.psoc_versions <- function() {
  versions <- phscs_versions("psoc")
  extra <- tryCatch(
    {
      if (exists("psoc2022_versions", mode = "function")) {
        as.character(psoc2022_versions())
      } else {
        character(0)
      }
    },
    error = function(e) character(0)
  )
  unique(c(versions, extra))
}

.psoc_current_version <- function(versions) {
  current <- tryCatch(
    {
      if (exists("psoc2022_metadata", mode = "function")) {
        meta <- psoc2022_metadata()
        if (identical(meta$status, "current")) meta$version else NULL
      } else {
        NULL
      }
    },
    error = function(e) NULL
  )
  if (!is.null(current) && current %in% versions) {
    return(current)
  }
  # PSOC 2022 adapter unavailable, or it didn't report itself as current:
  # degrade to the phscs-sourced version so the field is never empty (this
  # never happens once the 2022 artifact is built and present, but keeps
  # the registry total).
  .phscs_current_version("psoc", versions)
}

.psoc_levels <- function(version) {
  extra <- tryCatch(
    {
      if (exists("psoc2022_levels", mode = "function")) as.character(psoc2022_levels()) else character(0)
    },
    error = function(e) character(0)
  )
  if (length(extra) > 0L) {
    return(extra)
  }
  # PSOC 2022 adapter unavailable: fall back to the phscs-sourced 2012
  # level vocabulary (major/sub-major/minor/unit).
  phscs_levels("psoc", "2012")
}

.registry_systems_spec <- function() {
  list(
    list(
      id = "psgc",
      display_name = "Philippine Standard Geographic Code",
      short_name = "PSGC",
      category = "geographic",
      adapter = "adapter_psgc",
      supports_history = TRUE,
      source = "Philippine Statistics Authority",
      source_url = "https://psa.gov.ph/classification/psgc",
      versions_fn = function() psgc_versions(),
      current_fn = function(versions) {
        latest <- tryCatch(psgc::latest_release(), error = function(e) NULL)
        if (!is.null(latest) && latest %in% versions) latest else versions[[length(versions)]]
      },
      levels_fn = function(version) psgc_levels(version)
    ),
    list(
      id = "psic",
      display_name = "Philippine Standard Industrial Classification",
      short_name = "PSIC",
      category = "economic",
      adapter = "adapter_phscs",  # + adapter_psic_2026 (sibling); see .psic_versions()
      supports_history = TRUE,
      source = "Philippine Statistics Authority",
      source_url = "https://psa.gov.ph/classification/psic",
      versions_fn = .psic_versions,
      current_fn = .psic_current_version,
      levels_fn = .psic_levels
    ),
    list(
      id = "psoc",
      display_name = "Philippine Standard Occupational Classification",
      short_name = "PSOC",
      category = "economic",
      adapter = "adapter_phscs",  # + adapter_psoc_2022 (sibling); see .psoc_versions()
      supports_history = TRUE,
      source = "Philippine Statistics Authority",
      source_url = "https://psa.gov.ph/classification/psoc",
      versions_fn = .psoc_versions,
      current_fn = .psoc_current_version,
      levels_fn = .psoc_levels
    ),
    list(
      id = "psced",
      display_name = "Philippine Standard Classification of Education",
      short_name = "PSCED",
      category = "economic",
      adapter = "adapter_phscs",
      supports_history = FALSE,
      source = "Philippine Statistics Authority",
      source_url = "https://psa.gov.ph/classification/psced",
      versions_fn = function() phscs_versions("psced"),
      current_fn = function(versions) .phscs_current_version("psced", versions),
      levels_fn = function(version) phscs_levels("psced", version)
    ),
    list(
      id = "pcoicop",
      display_name = "Philippine Classification of Individual Consumption According to Purpose",
      short_name = "PCOICOP",
      category = "economic",
      adapter = "adapter_phscs",
      supports_history = TRUE,
      source = "Philippine Statistics Authority",
      source_url = "https://psa.gov.ph/classification/pcoicop",
      versions_fn = function() phscs_versions("pcoicop"),
      current_fn = function(versions) .phscs_current_version("pcoicop", versions),
      levels_fn = function(version) phscs_levels("pcoicop", version)
    ),
    list(
      id = "pcpc",
      display_name = "Philippine Central Product Classification",
      short_name = "PCPC",
      category = "economic",
      adapter = "adapter_phscs",
      supports_history = FALSE,
      source = "Philippine Statistics Authority",
      source_url = "https://psa.gov.ph/classification/pcpc",
      versions_fn = function() phscs_versions("pcpc"),
      current_fn = function(versions) .phscs_current_version("pcpc", versions),
      levels_fn = function(version) phscs_levels("pcpc", version)
    ),
    list(
      id = "psccs",
      display_name = "Philippine Standard Commodity Classification System",
      short_name = "PSCCS",
      category = "economic",
      adapter = "adapter_phscs",
      supports_history = FALSE,
      source = "Philippine Statistics Authority",
      source_url = "https://psa.gov.ph/classification/psccs",
      versions_fn = function() phscs_versions("psccs"),
      current_fn = function(versions) .phscs_current_version("psccs", versions),
      levels_fn = function(version) phscs_levels("psccs", version)
    )
  )
}

#' Build the classification system registry.
#'
#' One row per supported classification system, describing what versions
#' and hierarchy levels are available and which adapter serves it. This is
#' the single place the Shiny layer (and search/repository services) should
#' consult to discover what systems exist -- it never hardcodes a second
#' copy of adapter-owned facts.
#'
#' @return A tibble with columns: id, display_name, short_name, category,
#'   adapter, available_versions (list-column), current_version,
#'   available_levels (list-column), supports_history, source, source_url.
classification_registry <- function() {
  specs <- .registry_systems_spec()

  rows <- lapply(specs, function(s) {
    versions <- s$versions_fn()
    current_version <- s$current_fn(versions)
    levels_by_version <- lapply(versions, s$levels_fn)
    available_levels <- unique(unlist(levels_by_version, use.names = FALSE))

    tibble::tibble(
      id = s$id,
      display_name = s$display_name,
      short_name = s$short_name,
      category = s$category,
      adapter = s$adapter,
      available_versions = list(versions),
      current_version = current_version,
      available_levels = list(available_levels),
      supports_history = s$supports_history,
      source = s$source,
      source_url = s$source_url
    )
  })

  dplyr::bind_rows(rows)
}
