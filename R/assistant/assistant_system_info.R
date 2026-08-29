# RM orchestration hardening -- canonical classification-system metadata.
#
# DEFECT this file exists to fix: live RM answered "What is the difference
# between PSCC and PSCCS?", "What are the components of PTSCS?" and "What
# are the components of PSCrCS?" from unverified model knowledge, because
# the only tools available were `assistant_search_classification()` (which
# searches for classification ENTRIES, not system-level facts) and
# `assistant_classification_registry()` (a compact whole-registry listing
# that deliberately omits `available_components`, so it could not ground a
# components question even if the model chose the right tool).
#
# This wraps `classification_registry()` -- the SAME single source of truth
# every other consumer (Search selector, Sources deck, the RM tool enum)
# already reads -- filtered to one system and widened to include the fields
# a system-identity or components question needs. It does not maintain a
# second, hand-written list of system facts: every field returned here is
# already computed by the registry from the adapters, so it cannot drift
# out of sync with them.
#
# Only fields the registry can actually support are exposed. No "purpose"
# or "scope" prose is invented here -- `display_name` already states a
# system's subject (e.g. "Philippine Tourism Statistical Classification
# System"), and inventing additional descriptive text not sourced from the
# repository would be exactly the "unsupported latent knowledge" this tool
# exists to prevent.

ASSISTANT_SYSTEM_INFO_FIELDS <- c(
  "id", "display_name", "short_name", "category",
  "current_version", "available_versions", "available_levels",
  "available_components", "is_composite", "source", "source_url"
)

#' Verified canonical metadata for ONE classification system.
#'
#' @param system character(1). A `classification_registry()$id` value.
#'
#' @return list(found = TRUE, <ASSISTANT_SYSTEM_INFO_FIELDS>) or
#'   list(found = FALSE, requested_system, message, known_systems) or
#'   list(error = TRUE, message = ...).
assistant_get_classification_system_info <- function(system) {
  impl <- function() {
    system_chr <- .assistant_scalar_chr(system)
    if (is.null(system_chr)) {
      return(.assistant_error_result("A classification system id is required."))
    }

    reg <- classification_registry()
    row <- reg[reg$id == tolower(system_chr), , drop = FALSE]

    if (nrow(row) == 0L) {
      return(list(
        found = FALSE,
        requested_system = system_chr,
        message = sprintf(
          paste(
            "'%s' is not a classification system this application carries.",
            "Do not answer from model memory. Known systems: %s."
          ),
          system_chr, paste(reg$id, collapse = ", ")
        ),
        known_systems = reg$id
      ))
    }

    out <- .assistant_rows(utils::head(row, 1L), ASSISTANT_SYSTEM_INFO_FIELDS)[[1L]]
    c(list(found = TRUE), out)
  }
  .assistant_tool_try(impl(), "assistant_get_classification_system_info")
}
