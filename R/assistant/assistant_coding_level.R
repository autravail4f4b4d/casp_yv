# W1-A -- classification-level semantics.
#
# DEFECT this fixes: RM treated PSOC 833 (HEAVY TRUCK AND BUS DRIVERS, a
# 3-digit Minor Group) and 8332 (HEAVY TRUCK AND LORRY DRIVERS, a 4-digit
# Unit Group) as interchangeable final coding outputs. They are not. In
# survey/data-processing occupation coding the operational target is the
# most detailed level the system defines (PSOC Unit Group / 4 digits);
# broader levels are legitimate AGGREGATE hierarchy codes and must be
# labelled as such rather than offered as the detailed answer.
#
# HOW THE LEVEL ORDER IS DERIVED -- deliberately NOT a hard-coded table of
# "833 is aggregate, 8332 is detailed", and not a hard-coded per-system
# level list either. Both would rot the moment a system is re-ingested or
# added. Instead the order is measured from the repository itself: within
# one system+version, group every record by its canonical `level` string
# and take the median code width. Deeper level == longer code. Verified
# empirically across every registered system:
#
#   psoc  : major_group(1) < sub_major_group(2) < minor_group(3) < unit_group(4)
#   psic  : section(1) < division(2) < group(3) < class(4) < sub-class(5)
#   psced : levels(1) < broadfield(2) < narrowfield(3) < detailedfield(5)
#   pcpc  : sections(1) < ... < item(6)
#   pscc  : chapter(2) < ... < structural_group(17)
#
# Two families do not fit that shape and are handled explicitly rather
# than being forced into it:
#
#   * COMPOSITE systems (PTSCS, PSCrCS -- registry `is_composite`) partition
#     records by component, not by a code hierarchy; every record's `level`
#     is a component id. Role = "component".
#   * FIXED-WIDTH systems (PSGC -- every code is 10 characters at every
#     level, from Region to Barangay) carry a real hierarchy in
#     `parent_code` but code width cannot rank it. Role = "structural":
#     honest, since a PSGC level is a geographic stratum, not an
#     aggregate-vs-detailed coding choice in the survey sense.

# Recommended role vocabulary (spec 7).
ASSISTANT_CODING_ROLES <- c(
  "aggregate", "detailed", "structural", "component", "not_applicable"
)

# Per-process memo: level-depth maps are immutable for the life of the R
# process and each one costs a full get_classification() scan.
.assistant_level_cache <- new.env(parent = emptyenv())

.assistant_level_cache_reset <- function() {
  rm(list = ls(.assistant_level_cache), envir = .assistant_level_cache)
  invisible(NULL)
}

#' Ordered level map for one system+version, measured from the repository.
#'
#' @return list(levels = character (broadest -> most detailed),
#'   depth = named numeric median code width, detailed = character(1) or NA,
#'   kind = "hierarchical" | "fixed_width" | "composite") or NULL when the
#'   system/version cannot be read (never an error).
assistant_level_map <- function(system, version = NULL) {
  system <- tolower(as.character(system))
  version <- if (is.null(version)) {
    tryCatch(.assistant_current_version(system), error = function(e) NULL)
  } else {
    as.character(version)
  }
  if (is.null(version)) return(NULL)

  key <- paste0("lvl::", system, "::", version)
  cached <- .assistant_level_cache[[key]]
  if (!is.null(cached)) return(cached)

  is_composite <- tryCatch({
    reg <- classification_registry()
    row <- reg[reg$id == system, , drop = FALSE]
    nrow(row) > 0L && isTRUE(row$is_composite[[1L]])
  }, error = function(e) FALSE)

  data <- tryCatch(
    get_classification(system, version, level = NULL),
    error = function(e) NULL
  )
  if (is.null(data) || nrow(data) == 0L) return(NULL)

  lv <- as.character(data$level)
  ok <- !is.na(lv) & nzchar(lv)
  if (!any(ok)) return(NULL)

  depth <- tapply(nchar(as.character(data$code[ok])), lv[ok],
                  function(x) stats::median(x, na.rm = TRUE))
  depth <- depth[order(depth)]

  kind <- if (is_composite) {
    "composite"
  } else if (length(unique(as.numeric(depth))) <= 1L) {
    "fixed_width"
  } else {
    "hierarchical"
  }

  detailed <- if (identical(kind, "hierarchical")) names(depth)[[length(depth)]] else NA_character_

  out <- list(levels = names(depth), depth = depth, detailed = detailed, kind = kind)
  .assistant_level_cache[[key]] <- out
  out
}

#' Coding-level semantics for ONE verified classification code.
#'
#' @param system,version,code character(1). `version` NULL resolves the
#'   registry's current edition.
#'
#' @return list(found, system, version, code, label, classification_level,
#'   level_display, code_depth, coding_role, is_detailed_coding_level,
#'   parent_code, detailed_level_name) or list(found = FALSE, ...).
#'   Never errors.
assistant_coding_level <- function(system, version = NULL, code) {
  impl <- function() {
    system_chr <- .assistant_scalar_chr(system)
    code_chr <- .assistant_scalar_chr(code)
    if (is.null(system_chr) || is.null(code_chr)) {
      return(.assistant_error_result(
        "A classification system id and a code are both required."
      ))
    }
    version_chr <- .assistant_resolve_version(system_chr, version)

    hit <- get_classification_entry(system_chr, version_chr, code_chr)
    if (nrow(hit) == 0L) {
      return(list(
        found = FALSE, system = system_chr, version = version_chr,
        requested_code = code_chr,
        message = sprintf(
          "Code '%s' could not be verified in %s %s, so no level can be reported.",
          code_chr, toupper(system_chr), version_chr
        )
      ))
    }

    row <- utils::head(hit, 1L)
    lvl <- as.character(row$level[[1L]])
    map <- assistant_level_map(system_chr, version_chr)

    role <- if (is.null(map)) {
      "not_applicable"
    } else if (identical(map$kind, "composite")) {
      "component"
    } else if (identical(map$kind, "fixed_width")) {
      "structural"
    } else if (!is.na(map$detailed) && identical(lvl, map$detailed)) {
      "detailed"
    } else {
      "aggregate"
    }

    list(
      found = TRUE,
      system = system_chr,
      version = version_chr,
      code = as.character(row$code[[1L]]),
      label = as.character(row$label[[1L]]),
      classification_level = lvl,
      level_display = assistant_level_display(lvl),
      code_depth = nchar(as.character(row$code[[1L]])),
      coding_role = role,
      is_detailed_coding_level = identical(role, "detailed"),
      parent_code = as.character(row$parent_code[[1L]]),
      detailed_level_name = if (is.null(map)) NA_character_ else map$detailed
    )
  }
  .assistant_tool_try(impl(), "assistant_coding_level")
}

#' Human-readable form of a canonical level string ("unit_group" ->
#' "Unit Group", "sub-class" -> "Sub-class"). Presentation only; the
#' canonical value is always carried alongside it.
assistant_level_display <- function(level) {
  lvl <- as.character(level)
  if (length(lvl) != 1L || is.na(lvl) || !nzchar(lvl)) return(NA_character_)
  # "sub_major_group" -> "Sub-major Group" (not "Sub Major Group"): PSA
  # writes these compound level names hyphenated, and the spec states the
  # PSOC ladder as Major / Sub-major / Minor / Unit Group.
  lvl <- gsub("^sub[_ ]", "sub-", lvl)
  parts <- strsplit(gsub("_", " ", lvl), " ", fixed = TRUE)[[1L]]
  parts <- parts[nzchar(parts)]
  paste(toupper(substr(parts, 1L, 1L)), substr(parts, 2L, nchar(parts)),
        sep = "", collapse = " ")
}

#' Verified child codes of one code, for showing what an AGGREGATE code
#' decomposes into (spec 12.1: "PSOC 833 -> optionally list child Unit
#' Groups"). Reads `parent_code` from the canonical repository only.
#'
#' @return list(system, version, parent_code, count, children = list of
#'   list(code, label, level)) -- possibly empty. Never errors.
assistant_child_codes <- function(system, version = NULL, code, limit = ASSISTANT_DEFAULT_LIMIT) {
  impl <- function() {
    system_chr <- .assistant_scalar_chr(system)
    code_chr <- .assistant_scalar_chr(code)
    if (is.null(system_chr) || is.null(code_chr)) {
      return(.assistant_error_result(
        "A classification system id and a code are both required."
      ))
    }
    version_chr <- .assistant_resolve_version(system_chr, version)
    limit_int <- .assistant_clamp_limit(limit)

    data <- get_classification(system_chr, version_chr, level = NULL)
    kids <- data[!is.na(data$parent_code) & data$parent_code == code_chr, , drop = FALSE]
    total <- nrow(kids)
    kids <- utils::head(kids, limit_int)

    list(
      system = system_chr,
      version = version_chr,
      parent_code = code_chr,
      count = total,
      children = .assistant_rows(kids, c("code", "label", "level"))
    )
  }
  .assistant_tool_try(impl(), "assistant_child_codes")
}
