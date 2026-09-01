# Public-facing label formatting for edition identifiers and hierarchy levels.
#
# UI-POST-06 (edition/release labels) and UI-POST-03 (human-readable level
# labels). Everything here is PRESENTATION ONLY: the raw identifier is what
# travels to the repository, and every function in this file is a pure
# character -> character mapping with no side effects, so no display choice
# can ever change which records are selected.
#
# Two rules govern the whole file:
#
#   1. Never invent or reorder editions. `release_display_label()` is a
#      formatting pass over one identifier, not a sort key and not a lookup
#      into some parallel table of "nicer" editions.
#   2. Never show a machine token. A level whose raw value is not covered by
#      an explicit mapping falls through to a conservative humaniser rather
#      than being printed as-is.

# ---------------------------------------------------------------------
# Edition / release labels
# ---------------------------------------------------------------------

#' Human-readable label for an edition/release identifier.
#'
#' PSGC releases are published as tokens such as `Q1_2023`, `Q4_2023` and
#' `April_2024`. The underscore is a filename convention, not part of the
#' release's name, so it is the only thing removed.
#'
#' Deliberately conservative: underscores become spaces and nothing else
#' changes. Year-only editions ("2019", "2026"), hyphenated versioned
#' editions ("2025-v2.1") and anything else pass through untouched, so this
#' can never mangle an identifier it was not designed for. The transform is
#' also order-preserving, which is what keeps chronological ordering intact.
#'
#' @param version character vector of raw edition identifiers.
#'
#' @return A character vector of the same length. NA in, NA out.
release_display_label <- function(version) {
  version <- as.character(version)
  out <- gsub("_", " ", version, fixed = TRUE)
  out[is.na(version)] <- NA_character_
  out
}

# ---------------------------------------------------------------------
# Hierarchy level labels
# ---------------------------------------------------------------------

# Explicit per-system level labels.
#
# Explicit beats clever here: PSGC publishes genuine abbreviations that no
# generic humaniser could expand correctly ("Bgy", "SubMun"), and PSCED's
# level tokens are run together with no separator at all ("broadfield").
# Guessing at those would produce confident nonsense, so each is stated.
#
# A system absent from this list, or a level absent from its entry, falls
# through to .humanise_level_token().
LEVEL_DISPLAY_LABELS <- list(
  psgc = c(
    Reg = "Region",
    Prov = "Province",
    City = "City",
    Mun = "Municipality",
    SubMun = "Sub-municipality",
    Bgy = "Barangay"
  ),
  psced = c(
    levels = "Level",
    broadfield = "Broad field",
    narrowfield = "Narrow field",
    detailedfield = "Detailed field"
  )
)

# Generic fallback: separators become spaces, the first letter is capitalised,
# and the rest of the token is left alone so acronyms inside a label are not
# destroyed. "sub_major_group" -> "Sub major group"; "sub-class" ->
# "Sub-class" (hyphens are kept, being real orthography rather than a
# separator convention).
.humanise_level_token <- function(level) {
  out <- gsub("_", " ", level, fixed = TRUE)
  out <- trimws(out)
  ifelse(
    nchar(out) > 0L,
    paste0(toupper(substring(out, 1, 1)), substring(out, 2)),
    out
  )
}

#' Human-readable label for one or more hierarchy levels.
#'
#' PSCC is delegated to `pscc_level_labels()` when that mapping is available,
#' so the commodity classification's public level names stay owned by the
#' PSCC module rather than being restated here and drifting.
#'
#' @param system character(1).
#' @param level character vector of raw level values.
#'
#' @return A character vector of display labels, same length as `level`.
level_display_label <- function(system, level) {
  level <- as.character(level)
  if (length(level) == 0L) {
    return(character(0))
  }

  out <- .humanise_level_token(level)

  if (identical(system, "pscc") && exists("pscc_level_labels", mode = "function")) {
    mapping <- pscc_level_labels()
    hit <- match(level, names(mapping))
    out[!is.na(hit)] <- unname(mapping[hit[!is.na(hit)]])
    return(out)
  }

  mapping <- LEVEL_DISPLAY_LABELS[[system]]
  if (!is.null(mapping)) {
    hit <- match(level, names(mapping))
    out[!is.na(hit)] <- unname(mapping[hit[!is.na(hit)]])
  }

  out
}

# ---------------------------------------------------------------------
# Component labels
# ---------------------------------------------------------------------

# Public component names for the composite systems, exactly as the
# refinement specification names them (UI-POST-03, "Expected public
# Component choices"). These are the terms the source frameworks actually
# use -- "Tourism Characteristic Products" and "Creative Goods and Services"
# are the published category names, which a generic title-caser could never
# recover from the machine tokens `tourism_product` / `creative_good_service`.
#
# The token remains the value submitted to the repository; only the label
# changes, so component filtering is untouched.
COMPONENT_DISPLAY_LABELS <- list(
  ptscs = c(
    tourism_industry = "Tourism Industries",
    tourism_product = "Tourism Characteristic Products"
  ),
  pscrcs = c(
    creative_industry = "Creative Industries",
    creative_good_service = "Creative Goods and Services",
    creative_occupation = "Creative Occupations"
  )
)

#' Human-readable label for one or more component ids.
#'
#' Falls back to a title-cased form of the token for any component not
#' explicitly named, so a newly registered composite system degrades to
#' something readable rather than leaking a raw id.
#'
#' @param system character(1).
#' @param ids character vector of component ids.
#'
#' @return A character vector of display labels, same length as `ids`.
component_display_label <- function(system, ids) {
  ids <- as.character(ids)
  if (length(ids) == 0L) {
    return(character(0))
  }

  out <- vapply(ids, function(id) {
    words <- strsplit(gsub("_", " ", id, fixed = TRUE), " ", fixed = TRUE)[[1]]
    paste(toupper(substring(words, 1, 1)), substring(words, 2),
          sep = "", collapse = " ")
  }, character(1), USE.NAMES = FALSE)

  mapping <- COMPONENT_DISPLAY_LABELS[[system]]
  if (!is.null(mapping)) {
    hit <- match(ids, names(mapping))
    out[!is.na(hit)] <- unname(mapping[hit[!is.na(hit)]])
  }

  out
}

#' Named vector of component choices for a select input.
#'
#' @param system character(1).
#' @param ids character vector of component ids.
#'
#' @return A named character vector: names are public labels, values are the
#'   raw ids the repository validates against. Order preserved.
component_choice_vector <- function(system, ids) {
  stats::setNames(ids, component_display_label(system, ids))
}

# ---------------------------------------------------------------------
# Release ordering (UI-01)
# ---------------------------------------------------------------------
#
# The sidebar shows the newest/current release first. Two rules govern how
# that order is produced, and both exist to keep a display concern from
# becoming a data concern:
#
#   1. NEVER sort display labels. `release_display_label()` is a cosmetic
#      pass; sorting its output would make "April 2024" the newest PSGC
#      release (it sorts before every "Q..." token) and would put PSGC's
#      Q4 2025 above Q2 2026. Ordering is computed from the CANONICAL
#      version identifier, never from what the user sees.
#   2. NEVER invent an edition, and never change which edition is selected.
#      Reordering is a permutation of the vector the repository handed us.
#
# WHY A DERIVED KEY. There is no explicit effective-date column anywhere in
# the registry: `classification_registry()` exposes `available_versions`
# (a list-column of canonical identifiers) and `current_version`, and
# `phscs_metadata()` reports only a status. The adapters' own vector order
# is *usually* chronological (psgc::list_releases() genuinely is) but it is
# not universally so -- PCOICOP reports c("2020", "2009"), i.e. newest
# first. So neither signal alone is sufficient, and the ordering uses both:
#
#   primary   -- an effective date derived STRUCTURALLY from the canonical
#                identifier (year, plus quarter/month where the identifier
#                carries one). This is parsing a known identifier grammar,
#                not comparing strings.
#   tie-break -- the repository's own position for that identifier. Where
#                two releases share an effective month (PSGC publishes both
#                `April_2024` and `Q2_2024`, and both `July_2025` and
#                `Q3_2025`) the later-registered one is treated as newer,
#                which reproduces psgc::list_releases() order exactly.
#   override  -- the registry's `current_version` is pinned first. An
#                archived edition must never be able to sit above the
#                current one, whatever the identifiers look like.

# Month number for the month-name and quarter tokens PSA actually uses in
# release identifiers. Quarters map to the first month of the quarter.
.RELEASE_MONTH_TOKENS <- c(
  january = 1L, february = 2L, march = 3L, april = 4L, may = 5L, june = 6L,
  july = 7L, august = 8L, september = 9L, october = 10L, november = 11L,
  december = 12L,
  q1 = 1L, q2 = 4L, q3 = 7L, q4 = 10L
)

#' Effective-date sort key derived from one canonical release identifier.
#'
#' Returns `year * 100 + month`, or `NA_integer_` when the identifier
#' carries no recognisable year. Unknown shapes are never guessed at: they
#' fall through to NA and are ordered by repository position alone, which
#' is the conservative outcome.
#'
#' @param version character vector of raw edition identifiers.
#'
#' @return An integer vector of the same length.
.release_effective_key <- function(version) {
  v <- tolower(as.character(version))

  # First four-digit 19xx/20xx run in the identifier. "2025-v2.1" -> 2025.
  hits <- regexpr("(19|20)[0-9]{2}", v)
  has_year <- as.logical(hits > 0L)
  year <- rep(NA_integer_, length(v))
  year[has_year] <- suppressWarnings(as.integer(regmatches(v, hits)))

  # Month/quarter token, if the identifier carries one.
  month <- vapply(v, function(one) {
    hit <- names(.RELEASE_MONTH_TOKENS)[
      vapply(names(.RELEASE_MONTH_TOKENS),
             function(tok) grepl(paste0("(^|[^a-z])", tok, "([^a-z]|$)"), one),
             logical(1))
    ]
    if (length(hit) == 0L) 1L else max(.RELEASE_MONTH_TOKENS[hit])
  }, integer(1), USE.NAMES = FALSE)

  out <- year * 100L + month
  out[is.na(year)] <- NA_integer_
  out
}

#' Order edition identifiers newest/current first.
#'
#' Pure permutation: every input identifier appears exactly once in the
#' output, and nothing is added or renamed. See the block comment above for
#' why the key is derived rather than read from a metadata column.
#'
#' @param versions character vector of canonical edition identifiers, in
#'   the order the repository reported them (`classification_versions()`).
#' @param current character(1) or NULL. The registry's `current_version`
#'   for this system; pinned to the front when present.
#'
#' @return A character vector, same length and same elements as `versions`.
release_newest_first <- function(versions, current = NULL) {
  versions <- as.character(versions)
  n <- length(versions)
  if (n == 0L) {
    return(character(0))
  }

  key <- .release_effective_key(versions)
  # Identifiers we could not date sort last, but keep their relative
  # repository order among themselves.
  key[is.na(key)] <- -1L

  ord <- order(-key, -seq_len(n))
  out <- versions[ord]

  if (!is.null(current) && length(current) == 1L &&
      !is.na(current) && current %in% out) {
    out <- c(current, out[out != current])
  }
  out
}

# ---------------------------------------------------------------------
# System selector labels (UI-01)
# ---------------------------------------------------------------------

# The System option carries BOTH the acronym and the full official title.
# One string holds both, joined by this separator, so that:
#   * selectize's default `searchField: ["label"]` type-ahead matches on the
#     acronym AND on any word of the title with no extra configuration; and
#   * the two-line presentation is a pure client-side split of that one
#     string (see `system_selector_render()`), which means the value
#     submitted to the repository and the text available to assistive
#     technology are unaffected by the styling.
SYSTEM_LABEL_SEPARATOR <- " — "

#' Combined "ACRONYM — Full Official Title" label for a system.
#'
#' @param short_name,display_name character vectors of equal length, from
#'   `classification_registry()`.
#'
#' @return A character vector of labels.
system_choice_label <- function(short_name, display_name) {
  paste0(as.character(short_name), SYSTEM_LABEL_SEPARATOR, as.character(display_name))
}

#' Named choice vector for the System selector.
#'
#' Names are the combined labels, values are the raw registry ids -- the
#' standard Shiny `choices` shape, so the id is what is submitted.
#'
#' @param registry A `classification_registry()` tibble.
#'
#' @return A named character vector, registry order preserved.
system_choice_vector <- function(registry) {
  stats::setNames(
    as.character(registry$id),
    system_choice_label(registry$short_name, registry$display_name)
  )
}

#' Named vector of level choices for a select input.
#'
#' Names are the public labels, values are the raw levels the repository
#' expects — the standard Shiny `choices` shape, so the raw value is what is
#' submitted while only the label is humanised.
#'
#' @param system character(1).
#' @param levels character vector of raw level values, in hierarchy order.
#'
#' @return A named character vector, preserving the supplied order.
level_choice_vector <- function(system, levels) {
  stats::setNames(levels, level_display_label(system, levels))
}
