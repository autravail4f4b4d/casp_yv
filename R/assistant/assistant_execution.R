# RM-W1 -- deterministic server-side execution of authoritative coding.
#
# ============================================================================
# THE ROOT CAUSE THIS FILE EXISTS TO REMOVE
# ============================================================================
#
# pre-staging-v9 passed every local deterministic test and still failed live
# browser acceptance. The reason is not that `assistant_coding_service()` is
# nondeterministic -- it is a pure function, and 10x repeatability harnesses
# proved it. The reason is that NOTHING DETERMINISTIC EVER CHOSE ITS INPUTS.
#
# The live path was:
#
#   user text
#     -> shinychat::chat_mod_server()'s own observeEvent
#     -> client$stream_async()                      [the MODEL now drives]
#     -> gpt-4o-mini picks a tool
#     -> gpt-4o-mini picks `occupation` / `establishment_activity` / `wage_payer`
#     -> assistant_code_occupation_and_activity(...)  [deterministic, but on
#                                                      model-chosen arguments]
#
# So the whole slot-extraction step -- the step that decides WHAT is being
# coded -- was delegated to a nondeterministic model. Every live v9 symptom
# falls out of that one fact:
#
#   "mayor psoc psic" first turn vs repeat
#       one turn the model passed occupation="mayor" and NO establishment,
#       giving a (correct) clarification; another turn it passed
#       establishment_activity="local government", giving 84113. Both are
#       correct behaviours of the service. The instability is upstream.
#
#   incognito still asked for the establishment
#       a fresh conversation has no prior turn nudging the model's slot
#       choice, so it defaulted to the barest extraction.
#
#   outsourced janitor returned hospital 86111
#       the model passed establishment_activity="hospital", silently
#       dropping "through a manpower agency". The wage-payer precondition
#       inspects that string, so with the agency wording gone the rule had
#       nothing to fire on. The rule was never bypassed -- it was never
#       shown the evidence.
#
#   carpenter returned 08106 Construction sand and gravel quarrying
#       the model INVENTED establishment_activity from the occupation
#       (something like "construction"), which retrieves a quarrying
#       sub-class. The service never inferred an industry from an
#       occupation; the model fabricated the slot and handed it over.
#
#   batch: repeated "Checking..." and an empty answer
#       the server pre-resolved the batch, but the model ALSO ran its own
#       tool loop -- one tool call per item -- each rendering a tool-status
#       chunk, while the ContentText suppression hid its prose. Hence N
#       status lines and no visible answer.
#
#   packet/turn mismatch
#       `assistant_turn_set_latest_packet()` is written once per tool call,
#       so on a multi-call turn the response guard validated the final text
#       against whichever packet happened to be written last.
#
# ============================================================================
# THE FIX
# ============================================================================
#
# Move slot extraction and coding execution into R, ahead of the model:
#
#   user text
#     -> assistant_route_request()        deterministic route
#     -> assistant_extract_slots()        deterministic slots        [NEW]
#     -> assistant_coding_service()       deterministic decision
#     -> deterministic rendering
#     -> (optional) model explanation, guarded
#
# For coding routes the model is given NO TOOLS at all (see app.R). It
# cannot choose the route, cannot choose the slots, cannot call the coding
# service, and cannot emit a tool-status chunk. That single change removes
# the "Checking..." loop, the packet mismatch, and the first-turn
# instability together, because all three were symptoms of the model owning
# the workflow.
#
# The deterministic answer is produced BEFORE any provider call, so a
# provider outage degrades the explanation, never the classification.

# ---------------------------------------------------------------------------
# Deterministic slot extraction
# ---------------------------------------------------------------------------

# Prepositions that introduce an ESTABLISHMENT rather than more occupation
# wording. Ordered longest-first so "deployed at" wins over "at".
#
# Deliberately small. Every entry here is a phrase that, in the survey
# wording this application actually receives, separates "what the person
# does" from "where/for whom they do it". A vaguer connector would start
# splitting occupation titles in half ("machine operator FOR rubber
# products"), which is why "for" is absent.
.ASSISTANT_ESTABLISHMENT_PREPOSITIONS <- c(
  "deployed at", "deployed to", "deployed through", "deployed by",
  "assigned at", "assigned to",
  "working at", "working in", "working for", "works at", "works in",
  "employed at", "employed in", "employed by",
  "hired by", "hired through",
  "based at", "based in",
  " at ", " in a ", " in an ", " in the ", " in "
)

# System tokens and coding verbs the router already consumed. Stripped
# before slot extraction so "mayor psoc psic" yields the occupation
# "mayor" rather than "mayor psoc psic".
.ASSISTANT_SLOT_NOISE <- paste0(
  "\\b(psoc|psic|psgc|psced|pcoicop|pcpc|pscc|psccs|ptscs|pscrcs)\\b",
  "|\\b(code|codes|classification|classify|coding)\\b",
  "|\\bwhat(\\s+is|'s)?\\s+(the|my)\\b",
  "|\\b(i\\s+am|i'm|im)\\s+(a|an|the)?\\b",
  "|\\bplease\\b|\\bkindly\\b"
)

# Connector words that can be left STRANDED at the front once the noise
# above is removed. "what is the psoc code of a vulcanizer" strips down to
# "of a vulcanizer", because `code` is consumed by the noise alternation
# before any "code of" alternative could match it. Cleared in a second
# pass rather than by complicating the first one.
.ASSISTANT_SLOT_LEADING_CONNECTORS <- "^(of|for|about|on)\\s+(a|an|the)?\\s*"

# Government offices whose ESTABLISHMENT is, by definition, the government
# unit itself (spec 13).
#
# This is NOT occupation -> industry inference of the kind the project
# forbids. That rule protects PRIVATE establishments: a nurse's employer
# could be a hospital, a school clinic or a manufacturer, so the occupation
# cannot settle it. A municipal mayor is not employed BY some unrelated
# establishment -- holding the office IS the local government unit, and PSA
# codes it to public administration accordingly. The mapping below is
# therefore definitional, is restricted to elected/appointed public
# offices, and still resolves through ordinary retrieval and canonical
# verification -- it supplies ACTIVITY WORDING, never a code.
ASSISTANT_GOVERNMENT_OFFICE_CONTEXT <- list(
  "mayor"              = "public administration local government",
  "vice mayor"         = "public administration local government",
  "municipal mayor"    = "public administration local government",
  "city mayor"         = "public administration local government",
  "punong barangay"    = "public administration local government",
  "barangay captain"   = "public administration local government",
  "barangay chairman"  = "public administration local government",
  "governor"           = "public administration local government",
  "vice governor"      = "public administration local government",
  "provincial governor" = "public administration local government"
)

.assistant_slot_strip_noise <- function(x) {
  s <- tolower(as.character(x))
  s <- gsub(.ASSISTANT_SLOT_NOISE, " ", s, perl = TRUE)
  s <- gsub("[?.!,;]+", " ", s)
  s <- gsub("\\s+", " ", s)
  s <- trimws(s)
  s <- gsub(.ASSISTANT_SLOT_LEADING_CONNECTORS, "", s, perl = TRUE)
  trimws(s)
}

#' Split raw user wording into deterministic coding slots.
#'
#' This is the step that used to belong to gpt-4o-mini. It is intentionally
#' CONSERVATIVE: when the wording does not clearly name an establishment,
#' `establishment_activity` is NULL and the coding service asks -- which is
#' the correct, safe outcome. It never invents an activity from the
#' occupation (the carpenter -> 08106 defect), and it never drops qualifying
#' wording such as "through a manpower agency" (the janitor -> 86111
#' defect): the whole remainder of the sentence is preserved so the
#' outsourcing precondition can see it.
#'
#' @param text character(1) raw user message.
#' @param requested_systems character vector from the router, or NULL.
#'
#' @return list(occupation, establishment_activity, wage_payer,
#'   requested_systems, government_context). Any slot may be NULL.
assistant_extract_slots <- function(text, requested_systems = NULL) {
  raw <- .assistant_scalar_chr(text)
  out <- list(
    occupation = NULL,
    establishment_activity = NULL,
    wage_payer = NULL,
    requested_systems = if (is.null(requested_systems) ||
                            length(requested_systems) == 0L) {
      c("psoc", "psic")
    } else {
      requested_systems
    },
    government_context = FALSE
  )
  if (is.null(raw)) return(out)

  cleaned <- .assistant_slot_strip_noise(raw)
  if (!nzchar(cleaned)) return(out)

  # Find the FIRST establishment preposition, longest-match-first.
  occ <- cleaned
  act <- NULL
  for (prep in .ASSISTANT_ESTABLISHMENT_PREPOSITIONS) {
    pat <- paste0("\\b", trimws(prep), "\\b")
    m <- regexpr(pat, cleaned, perl = TRUE)
    if (m[[1L]] > 0L) {
      lhs <- trimws(substr(cleaned, 1L, m[[1L]] - 1L))
      rhs <- trimws(substr(cleaned, m[[1L]] + attr(m, "match.length"), nchar(cleaned)))
      # Only accept the split if BOTH sides carry content. "in" inside a
      # title ("growing of rice in upland") must not strand an empty side.
      if (nzchar(lhs) && nzchar(rhs)) {
        occ <- lhs
        # Preserve the preposition when it is part of the outsourcing
        # evidence -- "deployed at a hospital through a manpower agency"
        # must reach the wage-payer rule with its agency wording intact.
        act <- rhs
        break
      }
    }
  }

  occ <- trimws(gsub("^(a|an|the)\\s+", "", occ))
  if (!nzchar(occ)) occ <- NULL
  if (!is.null(act)) {
    act <- trimws(gsub("^(a|an|the)\\s+", "", act))
    if (!nzchar(act)) act <- NULL
  }

  out$occupation <- occ
  out$establishment_activity <- act

  # Definitional establishment context (spec 13/21), applied ONLY when the
  # user has not already described the establishment themselves.
  if (is.null(out$establishment_activity) && !is.null(occ)) {
    ctx <- .assistant_government_office_context(occ)
    if (!is.null(ctx)) {
      out$establishment_activity <- ctx
      out$government_context <- TRUE
    } else {
      out$establishment_activity <- .assistant_cultivation_context(occ)
    }
  }

  out
}

# Occupation titles of the form "<crop> farmer" / "<crop> grower", which
# name the CROP and therefore the cultivation activity itself.
.ASSISTANT_CULTIVATION_OCCUPATION <-
  "^(.+?)\\s+(farmer|farmers|grower|growers|planter|planters)$"

# The bare heads that carry no crop and must still be probed. "farmer"
# alone says nothing about what is grown, so it stays a clarification.
.ASSISTANT_CULTIVATION_BARE <- c(
  "farmer", "farmers", "grower", "growers", "planter", "planters",
  "subsistence", "tenant", "share", "seasonal", "migrant", "hired",
  "small", "smallhold", "smallholder", "commercial", "organic"
)

#' Cultivation activity implied by a crop-naming farming occupation.
#'
#' Same narrow, definitional logic as the government-office table above,
#' and NOT the general occupation -> industry inference the project
#' forbids. That rule exists because a nurse's employer could be a
#' hospital, a school or a factory, so the occupation cannot settle the
#' establishment. A "palay farmer" is different in kind: the occupation
#' names the CROP, and a farm growing palay grows palay whoever owns it,
#' so the establishment's principal activity is already stated -- which is
#' exactly why spec 21 requires `palay farmer` to reach 0112 rather than
#' asking what the farm does.
#'
#' Returns ACTIVITY WORDING only ("palay farming"), never a code. That
#' wording then goes through the ordinary activity expansions, hybrid
#' retrieval, the compatibility gate and canonical verification like any
#' user-typed phrase -- so an unlisted crop simply fails to verify and
#' falls back to a clarification instead of inventing a code.
.assistant_cultivation_context <- function(occupation) {
  o <- .assistant_scalar_chr(occupation)
  if (is.null(o)) return(NULL)
  q <- trimws(tolower(o))
  m <- regmatches(q, regexec(.ASSISTANT_CULTIVATION_OCCUPATION, q, perl = TRUE))[[1L]]
  if (length(m) < 2L) return(NULL)
  crop <- trimws(m[[2L]])
  if (!nzchar(crop)) return(NULL)
  # Strip qualifiers that are not the crop, then require something left.
  words <- strsplit(crop, "\\s+")[[1L]]
  words <- words[nzchar(words) & !(words %in% .ASSISTANT_CULTIVATION_BARE)]
  if (length(words) == 0L) return(NULL)
  paste(paste(words, collapse = " "), "farming")
}

#' Canonical government-office activity wording for an occupation phrase.
#'
#' Whole-word match on the longest office title present, so "vice mayor"
#' is not read as "mayor" with different semantics and an unrelated phrase
#' containing the word never matches accidentally.
.assistant_government_office_context <- function(occupation) {
  o <- .assistant_scalar_chr(occupation)
  if (is.null(o)) return(NULL)
  q <- .assistant_norm_text(tolower(o))
  if (!nzchar(q)) return(NULL)
  offices <- names(ASSISTANT_GOVERNMENT_OFFICE_CONTEXT)
  offices <- offices[order(-nchar(offices))]
  for (office in offices) {
    if (grepl(paste0("\\b", gsub("\\s+", "\\\\s+", office), "\\b"), q)) {
      return(ASSISTANT_GOVERNMENT_OFFICE_CONTEXT[[office]])
    }
  }
  NULL
}

# ---------------------------------------------------------------------------
# Server-facing turn handler
# ---------------------------------------------------------------------------

# The routes whose ANSWER is authoritative classification, and which must
# therefore be produced by R before the model is involved at all.
ASSISTANT_SERVER_HANDLED_ROUTES <- c(
  "contextual_coding",
  "batch_contextual_coding"
)

#' Handle one user turn deterministically, server-side.
#'
#' The single entry point app.R calls, and the single entry point the
#' repeatability harness exercises -- so what is tested is what runs.
#'
#' @param text character(1) raw user message.
#' @param turn_state an `assistant_new_turn_state()` environment.
#'
#' @return list(
#'   route, handled, status, packet, packets, render,
#'   allowed_codes, explanation_context
#' )
#'   `handled = FALSE` means this turn is NOT an authoritative coding turn
#'   and the ordinary conversational model flow should run unchanged.
assistant_handle_turn <- function(text, turn_state) {
  raw <- .assistant_scalar_chr(text)
  pending <- assistant_turn_pending(turn_state)
  routed <- assistant_route_request(raw, pending = pending)

  # Route and system authorisation are recorded FIRST and unconditionally,
  # so the tool interlock and render suppression are primed even if
  # anything below fails.
  assistant_turn_set_route(turn_state, routed$route)
  assistant_turn_set_requested_systems(turn_state, routed$requested_systems)

  out <- list(
    route = routed$route,
    handled = FALSE,
    status = NA_character_,
    packet = NULL,
    packets = list(),
    render = NA_character_,
    allowed_codes = character(0),
    explanation_context = NA_character_
  )

  if (!(routed$route %in% ASSISTANT_SERVER_HANDLED_ROUTES)) {
    return(out)
  }

  handled <- tryCatch({
    if (identical(routed$route, "batch_contextual_coding")) {
      .assistant_handle_batch(routed, turn_state)
    } else {
      .assistant_handle_single(routed, turn_state, pending)
    }
  }, error = function(e) {
    # FAIL CLOSED. No packet means the response guard has no allowed_codes,
    # so no code can be presented for this turn by any path.
    message(sprintf("[rm-assistant] deterministic turn handling failed: %s",
                    conditionMessage(e)))
    assistant_turn_set_latest_packet(turn_state, NULL)
    NULL
  })

  if (is.null(handled)) return(out)
  handled
}

.assistant_handle_single <- function(routed, turn_state, pending) {
  # A clarification reply reuses the SAME stored request rather than being
  # re-parsed as a fresh one -- this is what keeps "residential
  # construction" attached to the carpenter that prompted the question.
  args <- if (isTRUE(routed$is_clarification_reply) && !is.null(pending)) {
    assistant_turn_apply_reply(turn_state, routed$text)
  } else {
    slots <- assistant_extract_slots(routed$text, routed$requested_systems)
    list(
      occupation = slots$occupation,
      establishment_activity = slots$establishment_activity,
      requested_systems = slots$requested_systems,
      wage_payer = slots$wage_payer
    )
  }
  if (is.null(args)) return(NULL)

  packet <- do.call(assistant_coding_service, args)
  assistant_turn_set_latest_packet(turn_state, packet)

  # Pending state is set from the packet itself, so the stored question and
  # the rendered question can never disagree.
  assistant_turn_set_pending(
    turn_state, packet,
    occupation = args$occupation,
    establishment_activity = args$establishment_activity,
    requested_systems = args$requested_systems,
    wage_payer = args$wage_payer
  )

  list(
    route = routed$route,
    handled = TRUE,
    status = packet$status,
    packet = packet,
    packets = list(packet),
    render = assistant_render_coding_result(packet),
    allowed_codes = assistant_allowed_codes(packet),
    explanation_context = assistant_render_coding_result(packet)
  )
}

.assistant_handle_batch <- function(routed, turn_state) {
  items <- routed$items
  if (is.null(items) || length(items) == 0L) return(NULL)

  assistant_turn_begin_batch(turn_state, length(items))
  packets <- list()
  for (it in items) {
    # Each item is parsed and resolved INDEPENDENTLY. Nothing from item i
    # is visible to item j -- that isolation is the whole point, and it is
    # what the live build lost when six requests collapsed into one.
    slots <- assistant_extract_slots(it$text, it$requested_systems)
    args <- list(
      occupation = slots$occupation,
      establishment_activity = slots$establishment_activity,
      requested_systems = slots$requested_systems,
      wage_payer = slots$wage_payer
    )
    pkt <- do.call(assistant_coding_service, args)
    packets[[length(packets) + 1L]] <- pkt
    assistant_turn_record_batch_item(
      turn_state, it, pkt,
      occupation = args$occupation,
      establishment_activity = args$establishment_activity,
      wage_payer = args$wage_payer
    )
  }

  res <- assistant_turn_finalize_batch(turn_state)
  merged <- assistant_batch_merge_packets(packets)
  assistant_turn_set_latest_packet(turn_state, merged)

  list(
    route = routed$route,
    handled = TRUE,
    status = if (res$n_unresolved > 0L) "clarification_required" else "resolved",
    packet = merged,
    packets = packets,
    render = assistant_render_batch_results(res$resolved, res$unresolved),
    allowed_codes = assistant_allowed_codes(merged),
    explanation_context = NA_character_
  )
}
