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
