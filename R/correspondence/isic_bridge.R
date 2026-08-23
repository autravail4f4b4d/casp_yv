# Optional corroborating evidence source: the United Nations Statistics
# Division's official ISIC Rev.4 <-> Rev.5 correspondence table.
#
# WHY THIS EXISTS
# ----------------
# The source audit (docs/CORRESPONDENCE_SOURCES.md) found no official PSA
# PSIC 2019<->Revision 5 crosswalk, but did find a genuine, official,
# downloadable UN correspondence table between ISIC Rev.4 (which PSIC 2019
# is patterned on) and ISIC Rev.5 (which PSIC Revision 5 is patterned on).
# Per spec section 13/16, this UN table is usable as **derived** evidence
# for PSIC mappings -- never "official" for PSIC itself, since PSIC is a
# national adaptation of ISIC, not ISIC verbatim.
#
# THE CAVEAT THAT SHAPES HOW THIS IS USED
# -----------------------------------------
# Empirical spot-check during development (see docs/CORRESPONDENCE_SOURCES.md)
# found that PSIC does NOT always preserve ISIC's own numbering at a given
# class code: e.g. PSIC class "0113" is "Growing of corn" in both PSIC 2019
# and PSIC 2026, but ISIC Rev.4/Rev.5 class "0113" is "Growing of
# vegetables and melons, roots and tubers" -- a different concept entirely.
# PSIC reassigned that code nationally. Because of this, the bridge must
# never be trusted as a blind code-number lookup. `isic_bridge_supported()`
# below only credits the bridge when BOTH PSIC editions' own labels at that
# class position are themselves reasonably close to their respective ISIC
# titles at the same code (a "conformance" gate) -- i.e. only when PSIC
# actually appears to have followed ISIC's own numbering at that position
# do we trust ISIC's Rev.4->Rev.5 change history as informative about what
# happened to the PSIC counterpart.
#
# This file is used only at BUILD time (scripts/build_psic_correspondence.R).
# It is never called from the runtime service layer (R/correspondence/
# service.R only reads the already-built data/psic_2019_to_2026_correspondence.rds),
# so its dependency on `readxl` and on a data-raw/ source file never
# executes in production or in most tests.

ISIC_BRIDGE_XLSX_PATH <- "data-raw/ISIC4-5_Correspondence_Table.xlsx"
ISIC_BRIDGE_SOURCE_URL <- "https://unstats.un.org/unsd/classifications/Meetings/UNCEISC2024_2nd/Session_6_Bk_1_ISIC4-5_Correspondence_Table.xlsx"

# Same repo-root-vs-tests/testthat path resolution pattern used by
# adapter_psic_2026.R's `.psic2026_resolve_default_path()`.
.isic_bridge_resolve_default_path <- function(rel_path) {
  candidates <- c(rel_path, file.path("..", "..", rel_path))
  for (p in candidates) {
    if (file.exists(p)) return(p)
  }
  rel_path
}

#' Load the UN ISIC Rev.4<->Rev.5 correspondence table into build-time
#' lookup structures. Returns NULL (rather than erroring) if the source
#' workbook is not present -- callers must treat a NULL bridge as "no
#' corroborating evidence available" and fall back to hierarchy/label
#' evidence alone, never as a hard build failure, since the bridge is a
#' corroborating signal, not a required input.
#'
#' @return NULL, or a list with:
#'   - bridge_4to5: named list, ISIC Rev.4 class code (4-digit, no section
#'     letter) -> unique character vector of ISIC Rev.5 class codes.
#'   - isic4_titles, isic5_titles: named character vectors, code -> title.
load_isic_bridge <- function(path = NULL) {
  path <- if (is.null(path)) .isic_bridge_resolve_default_path(ISIC_BRIDGE_XLSX_PATH) else path
  if (!file.exists(path)) return(NULL)
  if (!requireNamespace("readxl", quietly = TRUE)) return(NULL)

  raw <- readxl::read_excel(path, sheet = "ISIC4-5", col_names = TRUE)
  # Columns, by position (see docs/CORRESPONDENCE_SOURCES.md for the full
  # header text): [1] ISIC4 code+section, [2] ISIC4 code, [3] ISIC4 title,
  # [4] ISIC5 code+section, [5] ISIC5 code, [6] ISIC5 title, [7] change
  # type, [8] change description.
  isic4_code <- as.character(raw[[2]])
  isic4_title <- as.character(raw[[3]])
  isic5_code <- as.character(raw[[5]])
  isic5_title <- as.character(raw[[6]])

  bridge_4to5 <- new.env(parent = emptyenv())
  for (i in seq_along(isic4_code)) {
    k <- isic4_code[i]
    if (is.na(k)) next
    existing <- bridge_4to5[[k]]
    bridge_4to5[[k]] <- unique(c(existing, isic5_code[i]))
  }

  isic4_titles <- stats::setNames(isic4_title, isic4_code)
  isic4_titles <- isic4_titles[!duplicated(names(isic4_titles))]
  isic5_titles <- stats::setNames(isic5_title, isic5_code)
  isic5_titles <- isic5_titles[!duplicated(names(isic5_titles))]

  list(
    bridge_4to5 = as.list(bridge_4to5),
    isic4_titles = isic4_titles,
    isic5_titles = isic5_titles
  )
}

#' Does the UN ISIC bridge corroborate a connection between a PSIC 2019
#' class-level code and a PSIC 2026 class-level code?
#'
#' Gated by the "conformance" check described in the file header: only
#' trusted when BOTH editions' own class-level labels are themselves close
#' to their respective ISIC titles at that same code (i.e. PSIC appears to
#' have followed ISIC's numbering there), so a PSIC-specific renumbering
#' (like the "0113 = corn" case) never spuriously borrows ISIC's change
#' history for an unrelated concept.
#'
#' @param bridge result of `load_isic_bridge()`, or NULL (always returns
#'   FALSE when NULL -- no evidence available).
#' @param psic19_class_code,psic26_class_code character(1) each, 4-digit
#'   PSIC class codes (no section letter).
#' @param psic19_class_label,psic26_class_label character(1) each, the
#'   PSIC label at that class code, used only for the conformance gate.
#'
#' @return logical(1).
isic_bridge_supported <- function(bridge,
                                   psic19_class_code, psic26_class_code,
                                   psic19_class_label, psic26_class_label) {
  if (is.null(bridge)) return(FALSE)
  if (is.na(psic19_class_code) || is.na(psic26_class_code)) return(FALSE)

  if (!psic19_class_code %in% names(bridge$isic4_titles)) return(FALSE)
  if (!psic26_class_code %in% names(bridge$isic5_titles)) return(FALSE)
  isic4_title <- unname(bridge$isic4_titles[[psic19_class_code]])
  isic5_title <- unname(bridge$isic5_titles[[psic26_class_code]])

  conformant19 <- jaccard_token_similarity(psic19_class_label, isic4_title) >=
    CORRESPONDENCE_SIMILARITY_THRESHOLDS$isic_conformance
  conformant26 <- jaccard_token_similarity(psic26_class_label, isic5_title) >=
    CORRESPONDENCE_SIMILARITY_THRESHOLDS$isic_conformance
  if (!conformant19 || !conformant26) return(FALSE)

  targets <- bridge$bridge_4to5[[psic19_class_code]]
  if (is.null(targets)) return(FALSE)
  psic26_class_code %in% targets
}
