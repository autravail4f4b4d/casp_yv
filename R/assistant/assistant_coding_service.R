# W1-B -- the mandatory deterministic coding service.
#
# THE AUTHORITY BOUNDARY. For a coding request this is the ONLY component
# permitted to choose a PSOC or PSIC code. It wraps the already-built
# deterministic layers (slot contract, controlled expansions, occupation
# examples, PSA survey guidance, context-consistency gate, hierarchy and
# coding-level policy, canonical verification) and converts their CANDIDATE
# output into a DECISION.
#
# The distinction matters and is the fix for a specific live failure
# (spec 11): retrieval for "barangay health worker" legitimately returns
# 3253, 5329 and 532. The model was shown all three and presented 3253 and
# 5329 as peers. A service that returns a decision emits selected_code =
# 3253 and an allowed_codes set of exactly {3253}; the peer never reaches
# the model at all.
#
# Three further server-side invariants live here rather than in the prompt:
#
#   * CURRENT EDITION ONLY. Archived rows can never be the authoritative
#     answer to an ordinary coding request (spec 17); the live build let
#     the model pass version = "2019" and receive status = "archived" rows.
#   * OUTSOURCING PRECONDITION runs BEFORE any PSIC retrieval (spec 15),
#     so "janitor deployed at a hospital through a manpower agency" asks
#     who pays the wage instead of asking whether the hospital is public.
#   * ALLOWED CODES are computed here, so the response guard has an
#     authoritative whitelist to check generated prose against.

ASSISTANT_CODING_STATUSES <- c("resolved", "clarification_required", "no_verified_match")

# Slots the service can ask for, in the order it will ask.
ASSISTANT_CODING_SLOTS <- c("wage_payer", "establishment_activity", "occupation")

.assistant_slot_status <- function(x) {
  if (is.null(x)) "not_requested" else x
}

# Turn one ranked candidate frame into a single decision.
#
# Selection order is already applied upstream (survey guidance, then exact
# example evidence, then detailed coding level, then retrieval rank), so
# the decision is simply "the top candidate" -- with one exception: when
# the set is a genuinely ambiguous sibling group the service refuses to
# pick and asks instead.
.assistant_select_from_slot <- function(slot) {
  none <- list(
    status = "no_verified_match", selected_code = NA_character_,
    selected_label = NA_character_, classification_level = NA_character_,
    level_display = NA_character_, coding_role = NA_character_,
    version = NA_character_, status_current = NA_character_,
    evidence_source = NA_character_, supported_aggregate_code = NA_character_,
    allowed = character(0), options = list()
  )
  if (is.null(slot) || length(slot$candidates) == 0L) return(none)

  # An unresolved detail question must not hand out a detailed child code.
  if (isTRUE(slot$detail_clarification_needed)) {
    agg <- slot$supported_aggregate_code
    agg_row <- NULL
    if (!is.na(agg)) {
      agg_row <- Filter(function(c) identical(c$code, agg), slot$candidates)
    }
    opts <- lapply(slot$detail_options, function(o) list(code = o$code, label = o$label))
    if (length(agg_row) > 0L) {
      a <- agg_row[[1L]]
      return(list(
        status = "clarification_required",
        selected_code = a$code, selected_label = a$label,
        classification_level = a$level, level_display = a$level_display,
        coding_role = a$coding_role, version = a$version,
        status_current = a$status, evidence_source = a$evidence_source,
        supported_aggregate_code = a$code,
        # Only the supported aggregate may be stated; the detailed children
        # are offered as bounded verified OPTIONS, never as final codes.
        allowed = a$code,
        options = opts
      ))
    }
    return(c(none, list(status = "clarification_required")))
  }

  top <- slot$candidates[[1L]]
  list(
    status = "resolved",
    selected_code = top$code,
    selected_label = top$label,
    classification_level = top$level,
    level_display = top$level_display,
    coding_role = top$coding_role,
    version = top$version,
    status_current = top$status,
    evidence_source = top$evidence_source,
    supported_aggregate_code = NA_character_,
    allowed = top$code,
    options = list()
  )
}

# Current-edition enforcement (spec 17). An archived row must never be the
# authoritative answer to an ordinary coding request.
.assistant_enforce_current <- function(sel, system, allow_archived) {
  if (isTRUE(allow_archived)) return(sel)
  if (identical(sel$status, "no_verified_match")) return(sel)
  st <- sel$status_current
  if (!is.na(st) && !identical(tolower(as.character(st)), "current")) {
    return(list(
      status = "no_verified_match",
      selected_code = NA_character_, selected_label = NA_character_,
      classification_level = NA_character_, level_display = NA_character_,
      coding_role = NA_character_, version = NA_character_,
      status_current = NA_character_, evidence_source = NA_character_,
      supported_aggregate_code = NA_character_,
      allowed = character(0), options = list(),
      note = sprintf(
        "The only %s match found is not from the current edition, so it was withheld.",
        toupper(system)
      )
    ))
  }
  sel
}

# --- employment arrangement vs. occupation title (UAT-RM-03) ---------------
#
# Wording that describes how a person is ENGAGED, not what work they do. No
# PSOC title contains any of it: it is establishment-side information, and
# the outsourcing precondition above is where it belongs.
#
# Deliberately short and whole-word. "contractor" is NOT here -- it is a
# real occupational head ("labour contractor") and stripping it would be
# the kind of silent title mangling this project forbids.
.ASSISTANT_OCCUPATION_ARRANGEMENT <- paste0(
  "\\b(outsourced|out-sourced|subcontracted|sub-contracted|contractual|",
  "contractualized|contractualised|job\\s*order|agency[- ]hired|",
  "agency[- ]based|casual|probationary|seconded)\\b"
)

#' The occupation title with employment-arrangement wording removed.
#'
#' Returns NULL when nothing was removed, or when removal would leave no
#' title at all -- "outsourced" on its own names no occupation, and must
#' keep asking rather than silently becoming a different question.
.assistant_occupation_without_arrangement <- function(occupation) {
  o <- .assistant_scalar_chr(occupation)
  if (is.null(o)) return(NULL)
  stripped <- gsub(.ASSISTANT_OCCUPATION_ARRANGEMENT, " ", tolower(o), perl = TRUE)
  stripped <- trimws(gsub("\\s+", " ", stripped))
  if (!nzchar(stripped)) return(NULL)
  if (identical(stripped, trimws(tolower(o)))) return(NULL)
  stripped
}

#' Did a slot selection fail to produce a verified code?
.assistant_slot_unresolved <- function(sel) {
  is.null(sel) || identical(sel$status, "no_verified_match") ||
    is.null(sel$selected_code) || is.na(sel$selected_code)
}

#' The authoritative coding service.
#'
#' @param occupation,establishment_activity character(1) or NULL.
#' @param requested_systems character vector, subset of c("psoc","psic").
#' @param wage_payer character(1) or NULL -- "establishment" or "agency",
#'   supplied once the outsourcing question has been answered.
#' @param allow_archived logical(1). TRUE only on an explicit historical
#'   request; never for ordinary current coding.
#'
#' @return the structured coding packet (spec 10). Never errors.
assistant_coding_service <- function(occupation = NULL,
                                     establishment_activity = NULL,
                                     requested_systems = c("psoc", "psic"),
                                     wage_payer = NULL,
                                     allow_archived = FALSE) {
  impl <- function() {
    systems <- intersect(tolower(as.character(requested_systems)), c("psoc", "psic"))
    if (length(systems) == 0L) systems <- c("psoc", "psic")

    occ_txt <- .assistant_scalar_chr(occupation)
    act_txt <- .assistant_scalar_chr(establishment_activity)
    payer <- .assistant_scalar_chr(wage_payer)

    slots <- assistant_slot_contract(occ_txt, act_txt)

    # ---- OUTSOURCING PRECONDITION, before any PSIC retrieval ----------
    outsourced <- isTRUE(slots$activity_outsourced) ||
      assistant_activity_mentions_outsourcing(occ_txt)
    payer_known <- !is.null(payer) &&
      grepl("establishment|agency|company|employer|hospital|school|manpower",
            tolower(payer))

    # ---- occupation half ----------------------------------------------
    #
    # PARTIAL-STATE PRESERVATION (UAT-RM-03). "outsourced janitor" used to
    # lose the occupation entirely: the same word that correctly raises the
    # PSIC wage-payer question above -- "outsourced" -- is not part of any
    # PSOC title, so the PSOC lookup was handed a string it could never
    # match and the user was told no occupation could be verified, for an
    # occupation the system resolves perfectly well one word shorter
    # (`janitor` -> 5153 BUILDING CARETAKERS).
    #
    # That is the PSOC/PSIC separation showing up as a defect: how a person
    # is ENGAGED is an employment arrangement and belongs to the industry
    # dimension; what they DO is the occupation. The arrangement wording is
    # therefore retried out of the occupation TITLE only.
    #
    # Written as a FALLBACK, not as unconditional stripping: the raw
    # wording is tried first and any string that resolves today resolves
    # identically, so only the no-verified-match path gains a second,
    # narrower attempt. `outsourced` is computed ABOVE from the raw
    # `occ_txt`, so the wage-payer precondition cannot be weakened by this.
    occ_sel <- if ("psoc" %in% systems && !is.null(occ_txt)) {
      first <- .assistant_enforce_current(
        .assistant_select_from_slot(
          assistant_slot_candidates("psoc", occ_txt, prefer_detailed = TRUE)
        ), "psoc", allow_archived
      )
      retry_txt <- .assistant_occupation_without_arrangement(occ_txt)
      if (.assistant_slot_unresolved(first) && !is.null(retry_txt)) {
        second <- .assistant_enforce_current(
          .assistant_select_from_slot(
            assistant_slot_candidates("psoc", retry_txt, prefer_detailed = TRUE)
          ), "psoc", allow_archived
        )
        if (!.assistant_slot_unresolved(second)) second else first
      } else {
        first
      }
    } else {
      NULL
    }

    # ---- industry half -------------------------------------------------
    ind_sel <- NULL
    ind_blocked_reason <- NA_character_
    if ("psic" %in% systems) {
      # Once the payer IS known the outsourcing precondition is satisfied,
      # so the slot contract's own outsourcing block must not keep
      # suppressing the activity -- that would ask the wage-payer question
      # forever. `activity_for_psic` therefore falls back to the supplied
      # wording, which by this point names whichever unit actually pays.
      activity_for_psic <- if (slots$context_known) {
        slots$psic_activity_query
      } else if (outsourced && payer_known && !isTRUE(slots$activity_too_vague)) {
        act_txt
      } else {
        NA_character_
      }

      if (outsourced && !payer_known) {
        ind_blocked_reason <- "wage_payer"
      } else if (is.null(activity_for_psic) || is.na(activity_for_psic)) {
        ind_blocked_reason <- "establishment_activity"
      } else {
        ind_sel <- .assistant_enforce_current(
          .assistant_select_from_slot(
            assistant_slot_candidates("psic", activity_for_psic,
                                      prefer_detailed = TRUE)
          ), "psic", allow_archived
        )
      }
    }

    # ---- clarification determination ------------------------------------
    missing_slot <- NA_character_
    question <- NA_character_
    options <- list()

    if (!is.null(occ_sel) && identical(occ_sel$status, "no_verified_match") &&
        is.null(occ_txt)) {
      missing_slot <- "occupation"
      question <- "What work does the person actually do - their main duties or job title?"
    } else if (!is.na(ind_blocked_reason)) {
      missing_slot <- ind_blocked_reason
      question <- if (identical(ind_blocked_reason, "wage_payer")) {
        ASSISTANT_GUIDANCE_OUTSOURCING_PROBE
      } else if (isTRUE(slots$activity_too_vague)) {
        assistant_activity_probe_question(slots$supplied_activity, occ_txt)
      } else {
        assistant_establishment_question(occ_txt)
      }
    } else if (!is.null(ind_sel) && identical(ind_sel$status, "clarification_required")) {
      missing_slot <- "establishment_activity_detail"
      question <- sprintf(
        "Which of these does the establishment mainly do? (%s)",
        paste(vapply(ind_sel$options, function(o) o$label, character(1)), collapse = "; ")
      )
      options <- ind_sel$options
    }

    # ---- overall status --------------------------------------------------
    occ_status <- .assistant_slot_status(if (is.null(occ_sel)) NULL else occ_sel$status)
    ind_status <- if (!is.na(ind_blocked_reason)) {
      "clarification_required"
    } else {
      .assistant_slot_status(if (is.null(ind_sel)) NULL else ind_sel$status)
    }

    status <- if (!is.na(missing_slot)) {
      "clarification_required"
    } else if (identical(occ_status, "no_verified_match") &&
               ind_status %in% c("no_verified_match", "not_requested")) {
      "no_verified_match"
    } else {
      "resolved"
    }

    allowed_psoc <- if (is.null(occ_sel)) character(0) else occ_sel$allowed
    allowed_psic <- if (is.null(ind_sel)) character(0) else ind_sel$allowed

    list(
      status = status,
      request_type = "contextual_coding",
      requested_systems = systems,
      occupation = if (is.null(occ_sel)) NULL else c(
        list(status = occ_sel$status), occ_sel[setdiff(names(occ_sel), c("status", "allowed", "options"))]
      ),
      industry = if (is.null(ind_sel)) {
        if (is.na(ind_blocked_reason)) NULL else list(status = "clarification_required",
                                                      blocked_on = ind_blocked_reason)
      } else {
        c(list(status = ind_sel$status), ind_sel[setdiff(names(ind_sel), c("status", "allowed", "options"))])
      },
      clarification = list(
        missing_slot = missing_slot,
        question = question,
        options = options
      ),
      allowed_codes = list(psoc = allowed_psoc, psic = allowed_psic),
      current_edition_enforced = !isTRUE(allow_archived),
      guidance = paste(
        "These classifications were selected by the application, not by you.",
        "State them exactly as given. If a clarification question is present,",
        "ask it and do not offer any code for that system yet."
      )
    )
  }
  .assistant_tool_try(impl(), "assistant_coding_service")
}

#' Every code the service authorised, as one flat vector.
#'
#' `context` is a third slot alongside psoc/psic, written only by
#' `assistant_attached_context_packet()`. It exists because a record the
#' user attached from Search may belong to any registered system -- a PSGC
#' province, a PSCED programme -- and filing such a code under `psoc` or
#' `psic` to get it authorised would be a lie in the packet. Packets from
#' the coding service carry no `context` slot, so this union is a no-op for
#' every pre-existing caller.
assistant_allowed_codes <- function(packet) {
  if (is.null(packet) || is.null(packet$allowed_codes)) return(character(0))
  codes <- c(packet$allowed_codes$psoc,
             packet$allowed_codes$psic,
             packet$allowed_codes$context)
  unique(as.character(codes[!is.na(codes)]))
}
