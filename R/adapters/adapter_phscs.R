# Adapter over the installed `phscs` package.
#
# Exposes the packaged editions of: psic (2019), psoc (2012), psced (2017),
# pcoicop (2020 current / 2009 archived), pcpc (2002), psccs (2018).
# Converts each system's native `get_X()` output into the canonical
# classification tibble defined in R/schema.R.
#
# PARENT_CODE DERIVATION
# -----------------------
# Rather than hardcoding a fixed digit-width per level (verified to be
# unreliable: pcpc and psccs mix 4- and 5-digit codes *within* a single
# level, and pcoicop mixes 3-5 dot-segments across "item"/"subitem"), every
# level's parent_code is derived by one generic search shared across all
# six systems: for each code, try successively shorter left-truncations of
# the raw code string (dropping one trailing character at a time) and take
# the first truncation that matches an ACTUAL code belonging to the
# immediately preceding level in that system's hierarchy (per
# `level_order` below). If no truncation matches, parent_code is left NA
# rather than guessing.
#
# This was validated against every system/level actually pulled from the
# installed phscs package: NA rates were 0% for the great majority of
# level transitions, and only slightly above 0% (never fabricated) for a
# handful of transitions where PSA's own packaged data has no resolvable
# parent for a small number of rows (e.g. a few pcoicop sub-items, and
# ~7% of psoc sub-major groups) -- those are left NA rather than forced to
# match something.
#
# For psic specifically: division-level codes are purely numeric (e.g.
# "01") while their true parent (a section) is a single letter (e.g. "A").
# No numeric truncation of a division code can ever equal a letter code,
# so division.parent_code is always (and correctly) NA under this scheme --
# consistent with the spec's explicit instruction that PSIC 2019 divisions
# cannot have their section parent derived without a separate section/
# division range table this adapter does not have. A later integration
# step (owned by the PSIC 2026 workstream) may backfill this from the
# PSIC 2026 structural mapping.

.phscs_cache <- new.env(parent = emptyenv())

# Registry of what each system exposes.
# - level_order: canonical level names, top (no parent) to bottom.
# - level_arg: canonical level name -> the string phscs::get_X() expects
#   for `level=`. Only psic differs (plural/dashed forms); every other
#   system's canonical level name equals its own argument value.
.phscs_systems <- list(
  psic = list(
    get_fn = function(version, level_arg) {
      phscs::get_psic(version = version, level = level_arg, minimal = TRUE, cols = "description")
    },
    versions = c("2019"),
    level_order = c("section", "division", "group", "class", "sub-class"),
    level_arg = c(
      section = "sections", division = "divisions", group = "groups",
      class = "classes", `sub-class` = "sub-classes"
    ),
    # PSIC 2019 is archived: PSIC Revision 5 (2026), supplied by the
    # sibling adapter_psic_2026.R, is the current edition for this system.
    status = function(version) "archived",
    source_url = "https://psa.gov.ph/classification/psic"
  ),
  psoc = list(
    get_fn = function(version, level_arg) {
      phscs::get_psoc(version = version, level = level_arg, minimal = TRUE, cols = "description")
    },
    versions = c("2012"),
    # Canonical level names use the vocabulary mandated for PSOC (spec:
    # major_group/sub_major_group/minor_group/unit_group), matching the
    # sibling adapter_psoc_2022.R so switching between the 2012 and 2022
    # editions never leaves an incompatible level id selected. level_arg's
    # VALUES are still phscs::get_psoc()'s own expected argument strings
    # ("major"/"sub-major"/"minor"/"unit") -- only the canonical names
    # (level_order, and level_arg's names) changed.
    level_order = c("major_group", "sub_major_group", "minor_group", "unit_group"),
    level_arg = c(
      major_group = "major", sub_major_group = "sub-major",
      minor_group = "minor", unit_group = "unit"
    ),
    # PSOC 2012 is archived: the "2022 Updates to the 2012 PSOC", supplied
    # by the sibling adapter_psoc_2022.R, is the current edition for this
    # system.
    status = function(version) "archived",
    source_url = "https://psa.gov.ph/classification/psoc"
  ),
  psced = list(
    get_fn = function(version, level_arg) {
      phscs::get_psced(version = version, level = level_arg, minimal = TRUE, cols = "description")
    },
    versions = c("2017"),
    level_order = c("levels", "broadfield", "narrowfield", "detailedfield"),
    level_arg = c(
      levels = "levels", broadfield = "broadfield",
      narrowfield = "narrowfield", detailedfield = "detailedfield"
    ),
    status = function(version) "current",
    source_url = "https://psa.gov.ph/classification/psced"
  ),
  pcoicop = list(
    get_fn = function(version, level_arg) {
      phscs::get_pcoicop(version = version, level = level_arg, minimal = TRUE, cols = "description")
    },
    versions = c("2020", "2009"),
    level_order = c("divisions", "groups", "class", "sub-class", "item", "subitem"),
    level_arg = c(
      divisions = "divisions", groups = "groups", class = "class",
      `sub-class` = "sub-class", item = "item", subitem = "subitem"
    ),
    status = function(version) if (identical(version, "2020")) "current" else "archived",
    source_url = "https://psa.gov.ph/classification/pcoicop"
  ),
  pcpc = list(
    get_fn = function(version, level_arg) {
      phscs::get_pcpc(version = version, level = level_arg, minimal = TRUE, cols = "description")
    },
    versions = c("2002"),
    level_order = c("sections", "divisions", "groups", "classes", "sub-classes", "item"),
    level_arg = c(
      sections = "sections", divisions = "divisions", groups = "groups",
      classes = "classes", `sub-classes` = "sub-classes", item = "item"
    ),
    status = function(version) "current",
    source_url = "https://psa.gov.ph/classification/pcpc"
  ),
  psccs = list(
    get_fn = function(version, level_arg) {
      phscs::get_psccs(version = version, level = level_arg, minimal = TRUE, cols = "description")
    },
    versions = c("2018"),
    level_order = c("section", "divisions", "groups", "classes", "sub-classes"),
    level_arg = c(
      section = "section", divisions = "divisions", groups = "groups",
      classes = "classes", `sub-classes` = "sub-classes"
    ),
    status = function(version) "current",
    source_url = "https://psa.gov.ph/classification/psccs"
  )
)

#' Fill in a missing (NA) label as honestly as possible, never inventing
#' prose. Two fallbacks, tried in order:
#'  1. Some phscs datasets store a row's true title as a leading ALL-CAPS
#'     phrase glued onto the front of `description` instead of populating
#'     `label` (verified in pcoicop 2020 groups 01.3/02.3/02.4/03.2, e.g.
#'     description "TOBACCO This group covers..." with label NA). Recover
#'     it with a regex -- this reads data that IS present, it does not
#'     fabricate anything.
#'  2. A handful of rows have neither a label nor a description anywhere
#'     in the packaged data (verified: pcpc item codes 347305, 625290).
#'     For those, fall back to the official code itself as the display
#'     label -- the one fact about the row we're certain of, not invented
#'     text.
.fill_missing_label <- function(label, description, code) {
  missing <- is.na(label)
  if (!any(missing)) {
    return(label)
  }

  extract_leading_caps <- function(desc) {
    if (is.na(desc)) return(NA_character_)
    m <- regexpr("^([A-Z0-9 ,\\-]+?)(?=\\s[A-Z][a-z])", desc, perl = TRUE)
    if (m == -1L) return(NA_character_)
    trimws(regmatches(desc, m))
  }

  extracted <- vapply(description[missing], extract_leading_caps, character(1), USE.NAMES = FALSE)
  label[missing] <- ifelse(!is.na(extracted), extracted, code[missing])
  label
}

.phscs_system_spec <- function(system) {
  spec <- .phscs_systems[[system]]
  if (is.null(spec)) {
    stop(sprintf("Unknown phscs system: '%s'", system), call. = FALSE)
  }
  spec
}

#' Character vector of version ids available for a system.
phscs_versions <- function(system) {
  .phscs_system_spec(system)$versions
}

#' Character vector of canonical level ids for a system+version.
#' (The level vocabulary is the same across every documented version of a
#' given system in the installed phscs package.)
phscs_levels <- function(system, version) {
  .phscs_system_spec(system)$level_order
}

#' Generic parent-code derivation shared by every phscs-backed system.
#' See file header for rationale and validation notes.
.derive_parent_by_truncation <- function(codes, levels, level_order) {
  parent <- rep(NA_character_, length(codes))
  for (i in seq_along(level_order)[-1]) {
    lvl <- level_order[i]
    parent_lvl <- level_order[i - 1L]
    parent_codes <- codes[levels == parent_lvl]
    if (length(parent_codes) == 0L) next

    # Hash the parent level's codes once so each candidate lookup below is
    # O(1) rather than O(n) (this matters for levels with thousands of rows).
    parent_env <- new.env(size = length(parent_codes) * 2L, parent = emptyenv())
    for (pc in parent_codes) assign(pc, TRUE, envir = parent_env)

    idx <- which(levels == lvl)
    for (j in idx) {
      code <- codes[j]
      len <- nchar(code) - 1L
      found <- NA_character_
      while (len >= 1L) {
        cand <- substr(code, 1L, len)
        if (exists(cand, envir = parent_env, inherits = FALSE)) {
          found <- cand
          break
        }
        len <- len - 1L
      }
      parent[j] <- found
    }
  }
  parent
}

# Pull + assemble every level for one system+version, computing parent_code
# generically across the whole assembled dataset. Cached per system:version
# so repeated calls within one R session don't re-hit phscs's in-memory
# package datasets.
.phscs_pull_all_levels <- function(system, version) {
  key <- paste(system, version, sep = ":")
  cached <- .phscs_cache[[key]]
  if (!is.null(cached)) {
    return(cached)
  }

  spec <- .phscs_system_spec(system)
  status <- spec$status(version)

  per_level <- lapply(spec$level_order, function(lvl) {
    arg <- spec$level_arg[[lvl]]
    raw <- spec$get_fn(version, arg)
    description <- if ("description" %in% names(raw)) raw$description else NA_character_
    list(
      code = as.character(raw$value),
      label = as.character(raw$label),
      description = as.character(description)
    )
  })
  names(per_level) <- spec$level_order

  all_codes <- unlist(lapply(per_level, `[[`, "code"), use.names = FALSE)
  all_labels <- unlist(lapply(per_level, `[[`, "label"), use.names = FALSE)
  all_desc <- unlist(lapply(per_level, `[[`, "description"), use.names = FALSE)
  all_labels <- .fill_missing_label(all_labels, all_desc, all_codes)
  all_levels <- unlist(
    lapply(spec$level_order, function(lvl) rep(lvl, length(per_level[[lvl]]$code))),
    use.names = FALSE
  )

  parent_code <- .derive_parent_by_truncation(all_codes, all_levels, spec$level_order)

  out <- new_classification_tibble(
    system = system,
    version = version,
    level = all_levels,
    code = all_codes,
    label = all_labels,
    description = all_desc,
    parent_code = parent_code,
    status = status,
    source = "Philippine Statistics Authority",
    source_url = spec$source_url
  )

  .phscs_cache[[key]] <- out
  out
}

#' Canonical classification tibble for one system+version.
#' `level = NULL` (default) returns every level for that system+version.
phscs_get <- function(system, version, level = NULL) {
  out <- .phscs_pull_all_levels(system, version)
  if (!is.null(level)) {
    out <- out[out$level == level, , drop = FALSE]
  }
  out
}

#' Display/provenance metadata for one system+version.
phscs_metadata <- function(system, version) {
  spec <- .phscs_system_spec(system)
  list(
    system = system,
    version = version,
    display_version = version,
    status = spec$status(version),
    source = "Philippine Statistics Authority",
    source_url = spec$source_url,
    # Sys.Date() is an MVP placeholder for "when this was pulled". Ideally
    # this would instead be the phscs package's own build/publication date
    # if that becomes introspectable in a future package version.
    retrieved_at = as.character(Sys.Date()),
    license = "CC BY 4.0 unless otherwise stated by PSA"
  )
}
