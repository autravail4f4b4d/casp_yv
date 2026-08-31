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

# ---------------------------------------------------------------------------
# Full-chain ancestry (v10)
# ---------------------------------------------------------------------------
#
# `assistant_hierarchy_annotate()` above deliberately looks only at
# parent_code links WITHIN the candidate set: that is all it needs to label
# a clean ancestor chain, and it must stay cheap enough to run on every
# search.
#
# That is not enough for RANKING. A candidate set is a bounded shortlist,
# so an intermediate level is frequently absent. Measured: for a national
# public-administration query the survivors were the Section P, the
# Division 84, the Class 8411 and the sub-class 84119 -- but the Group 841
# sitting between 84 and 8411 was never retrieved. With the chain broken,
# 84 came back "standalone", outranked 8411, and the answer degraded from
# the canonical ceiling to an entire PSIC Division.
#
# This resolves the real chain from the repository instead, memoised per
# system+version so the cost is one lookup per process, not per query.

.assistant_parent_map_cache <- new.env(parent = emptyenv())

.assistant_parent_map_reset <- function() {
  rm(list = ls(.assistant_parent_map_cache, all.names = TRUE),
     envir = .assistant_parent_map_cache)
  invisible(NULL)
}

#' code -> parent_code lookup for one system/version, memoised.
#'
#' Returns an empty map for a system with no hierarchy (every
#' `parent_code` NA), which makes every ancestry test below FALSE -- the
#' correct answer for a flat classification such as PTSCS.
.assistant_parent_map <- function(system, version) {
  key <- paste(system, version, sep = "::")
  hit <- .assistant_parent_map_cache[[key]]
  if (!is.null(hit)) return(hit)
  map <- tryCatch({
    d <- get_classification(system, version)
    if (is.null(d) || !all(c("code", "parent_code") %in% names(d))) {
      stats::setNames(character(0), character(0))
    } else {
      p <- as.character(d$parent_code)
      names(p) <- as.character(d$code)
      p[!is.na(p) & nzchar(p)]
    }
  }, error = function(e) stats::setNames(character(0), character(0)))
  .assistant_parent_map_cache[[key]] <- map
  map
}

#' How many OTHER candidates in the set is each code an ancestor of?
#'
#' A COUNT rather than a flag, because a flag cannot rank two ancestors
#' against each other. Measured: for the national public-administration
#' set the survivors were the Section P, the Division 84, the Class 8411
#' and the residual sub-class 84119. All three of P/84/8411 are ancestors,
#' so a boolean tied them and retrieval order picked P -- an entire PSIC
#' Section. Counting descendants orders them by specificity instead:
#' P covers 3, 84 covers 2, 8411 covers 1, so ascending order puts the
#' narrowest ancestor first and 8411 wins once the residual 84119 has been
#' demoted by the residual-marker rule.
#'
#' @param codes character vector of candidate codes.
#' @param system,version character(1).
#'
#' @return integer vector the same length as `codes`. Never errors; a
#'   system with no canonical hierarchy yields all zeros.
.assistant_ancestor_of_other <- function(codes, system, version) {
  n <- length(codes)
  if (n < 2L) return(rep(0L, n))
  map <- .assistant_parent_map(system, version)
  if (length(map) == 0L) return(rep(0L, n))

  # Full ancestor chain of one code. The depth cap is a cycle backstop;
  # real classifications are about five levels deep.
  ancestors_of <- function(code) {
    out <- character(0)
    cur <- code
    for (i in seq_len(12L)) {
      # SINGLE bracket on purpose: `map[["absent"]]` throws "subscript out
      # of bounds" on an atomic vector, and a code with no parent entry --
      # a top-level row, or one from a differently-keyed set -- is the
      # normal case here, not an error. `map["absent"]` yields NA, which
      # simply ends the walk.
      nxt <- unname(map[cur])
      if (length(nxt) != 1L || is.na(nxt) || !nzchar(nxt) || nxt %in% out) break
      out <- c(out, nxt)
      cur <- nxt
    }
    out
  }

  chains <- lapply(codes, ancestors_of)
  # Counted against DIFFERENT candidates only, never against itself.
  vapply(seq_len(n), function(i) {
    sum(vapply(chains[-i], function(ch) codes[[i]] %in% ch, logical(1)))
  }, integer(1))
}

#' Canonical depth of each code -- how many levels down the real hierarchy.
#'
#' A Section is 0, a Division 1, a Group 2, a Class 3, a sub-class 4. Used
#' as the last specificity tiebreaker: when two AGGREGATES survive with
#' every other ranking key tied, the deeper one says more about the same
#' subject. Measured: for a national public-administration query the
#' Division 84 ("Public Administration and Defense; Compulsory Social
#' Security" -- an entire PSIC sector) and the Class 8411 ("General public
#' administration activities" -- the canonical ceiling this context can
#' support) tied on every key including query coverage, and retrieval
#' order alone chose the Division.
#'
#' @return integer vector the same length as `codes`; 0 where unknown.
.assistant_canonical_depth <- function(codes, system, version) {
  n <- length(codes)
  if (n == 0L) return(integer(0))
  map <- .assistant_parent_map(system, version)
  if (length(map) == 0L) return(rep(0L, n))
  vapply(codes, function(code) {
    d <- 0L
    cur <- code
    seen <- character(0)
    for (i in seq_len(12L)) {
      nxt <- unname(map[cur])
      if (length(nxt) != 1L || is.na(nxt) || !nzchar(nxt) || nxt %in% seen) break
      seen <- c(seen, nxt)
      cur <- nxt
      d <- d + 1L
    }
    d
  }, integer(1), USE.NAMES = FALSE)
}
