# RM Classification Assistant — read-only tool wrappers (Wave 1B).
#
# These functions are the ONLY channel through which a classification code
# may legitimately reach the model. The milestone's non-negotiable rule
# (spec section 2.1) is:
#
#   NO RETRIEVED CLASSIFICATION CODE = NO CLASSIFICATION CODE PRESENTED
#   AS THE ANSWER.
#
# Everything here serves that rule:
#
#   * every code returned comes verbatim from R/repository.R (the official
#     local PSA-derived artifacts) — nothing here invents, reformats,
#     fuzzy-matches or "did-you-mean"s a code;
#   * codes are handled as character throughout, so leading zeros survive
#     (PSIC "01111" is never 1111);
#   * a miss is reported as `found = FALSE`, never as a near match;
#   * current/archived `status` is passed through untouched;
#   * results are bounded so the model can never pull a whole table;
#   * the common-pairing workbook is returned as *supporting evidence* with
#     a caveat carried in the tool RESULT itself (spec 2.3 / 5.4) — a long
#     conversation can drown out a system prompt, it cannot rewrite a tool
#     result;
#   * missing evidence artifacts degrade to an explicit `available = FALSE`
#     with an instruction NOT to substitute model memory (spec 21).
#
# Security (spec 22): every tool is strictly read-only. No writes, no shell,
# no network, no eval/parse of model input, no model-driven file paths, and
# no raw R error or stack trace ever reaches the model — repository-layer
# errors are converted into short structured results and the technical
# detail is logged server-side with message().

# ---------------------------------------------------------------------------
# Bounds and constants
# ---------------------------------------------------------------------------

# Default number of rows any assistant tool hands the model.
ASSISTANT_DEFAULT_LIMIT <- 6L

# Hard ceiling. The model may ask for more than the default, but never for
# the whole table (spec 5.1: "Do not return 100 search rows to the LLM").
ASSISTANT_MAX_LIMIT <- 25L

# Description truncation for compact search results.
ASSISTANT_SHORT_DESCRIPTION_CHARS <- 200L

# Compact field sets. Kept as constants so the tests can assert exactly
# which columns are (and are not) exposed to the model.
ASSISTANT_SEARCH_FIELDS <- c(
  "system", "version", "level", "code", "label",
  "short_description", "status", "source"
)

ASSISTANT_ENTRY_FIELDS <- c(
  "system", "version", "level", "code", "label", "description",
  "parent_code", "status", "source", "source_url"
)

ASSISTANT_REGISTRY_FIELDS <- c(
  "id", "display_name", "current_version", "available_versions", "category"
)

ASSISTANT_PAIRING_FIELDS <- c(
  "occupation", "confirmed_psoc", "confirmed_psoc_label",
  "psoc_confidence", "psoc_provenance", "psoc_curation_note",
  "source_industry", "original_psic",
  "psic_rev5_code", "psic_rev5_rule", "mapping_confidence", "mapping_note",
  "has_fixed_psic"
)

# The 12 rule keys defined by spec 5.5. Validated locally so an unknown
# topic returns the menu instead of erroring or being guessed at.
ASSISTANT_PSIC_RULE_TOPICS <- c(
  "unit_of_classification",
  "economic_activity",
  "principal_activity",
  "secondary_activity",
  "ancillary_activity",
  "independent_mixed",
  "top_down_bottom_up",
  "horizontal_integration",
  "vertical_integration",
  "outsourced_subcontracted",
  "vague_information",
  "common_mistakes"
)

# Carried in EVERY pairings result (spec 2.3, 5.4).
ASSISTANT_PAIRING_CAVEAT <- paste(
  "Supporting evidence only.",
  "These are reviewed common PSOC-PSIC pairings, not an authority.",
  "A pairing does NOT establish a particular establishment's PSIC -",
  "the establishment's actual economic activity does.",
  "Any code taken from here must still be verified with",
  "assistant_get_classification_entry() before it is presented as an answer."
)

# Returned when the PSIC rules artifact is absent (spec 21).
ASSISTANT_NO_RULES_REASON <- paste(
  "The detailed PSIC classification-rule artifact is not available.",
  "Do NOT substitute model memory and do NOT invent PSIC methodology.",
  "Tell the user that detailed PSIC classification-rule assistance is",
  "unavailable right now, fall back to official classification text search",
  "via assistant_search_classification(), and ask for the establishment's",
  "actual economic activity when it is needed."
)

# Returned when the common-pairings artifact is absent (spec 21). The
# assistant keeps working off official search; it just loses this evidence.
ASSISTANT_NO_PAIRINGS_REASON <- paste(
  "The reviewed common PSOC-PSIC pairing evidence is not available.",
  "Do NOT invent pairings from memory.",
  "Continue using official classification search and verification instead."
)

ASSISTANT_GENERIC_ERROR_MESSAGE <- paste(
  "The application could not complete that classification lookup just now.",
  "Do not guess a code. Tell the user it could not be verified and suggest",
  "the main search."
)

# ---------------------------------------------------------------------------
# Internal helpers (not exposed to the model)
# ---------------------------------------------------------------------------

#' Clamp a model-supplied limit into [1, ASSISTANT_MAX_LIMIT].
#'
#' A missing/NA/non-numeric limit falls back to `default`. This is the
#' guard that stops the model from requesting the entire classification
#' table one tool call at a time.
.assistant_clamp_limit <- function(limit, default = ASSISTANT_DEFAULT_LIMIT,
                                   max_limit = ASSISTANT_MAX_LIMIT) {
  if (is.null(limit) || length(limit) != 1L) {
    return(as.integer(default))
  }
  suppressWarnings(limit <- as.numeric(limit))
  if (is.na(limit)) {
    return(as.integer(default))
  }
  limit <- floor(limit)
  if (limit < 1) {
    return(1L)
  }
  if (limit > max_limit) {
    return(as.integer(max_limit))
  }
  as.integer(limit)
}

#' Truncate a character vector for compact tool output. NA stays NA and is
#' never turned into the string "NA".
.assistant_truncate <- function(x, n = ASSISTANT_SHORT_DESCRIPTION_CHARS) {
  x <- as.character(x)
  long <- !is.na(x) & nchar(x) > n
  x[long] <- paste0(substr(x[long], 1L, n), "...")
  x
}

#' Coerce a single model-supplied scalar to a length-1 character or NULL.
#' Never numeric — classification codes keep their leading zeros.
.assistant_scalar_chr <- function(x) {
  if (is.null(x) || length(x) != 1L) {
    return(NULL)
  }
  if (is.na(x)) {
    return(NULL)
  }
  x <- as.character(x)
  if (!nzchar(trimws(x))) {
    return(NULL)
  }
  x
}

#' Structured, user-safe error result.
.assistant_error_result <- function(message) {
  list(error = TRUE, message = message)
}

#' Run a tool body, converting any R condition into a short structured
#' result. Repository validation errors ("Unsupported system/version/level
#' ... Available: ...") are genuinely useful to the model and are raised
#' with `call. = FALSE`, so they are passed through; anything else becomes a
#' generic message and the technical detail is logged server-side only.
#' No stack trace, no "Error in <call>" text ever reaches the model.
.assistant_tool_try <- function(expr, context = "assistant tool") {
  tryCatch(
    expr,
    error = function(e) {
      detail <- conditionMessage(e)
      message(sprintf("[rm-assistant] %s failed: %s", context, detail))
      safe <- grepl("^Unsupported (classification system|version|level)", detail)
      msg <- if (safe) {
        gsub("[\r\n]+", " ", detail)
      } else {
        ASSISTANT_GENERIC_ERROR_MESSAGE
      }
      .assistant_error_result(msg)
    }
  )
}

#' Resolve the CURRENT version for a system from the registry.
#'
#' Never silently picks an archived edition: psoc -> "2022", psic -> "2026".
#' Raises the repository's own "Unsupported classification system" error for
#' an unknown system, which `.assistant_tool_try()` then converts.
.assistant_current_version <- function(system) {
  reg <- classification_registry()
  row <- reg[reg$id == system, , drop = FALSE]
  if (nrow(row) == 0L) {
    stop(sprintf(
      "Unsupported classification system '%s'. Available systems: %s",
      system, paste(reg$id, collapse = ", ")
    ), call. = FALSE)
  }
  as.character(row$current_version[[1]])
}

.assistant_resolve_version <- function(system, version) {
  version <- .assistant_scalar_chr(version)
  if (is.null(version)) .assistant_current_version(system) else version
}

#' Convert a data frame into a list-of-row-lists for compact JSON output.
#' NA values stay NA (serialized as null) rather than becoming "NA".
.assistant_rows <- function(df, fields) {
  fields <- intersect(fields, names(df))
  if (nrow(df) == 0L) {
    return(list())
  }
  lapply(seq_len(nrow(df)), function(i) {
    row <- lapply(fields, function(f) {
      value <- df[[f]][[i]]
      if (is.list(value)) value <- unlist(value, use.names = FALSE)
      value
    })
    names(row) <- fields
    row
  })
}

# --- evidence-artifact accessors (owned by Workstream A / assistant_data.R) --
#
# Looked up dynamically so this file loads (and its non-evidence tools keep
# working) even when assistant_data.R is absent. The accessors themselves
# return NULL when their artifact is missing; they never error.

.assistant_data_accessor <- function(name) {
  fn <- get0(name, mode = "function", ifnotfound = NULL)
  if (is.null(fn)) {
    return(NULL)
  }
  tryCatch(
    fn(),
    error = function(e) {
      message(sprintf("[rm-assistant] %s() failed: %s", name, conditionMessage(e)))
      NULL
    }
  )
}

.assistant_pairings_data <- function() .assistant_data_accessor("assistant_common_pairings")

.assistant_rules_data <- function() .assistant_data_accessor("assistant_psic_rules")

#' Case-insensitive LITERAL substring test. Model input is never treated as
#' a regular expression (fixed = TRUE). NA haystack values never match.
.assistant_contains <- function(haystack, needle) {
  haystack <- as.character(haystack)
  hit <- rep(FALSE, length(haystack))
  ok <- !is.na(haystack)
  hit[ok] <- grepl(tolower(needle), tolower(haystack[ok]), fixed = TRUE)
  hit
}

# ---------------------------------------------------------------------------
# 5.1 assistant_search_classification()
# ---------------------------------------------------------------------------

#' Search one official classification for candidate codes.
#'
#' Thin, bounded wrapper over `search_classification()`. Returns at most
#' `limit` compact candidates (default 6, hard ceiling 25) plus
#' `total_matches` so the model knows it is looking at a shortlist.
#'
#' @param system character(1). One of `classification_registry()$id`.
#' @param query character(1) search text.
#' @param version character(1) or NULL. NULL resolves the system's CURRENT
#'   version from the registry — never an archived edition.
#' @param level character(1) or NULL hierarchy level filter.
#' @param limit integer(1), clamped to [1, 25].
#'
#' @return list(system, version, level, query, total_matches, returned,
#'   truncated, results) or list(error = TRUE, message = ...).
assistant_search_classification <- function(system, query, version = NULL,
                                            level = NULL, limit = ASSISTANT_DEFAULT_LIMIT) {
  impl <- function() {
    system <- .assistant_scalar_chr(system)
    if (is.null(system)) {
      return(.assistant_error_result("A classification system id is required."))
    }
    version <- .assistant_resolve_version(system, version)
    level <- .assistant_scalar_chr(level)
    query_chr <- .assistant_scalar_chr(query)
    limit <- .assistant_clamp_limit(limit)

    # Fetch the full ranked match set once so `total_matches` is honest,
    # then hand the model only the shortlist.
    full <- search_classification(
      system = system, version = version, query = query_chr,
      level = level, limit = 1e6
    )
    total <- nrow(full)
    shortlist <- utils::head(full, limit)

    shortlist$short_description <- .assistant_truncate(shortlist$description)

    list(
      system = system,
      version = version,
      level = if (is.null(level)) NA_character_ else level,
      query = if (is.null(query_chr)) NA_character_ else query_chr,
      total_matches = total,
      returned = nrow(shortlist),
      truncated = total > nrow(shortlist),
      results = .assistant_rows(shortlist, ASSISTANT_SEARCH_FIELDS)
    )
  }
  .assistant_tool_try(impl(), "assistant_search_classification")
}

# ---------------------------------------------------------------------------
# 5.2 assistant_get_classification_entry()
# ---------------------------------------------------------------------------

#' Verify one exact classification code against the official local data.
#'
#' THE grounding tool. Call it before presenting any code as an answer.
#' Matching is exact, case-sensitive string comparison — codes are never
#' coerced to numbers, so leading zeros are preserved, and there is
#' deliberately NO fuzzy match and NO "did you mean" suggestion: an unknown
#' code comes back `found = FALSE` and the requested value is echoed only
#' under `requested_code`, never as a validated `code`.
#'
#' @param system character(1).
#' @param version character(1) or NULL (NULL resolves the current version).
#' @param code character(1) exact official code.
#'
#' @return list(found = TRUE, <ASSISTANT_ENTRY_FIELDS>) or
#'   list(found = FALSE, system, version, requested_code, message) or
#'   list(error = TRUE, message = ...).
assistant_get_classification_entry <- function(system, version = NULL, code) {
  impl <- function() {
    system <- .assistant_scalar_chr(system)
    if (is.null(system)) {
      return(.assistant_error_result("A classification system id is required."))
    }
    code_chr <- .assistant_scalar_chr(code)
    version <- .assistant_resolve_version(system, version)

    if (is.null(code_chr)) {
      return(list(
        found = FALSE,
        system = system,
        version = version,
        requested_code = NA_character_,
        message = "No code was supplied, so nothing could be verified."
      ))
    }

    hit <- get_classification_entry(system, version, code_chr)

    if (nrow(hit) == 0L) {
      return(list(
        found = FALSE,
        system = system,
        version = version,
        requested_code = code_chr,
        message = sprintf(
          paste(
            "Code '%s' could not be verified in %s %s.",
            "It is NOT a confirmed classification code.",
            "Do not present it as an answer and do not offer a similar code",
            "that has not itself been verified."
          ),
          code_chr, toupper(system), version
        )
      ))
    }

    # A code is not guaranteed unique within one system+version: the
    # archived phscs PSOC 2012 edition, for example, carries 13 distinct
    # one-character codes where only 10 major groups exist, so
    # get_classification_entry("psoc", "2012", "1") really does return
    # more than one row. Report the first match but never silently hide
    # the others -- concealing a second official entry would let the model
    # present a partial answer as if it were the whole verified truth.
    extra <- nrow(hit) - 1L
    row <- .assistant_rows(utils::head(hit, 1L), ASSISTANT_ENTRY_FIELDS)[[1L]]
    out <- c(list(found = TRUE), row)

    if (extra > 0L) {
      other_levels <- unique(hit$level[-1L])
      out$additional_matches <- extra
      out$additional_matches_note <- sprintf(
        paste(
          "This code also appears %d more time(s) in %s %s (level(s): %s).",
          "Mention that the code is not unique in this edition rather than",
          "presenting the first match as the only entry."
        ),
        extra, toupper(system), version, paste(other_levels, collapse = ", ")
      )
    }

    out
  }
  .assistant_tool_try(impl(), "assistant_get_classification_entry")
}

# ---------------------------------------------------------------------------
# 5.3 assistant_classification_registry()
# ---------------------------------------------------------------------------

#' Compact list of the classification systems the application carries.
#'
#' Deliberately omits `adapter`, `available_levels`, `supports_history` and
#' the rest of the metadata graph (spec 5.3).
#'
#' @return list(systems = list(list(id, display_name, current_version,
#'   available_versions, category), ...)) or list(error = TRUE, ...).
assistant_classification_registry <- function() {
  impl <- function() {
    reg <- classification_registry()
    list(
      count = nrow(reg),
      systems = .assistant_rows(reg, ASSISTANT_REGISTRY_FIELDS)
    )
  }
  .assistant_tool_try(impl(), "assistant_classification_registry")
}

# ---------------------------------------------------------------------------
# 5.4 assistant_search_common_pairings()
# ---------------------------------------------------------------------------

#' Search the reviewed common PSOC-PSIC pairing evidence.
#'
#' Supporting evidence ONLY (spec 2.3). Rows where no fixed PSIC exists are
#' preserved as no-code evidence: `psic_rev5_code` stays NA and
#' `has_fixed_psic` stays FALSE — they are never filled from
#' `original_psic` and never dropped. Multi-code strings ("96211 / 96220")
#' and ranges ("01171-01189") pass through verbatim.
#'
#' Each row carries two independent judgements that must not be conflated:
#' `psoc_confidence` grades the OCCUPATION mapping and `mapping_confidence`
#' grades the PSIC mapping. `psoc_provenance` is `"source_workbook"` for the
#' published mapping or `"curated"` where the application has recorded an
#' approved manual correction; curated rows carry their rationale, and any
#' retained ambiguity, in `psoc_curation_note`. `confirmed_psoc_label` is
#' the official PSOC 2022 title resolved from the canonical repository at
#' build time, so it can never disagree with the classification of record.
#'
#' All filters are case-insensitive LITERAL substrings (never regex) and are
#' AND-combined.
#'
#' @param occupation,psoc_code,industry_context,original_psic character(1)
#'   filters or NULL.
#' @param limit integer(1), clamped to [1, 25].
#' @param .pairings Test/injection seam. OMIT it to use the real artifact;
#'   pass NULL explicitly to simulate a missing artifact. Never exposed to
#'   the model.
#'
#' @return list(available, total_matches, returned, evidence_caveat,
#'   results) or list(available = FALSE, reason = ...).
assistant_search_common_pairings <- function(occupation = NULL, psoc_code = NULL,
                                             industry_context = NULL,
                                             original_psic = NULL,
                                             limit = ASSISTANT_DEFAULT_LIMIT,
                                             .pairings) {
  if (missing(.pairings)) {
    .pairings <- .assistant_pairings_data()
  }

  impl <- function() {
    if (is.null(.pairings) || !is.data.frame(.pairings) || nrow(.pairings) == 0L) {
      return(list(
        available = FALSE,
        reason = ASSISTANT_NO_PAIRINGS_REASON
      ))
    }

    data <- .pairings
    limit <- .assistant_clamp_limit(limit)

    filters <- list(
      occupation = occupation,
      confirmed_psoc = psoc_code,
      source_industry = industry_context,
      original_psic = original_psic
    )

    keep <- rep(TRUE, nrow(data))
    applied <- character(0)
    for (col in names(filters)) {
      needle <- .assistant_scalar_chr(filters[[col]])
      if (is.null(needle)) next
      applied <- c(applied, col)
      if (!col %in% names(data)) {
        keep <- keep & FALSE
        next
      }
      keep <- keep & .assistant_contains(data[[col]], needle)
    }

    matched <- data[keep, , drop = FALSE]

    # Preserve the deliberate no-fixed-PSIC signal. Derive the flag only
    # when the artifact does not carry it; never invent a code.
    if (!"has_fixed_psic" %in% names(matched)) {
      matched$has_fixed_psic <- if ("psic_rev5_code" %in% names(matched)) {
        !is.na(matched$psic_rev5_code)
      } else {
        rep(NA, nrow(matched))
      }
    }

    total <- nrow(matched)
    shortlist <- utils::head(matched, limit)

    list(
      available = TRUE,
      filters_applied = if (length(applied)) applied else NA_character_,
      total_matches = total,
      returned = nrow(shortlist),
      truncated = total > nrow(shortlist),
      evidence_caveat = ASSISTANT_PAIRING_CAVEAT,
      results = .assistant_rows(shortlist, ASSISTANT_PAIRING_FIELDS)
    )
  }
  .assistant_tool_try(impl(), "assistant_search_common_pairings")
}

# ---------------------------------------------------------------------------
# 5.5 assistant_get_psic_rule()
# ---------------------------------------------------------------------------

#' Retrieve ONE compact PSIC classification rule by topic.
#'
#' Never returns all 12 rules (spec 13.2). An unknown topic returns the
#' valid-topic menu instead of erroring or being guessed at. When the rules
#' artifact is missing, the result explicitly instructs that model-memory
#' methodology must NOT be substituted (spec 21).
#'
#' @param topic character(1). One of `ASSISTANT_PSIC_RULE_TOPICS`.
#' @param .rules Test/injection seam. OMIT to use the real artifact; pass
#'   NULL explicitly to simulate a missing artifact. Not exposed to the model.
#'
#' @return list(available = TRUE, found = TRUE, topic, title, rule, example)
#'   or list(found = FALSE, message, valid_topics) or
#'   list(available = FALSE, reason = ...).
assistant_get_psic_rule <- function(topic, .rules) {
  if (missing(.rules)) {
    .rules <- .assistant_rules_data()
  }

  impl <- function() {
    if (is.null(.rules) || !is.data.frame(.rules) || nrow(.rules) == 0L) {
      return(list(
        available = FALSE,
        reason = ASSISTANT_NO_RULES_REASON
      ))
    }

    topic_chr <- .assistant_scalar_chr(topic)
    if (is.null(topic_chr) || !topic_chr %in% ASSISTANT_PSIC_RULE_TOPICS) {
      return(list(
        available = TRUE,
        found = FALSE,
        message = paste(
          "Unknown PSIC rule topic. Call this tool again with exactly one of",
          "the valid topics listed here. Do not invent a rule."
        ),
        valid_topics = ASSISTANT_PSIC_RULE_TOPICS
      ))
    }

    hit <- .rules[!is.na(.rules$topic) & .rules$topic == topic_chr, , drop = FALSE]
    if (nrow(hit) == 0L) {
      return(list(
        available = TRUE,
        found = FALSE,
        message = sprintf(
          "PSIC rule topic '%s' is not present in the local rules artifact. Do not substitute model memory.",
          topic_chr
        ),
        valid_topics = ASSISTANT_PSIC_RULE_TOPICS
      ))
    }

    hit <- utils::head(hit, 1L)
    row <- .assistant_rows(hit, c("topic", "title", "rule", "example"))[[1L]]
    c(list(available = TRUE, found = TRUE), row)
  }
  .assistant_tool_try(impl(), "assistant_get_psic_rule")
}

# ---------------------------------------------------------------------------
# 5.6 assistant_lookup_synonyms() — NOT a registered tool in V1
# ---------------------------------------------------------------------------

#' Stub. No approved curated synonym source exists in V1, so this is
#' deliberately NOT registered in `rm_assistant_tools()` — the model must
#' not be given a synonym capability that would have to be fabricated.
#' Kept only so the degraded state is explicit and testable.
assistant_lookup_synonyms <- function(term = NULL, language = NULL,
                                      system = NULL, limit = 8L) {
  list(
    available = FALSE,
    reason = paste(
      "No approved curated multilingual synonym source exists in this",
      "version. Do not fabricate synonym mappings; use",
      "assistant_search_classification() with the user's own wording and",
      "with plausible English equivalents instead."
    )
  )
}

# ---------------------------------------------------------------------------
# ellmer tool registration
# ---------------------------------------------------------------------------

# The exact set of tools exposed to the model. Anything not on this list is
# not callable by the LLM. Tested, so a future edit cannot silently add a
# mutating tool.
RM_ASSISTANT_TOOL_NAMES <- c(
  "assistant_search_classification",
  "assistant_get_classification_entry",
  "assistant_classification_registry",
  "assistant_search_common_pairings",
  "assistant_get_psic_rule"
)

.assistant_read_only_annotations <- function() {
  ellmer::tool_annotations(
    read_only_hint = TRUE,
    open_world_hint = FALSE,
    idempotent_hint = TRUE,
    destructive_hint = FALSE
  )
}

#' Build the registered `ellmer::tool()` objects for the RM assistant.
#'
#' Every wrapper below is a thin lambda whose formals match its declared
#' schema exactly — the `.pairings` / `.rules` injection seams are NOT part
#' of any schema, so the model can neither see nor set them.
#'
#' @return A list of `ellmer::ToolDef` objects for `client$set_tools()`.
rm_assistant_tools <- function() {
  if (!requireNamespace("ellmer", quietly = TRUE)) {
    stop("Package 'ellmer' is required to register RM assistant tools.", call. = FALSE)
  }
  annotations <- .assistant_read_only_annotations()

  systems_enum <- c("psgc", "psic", "psoc", "psced", "pcoicop", "pcpc", "psccs")

  list(
    ellmer::tool(
      function(system, query, version = NULL, level = NULL, limit = 6L) {
        assistant_search_classification(
          system = system, query = query, version = version,
          level = level, limit = limit
        )
      },
      paste(
        "Search one official Philippine statistical classification for candidate codes.",
        "Use this to find candidates from the user's description of an occupation,",
        "economic activity, product, place or field of education.",
        "Returns a short ranked shortlist (default 6) plus the total number of matches.",
        "Always verify the chosen candidate with assistant_get_classification_entry()",
        "before presenting it as an answer."
      ),
      arguments = list(
        system = ellmer::type_enum(
          values = systems_enum,
          description = "Classification system id. psoc = occupations, psic = industries/economic activity, psgc = geography, psced = education, pcoicop/pcpc/psccs = products and consumption."
        ),
        query = ellmer::type_string(
          "Search text: an occupation title, activity description, product name or code fragment."
        ),
        version = ellmer::type_string(
          "Optional edition, e.g. '2022' for PSOC or '2026' for PSIC. Omit to use the current edition. Only supply this when the user explicitly asks about an older edition.",
          required = FALSE
        ),
        level = ellmer::type_string(
          "Optional hierarchy level filter, e.g. 'unit_group' or 'sub-class'. Omit unless the user asked for a specific level.",
          required = FALSE
        ),
        limit = ellmer::type_integer(
          "Maximum candidates to return. Default 6, maximum 25.",
          required = FALSE
        )
      ),
      name = "assistant_search_classification",
      annotations = annotations
    ),

    ellmer::tool(
      function(system, code, version = NULL) {
        assistant_get_classification_entry(system = system, version = version, code = code)
      },
      paste(
        "Verify one exact classification code against the application's official data.",
        "This is the mandatory final step before stating any code as the answer.",
        "Returns found = true with the official label and provenance, or found = false",
        "if the code does not exist in that system and edition.",
        "If found is false you MUST tell the user the code could not be verified;",
        "never present it, and never offer a similar code you have not verified."
      ),
      arguments = list(
        system = ellmer::type_enum(
          values = systems_enum,
          description = "Classification system id."
        ),
        code = ellmer::type_string(
          "The exact code as a string, keeping any leading zeros (e.g. '01111')."
        ),
        version = ellmer::type_string(
          "Optional edition. Omit to use the current edition.",
          required = FALSE
        )
      ),
      name = "assistant_get_classification_entry",
      annotations = annotations
    ),

    ellmer::tool(
      function() {
        assistant_classification_registry()
      },
      paste(
        "List the classification systems this application carries, with each one's",
        "current edition and available editions.",
        "Use it when the user asks which classification applies to their question."
      ),
      arguments = list(),
      name = "assistant_classification_registry",
      annotations = annotations
    ),

    ellmer::tool(
      function(occupation = NULL, psoc_code = NULL, industry_context = NULL,
               original_psic = NULL, limit = 6L) {
        assistant_search_common_pairings(
          occupation = occupation, psoc_code = psoc_code,
          industry_context = industry_context, original_psic = original_psic,
          limit = limit
        )
      },
      paste(
        "Look up reviewed COMMON PSOC-PSIC pairings as supporting evidence.",
        "This is evidence, not authority: a pairing never establishes a particular",
        "establishment's PSIC - only its actual economic activity does.",
        "Some rows deliberately have no fixed PSIC code; when has_fixed_psic is false,",
        "ask what the establishment actually does instead of supplying a code.",
        "psoc_confidence grades the OCCUPATION mapping; mapping_confidence grades the",
        "PSIC mapping - do not read one as the other. Rows with psoc_provenance",
        "'curated' are approved manual corrections and psoc_curation_note states the",
        "rationale and any ambiguity that still has to be resolved with the user.",
        "Any code found here must still be verified with assistant_get_classification_entry()."
      ),
      arguments = list(
        occupation = ellmer::type_string(
          "Occupation text to match as a case-insensitive substring.",
          required = FALSE
        ),
        psoc_code = ellmer::type_string(
          "Confirmed 2022 PSOC code to match, as a string.",
          required = FALSE
        ),
        industry_context = ellmer::type_string(
          "Industry or workplace context to match, e.g. 'government', 'school'.",
          required = FALSE
        ),
        original_psic = ellmer::type_string(
          "Original PSIC code or text to match, as a string.",
          required = FALSE
        ),
        limit = ellmer::type_integer(
          "Maximum rows to return. Default 6, maximum 25.",
          required = FALSE
        )
      ),
      name = "assistant_search_common_pairings",
      annotations = annotations
    ),

    ellmer::tool(
      function(topic) {
        assistant_get_psic_rule(topic = topic)
      },
      paste(
        "Retrieve ONE compact official PSIC classification rule by topic.",
        "Use it when PSIC reasoning is needed - principal versus secondary or",
        "ancillary activity, mixed or integrated activities, outsourcing, vague",
        "descriptions, or common mistakes.",
        "Request only the single topic you need. If the rules are unavailable, say so;",
        "do not substitute remembered methodology."
      ),
      arguments = list(
        topic = ellmer::type_enum(
          values = ASSISTANT_PSIC_RULE_TOPICS,
          description = "The PSIC rule topic to retrieve."
        )
      ),
      name = "assistant_get_psic_rule",
      annotations = annotations
    )
  )
}
