# Whether the public Level control carries information for a given system.
#
# UI-POST-03. Composite/thematic systems (PTSCS, PSCrCS) group their records
# by `component`, and their `level` column was populated with the SAME token
# as the component. Showing both controls therefore asks the user to make the
# same choice twice, and the second control leaks machine tokens such as
# `tourism_product` into the interface.
#
# The specification is explicit that this must not be hard-coded per system:
# the answer has to be derived from the artifact, so that a future edition
# which genuinely introduces sub-levels inside a component starts showing the
# Level control again without any code change here.
#
# The rule implemented below is exactly the one the specification states:
#
#   Level is informative  <=>  some reachable component contains two or more
#                              distinct levels.
#
# For an ordinary hierarchical system (PSGC, PSIC, PSOC, PSCC, ...) there are
# no components at all, the question does not arise, and Level is always
# informative.
#
# This is a presentation predicate only. `level` remains in the canonical data
# model, remains a valid argument to every service function, and remains
# searchable — nothing here changes which records exist or which are selected.

#' Distinct component x level pairs actually present in a system+version.
#'
#' @param system character(1).
#' @param version character(1).
#'
#' @return A data.frame with character columns `component` and `level`, one
#'   row per observed pair, or a zero-row frame when the system carries no
#'   component column.
classification_component_levels <- function(system, version) {
  empty <- data.frame(
    component = character(0), level = character(0),
    stringsAsFactors = FALSE
  )

  data <- get_classification(system, version)
  if (!"component" %in% names(data) || !"level" %in% names(data)) {
    return(empty)
  }

  pairs <- unique(data.frame(
    component = as.character(data$component),
    level = as.character(data$level),
    stringsAsFactors = FALSE
  ))
  pairs <- pairs[!is.na(pairs$component) & !is.na(pairs$level), , drop = FALSE]
  rownames(pairs) <- NULL
  pairs
}

#' Should the public Level control be offered for this system?
#'
#' @param system character(1).
#' @param version character(1).
#' @param component character(1) or NULL. When supplied, the question is
#'   narrowed to "does Level add anything *within this component*".
#'
#' @return TRUE when Level adds information beyond Component and should be
#'   shown; FALSE when it merely restates Component and must be hidden.
#'   Never NA. A system with no components always returns TRUE.
classification_level_is_informative <- function(system, version, component = NULL) {
  pairs <- classification_component_levels(system, version)

  # No component dimension at all: an ordinary code hierarchy, where Level is
  # the primary and only structural filter.
  if (nrow(pairs) == 0L) {
    return(TRUE)
  }

  if (!is.null(component)) {
    pairs <- pairs[pairs$component == component, , drop = FALSE]
    # An unknown component narrows to nothing; treat that as "no extra
    # information" rather than erroring, so a stale client value during a
    # round-trip cannot crash the UI.
    return(length(unique(pairs$level)) > 1L)
  }

  # "All components": informative only if SOME component genuinely subdivides.
  per_component <- tapply(pairs$level, pairs$component, function(x) length(unique(x)))
  any(per_component > 1L)
}
