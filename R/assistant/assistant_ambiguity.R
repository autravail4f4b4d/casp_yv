# RM orchestration hardening -- ambiguity detection and clarification.
#
# Runs AFTER `assistant_hierarchy_annotate()`. Hierarchy already resolves
# the "ancestor presented as an equal alternative" defect; this module
# targets a different, genuinely distinct failure mode: several verified
# candidates that are SIBLINGS (same immediate parent, none an ancestor of
# another) with no single one clearly dominant -- e.g. PSIC "bakery"
# surfacing three separate bakery-product sub-classes under the same class.
#
# The clarifying question and its options are built ENTIRELY from verified
# fields already present in `rows` (`code`, `label`, `parent_code`) --
# nothing here invents category names, product distinctions, or wording not
# already present in the official labels. This is deliberately generic: it
# is not bakery-specific, PSIC-specific, or hard-coded to any query: it
# fires for any candidate set containing 2+ true siblings, on any system
# that populates `parent_code`.

#' Detect sibling ambiguity in a hierarchy-annotated candidate set.
#'
#' @param rows A data.frame as returned by `assistant_hierarchy_annotate()`
#'   (must carry `code`, `label`, `hierarchy_role`; `parent_code` is read
#'   when present).
#'
#' @return A list:
#'   `ambiguous`           logical(1).
#'   `clarifying_question` character(1) or NA when not ambiguous.
#'   `options`             list of `list(code, label)`, one per sibling in
#'                         the ambiguous group; empty list when not
#'                         ambiguous.
#'   Never errors: malformed or insufficient input returns the "not
#'   ambiguous" result.
assistant_ambiguity_check <- function(rows) {
  none <- list(ambiguous = FALSE, clarifying_question = NA_character_, options = list())

  if (is.null(rows) || nrow(rows) == 0L) return(none)
  required_cols <- c("code", "label", "hierarchy_role")
  if (!all(required_cols %in% names(rows))) return(none)
  if (!"parent_code" %in% names(rows)) return(none)

  # Only leaves compete for "the" answer; an ancestor already has its
  # relationship recorded by the hierarchy step and is not itself a
  # clarification candidate.
  leaves <- rows[rows$hierarchy_role != "ancestor", , drop = FALSE]
  if (nrow(leaves) < 2L) return(none)

  parents <- as.character(leaves$parent_code)
  has_parent <- !is.na(parents)
  if (!any(has_parent)) return(none)

  counts <- table(parents[has_parent])
  sibling_parents <- names(counts)[counts >= 2L]
  if (length(sibling_parents) == 0L) return(none)

  # Deterministic, bounded: the first qualifying sibling group in the
  # candidate set's own order. A result set with more than one distinct
  # ambiguous group is rare; resolving one group at a time (with a further
  # round of retrieval + this same check after the user answers) is safer
  # than trying to ask about several dimensions of ambiguity at once.
  group_parent <- sibling_parents[[1L]]
  group <- leaves[has_parent & parents == group_parent, , drop = FALSE]

  parent_label <- NA_character_
  parent_row <- rows[!is.na(rows$code) & rows$code == group_parent, , drop = FALSE]
  if (nrow(parent_row) > 0L) {
    parent_label <- as.character(parent_row$label[[1L]])
  }

  options <- lapply(seq_len(nrow(group)), function(i) {
    list(code = as.character(group$code[[i]]), label = as.character(group$label[[i]]))
  })

  option_lines <- vapply(options, function(o) sprintf("- %s", o$label), character(1))
  question <- if (!is.na(parent_label) && nzchar(parent_label)) {
    sprintf(
      "Multiple verified classifications fall under \"%s\". Which one best matches?\n\n%s",
      parent_label, paste(option_lines, collapse = "\n")
    )
  } else {
    sprintf(
      "Multiple verified classifications match this description. Which one best matches?\n\n%s",
      paste(option_lines, collapse = "\n")
    )
  }

  list(ambiguous = TRUE, clarifying_question = question, options = options)
}
