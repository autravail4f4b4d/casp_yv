# RM orchestration hardening -- hierarchy-aware candidate selection.
#
# ROOT DEFECT (staging, live RM): for "heavy truck driver", the retrieval
# engine correctly returns BOTH 833 (HEAVY TRUCK AND BUS DRIVERS, the
# ancestor minor group) and 8332 (HEAVY TRUCK AND LORRY DRIVERS, the more
# specific unit group) as verified candidates -- that is retrieval doing its
# job, since both are real, canonical, on-topic matches. The defect was in
# what RM did with them: presenting both as equally specific final answers
# instead of recognising that one is a parent of the other.
#
# This file adds a deterministic, code-level annotation step between
# retrieval and presentation. It does not touch retrieval, and it does not
# decide what RM says -- it only computes, from the CANONICAL `parent_code`
# field already carried by every classification row (see R/schema.R,
# R/adapters/adapter_phscs.R, R/adapters/adapter_psgc.R), which candidates
# in a given result set are ancestors of other candidates in that SAME set.
#
# Deliberately NOT a string-length/digit-count heuristic: `parent_code` is
# the actual canonical hierarchy relationship the repository already
# computes per system (and is NA everywhere for a system with no hierarchy,
# e.g. PTSCS -- every row in such a system is correctly left "standalone").

#' Annotate a candidate result set with hierarchy roles.
#'
#' Operates purely on the columns already present in `rows` (`code`,
#' `parent_code`) -- no extra repository lookups, so it is cheap enough to
#' run on every `assistant_search_classification()` call.
#'
#' Roles:
#'   "ancestor"      -- this row is the ancestor (direct or indirect, within
#'                      THIS result set) of at least one other row here.
#'                      `hierarchy_of` names the single most-specific
#'                      descendant it relates to, when exactly one exists.
#'   "most_specific" -- this row is not an ancestor of anything else in the
#'                      set, and it is the ONLY such row (a clean ancestor
#'                      chain with one leaf).
#'   "standalone"    -- not part of any ancestor/descendant relationship
#'                      found in this set, OR one of several co-equal leaves
#'                      (see `assistant_ambiguity_check()`, which further
#'                      distinguishes "sibling" leaves sharing a parent from
#'                      genuinely unrelated leaves).
#'
#' @param rows A data.frame with at least a `code` column; `parent_code` is
#'   used when present and treated as entirely absent (NA) otherwise.
#'
#' @return `rows` with two additional character columns, `hierarchy_role`
#'   and `hierarchy_of` (NA where not applicable). Zero-row input round-trips
#'   with zero-length columns added, never an error.
assistant_hierarchy_annotate <- function(rows) {
  n <- nrow(rows)
  if (is.null(n)) n <- 0L

  if (n == 0L) {
    rows$hierarchy_role <- character(0)
    rows$hierarchy_of <- character(0)
    return(rows)
  }

  codes <- as.character(rows$code)
  parents <- if ("parent_code" %in% names(rows)) {
    as.character(rows$parent_code)
  } else {
    rep(NA_character_, n)
  }

  # descendants_in_set[[i]] accumulates every code in `rows` that row i is a
  # (direct or transitive) ancestor of, found by walking each row's OWN
  # parent chain upward only as far as the chain stays inside this set.
  descendants_in_set <- vector("list", n)

  for (j in seq_len(n)) {
    p <- parents[[j]]
    hops <- 0L
    while (!is.na(p) && hops < n) {
      i <- match(p, codes)
      if (is.na(i)) break
      descendants_in_set[[i]] <- union(descendants_in_set[[i]], codes[[j]])
      p <- parents[[i]]
      hops <- hops + 1L
    }
  }

  is_ancestor <- vapply(descendants_in_set, function(x) length(x) > 0L, logical(1))
  role <- ifelse(is_ancestor, "ancestor", "standalone")

  leaf_idx <- which(!is_ancestor)
  if (length(leaf_idx) == 1L) {
    role[leaf_idx] <- "most_specific"
    the_leaf_code <- codes[leaf_idx]
    hierarchy_of <- ifelse(role == "ancestor", the_leaf_code, NA_character_)
  } else {
    # Multiple (or zero) leaves: an ancestor here relates to more than one
    # descendant, or the "most specific" judgement is genuinely ambiguous --
    # leave `hierarchy_of` unset rather than guessing which leaf is "the"
    # one; `assistant_ambiguity_check()` handles the leaf set next.
    hierarchy_of <- vapply(descendants_in_set, function(x) {
      if (length(x) == 1L) x[[1L]] else NA_character_
    }, character(1))
  }

  rows$hierarchy_role <- role
  rows$hierarchy_of <- hierarchy_of
  rows
}
