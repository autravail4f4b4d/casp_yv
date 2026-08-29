# W1-B -- contextual slot decomposition and candidate-generation vocabulary.
#
# THE STRUCTURAL DEFECT THIS EXISTS TO MAKE IMPOSSIBLE
# ----------------------------------------------------
# Traced directly against the shipped build: for every paired staging
# query the model passed ONE undifferentiated sentence to BOTH systems --
# `assistant_search_classification("psoc", "nurse in a private hospital
# psoc psic")` AND `("psic", <same string>)`. Measured result: total = 0 on
# BOTH systems for all nine transcript queries, because the evidence gate
# (correctly) rejects a sentence whose meaningful tokens are mostly
# unsupported. RM then had nothing verified to work from.
#
# The same content, decomposed, retrieves cleanly from the SAME engine:
#   occupation "corn farmer"          -> PSOC 6112 CORN FARMERS
#   activity   "growing of corn"      -> PSIC 0113 / 01130 Growing of corn
#   activity   "private hospital"     -> PSIC 8612 Private hospital activities
#   occupation "barangay health worker" -> PSOC 3253 COMMUNITY HEALTH WORKERS
#
# So retrieval was never the problem; passing an undecomposed sentence
# was. The fix is therefore NOT a retrieval change: it is a tool contract
# that cannot represent the broken call. `assistant_code_occupation_and_activity()`
# (R/assistant/assistant_contextual_coding.R) takes `occupation` and
# `establishment_activity` as SEPARATE arguments -- there is no single
# free-text field for the model to dump a whole sentence into and have it
# reach both systems.
#
# CONTROLLED CANDIDATE-GENERATION VOCABULARY
# ------------------------------------------
# A second, smaller cause: some correct occupations are unreachable by
# lexical retrieval from the user's own wording. Measured:
#   sim("nurse", "nursing")  = 0.000   -> PSOC 2221 NURSING PROFESSIONALS missed
#   sim("nurse", "nursery")  = 0.714   -> but "nurse" IS a literal substring of
#                                        "NURSERY", so the deterministic
#                                        substring tier returns 6118
#                                        GARDENERS, HORTICULTURAL AND NURSERY
#                                        GROWERS as the ONLY candidate.
# i.e. the wrong record is reachable and the right one is not.
#
# The table below is expansion for CANDIDATE GENERATION ONLY. Every entry
# maps user wording -> additional OFFICIAL-VOCABULARY SEARCH TEXT. No entry
# maps to a classification code, and no entry maps an occupation to an
# industry -- both are explicitly forbidden by the specification, and both
# would move authority out of the canonical repository. Every expansion
# still goes through the ordinary hybrid retrieval engine, the context
# consistency gate, and canonical verification before anything is
# presented. Removing this table would lose recall; it could never
# manufacture a code.
ASSISTANT_QUERY_EXPANSIONS <- list(
  # English morphology the lexical tiers cannot bridge.
  "nurse"                  = c("nursing"),
  "nurses"                 = c("nursing"),
  "midwife"                = c("midwifery"),
  "teacher"                = c("teaching"),
  "farmer"                 = c("farming", "growing"),
  "fisherman"              = c("fishery", "fishing"),
  "fisherfolk"             = c("fishery", "fishing"),
  "driver"                 = c("driving"),
  "carpenter"              = c("carpentry", "joiner"),
  "mayor"                  = c("senior government official", "legislator"),
  "governor"               = c("senior government official", "legislator"),
  "barangay captain"       = c("senior government official", "legislator"),
  "call center agent"      = c("contact center"),
  "call centre agent"      = c("contact center"),
  "call center"            = c("contact center"),
  "bpo agent"              = c("contact center"),
  "statistician"           = c("statistics"),
  "vendor"                 = c("selling", "salesperson", "vendors"),
  "helper"                 = c("assistant", "helpers"),

  # Acronym only. Deliberately expands to the "worker" wording and NOT to
  # "aide": PSOC treats these as two different occupations -- 3253
  # COMMUNITY HEALTH WORKERS versus 5321 HEALTH CARE ASSISTANTS, whose
  # canonical example list contains "Barangay health aide". Collapsing
  # worker/aide here would erase a distinction the classification makes.
  "bhw"                    = c("barangay health worker", "community health worker"),

  # School-stage wording. PSA titles say "secondary"/"primary"; users say
  # "high school"/"elementary". Without this a high-school teacher query
  # lands on PRIMARY SCHOOL TEACHERS.
  "high school"            = c("secondary education"),
  "highschool"             = c("secondary education"),
  "senior high school"     = c("secondary education"),
  "high school teacher"    = c("secondary education teacher"),
  "elementary"             = c("primary school"),
  "grade school"           = c("primary school"),
  "elementary teacher"     = c("primary school teacher"),
  "elementarya"            = c("primary school"),

  # Filipino / Tagalog.
  "palay"                  = c("rice"),
  "palay farmer"           = c("rice farmer"),
  "magsasaka"              = c("farmer"),
  "mangingisda"            = c("fishery worker", "fisherman"),
  "guro"                   = c("teacher"),
  "nars"                   = c("nursing"),
  "panadero"               = c("baker"),
  "karpintero"             = c("carpenter", "carpentry"),
  "tsuper"                 = c("driver"),
  "drayber"                = c("driver"),
  "pulis"                  = c("police"),
  "abogado"                = c("lawyer"),
  "karinderya"             = c("eatery", "food service"),
  "carinderia"             = c("eatery", "food service"),
  "tindahan"               = c("retail sale", "store"),
  "panaderya"              = c("bakery"),

  # Cebuano / Bisaya.
  "mananagat"              = c("fishery worker", "fisherman"),
  "magtutudlo"             = c("teacher"),
  "panday"                 = c("carpenter", "carpentry"),
  "tigbaligya"             = c("salesperson", "selling"),
  "guwardya"               = c("security guard")
)

# Words that describe an EMPLOYER/WORKPLACE rather than the work performed.
# Used only to notice that an occupation phrase carries embedded
# establishment context (so it can be reported to the caller), never to
# choose a code.
ASSISTANT_ESTABLISHMENT_HINTS <- c(
  "hospital", "clinic", "school", "university", "college", "office",
  "factory", "plant", "store", "shop", "restaurant", "eatery", "hotel",
  "farm", "government", "barangay", "municipal", "city hall", "agency",
  "company", "firm", "bank", "call center", "contact center", "bpo"
)

#' Expand one slot phrase into additional official-vocabulary search texts.
#'
#' Matching is on the WHOLE normalized phrase first, then on individual
#' normalized tokens, so both "palay farmer" and a bare "palay" expand.
#' The original phrase is always first in the result and is never dropped.
#'
#' @param phrase character(1) user wording.
#' @return character vector of search texts, original first, de-duplicated.
assistant_expand_query <- function(phrase) {
  p <- .assistant_scalar_chr(phrase)
  if (is.null(p)) return(character(0))

  norm <- tolower(trimws(gsub("\\s+", " ", p)))
  out <- p

  whole <- ASSISTANT_QUERY_EXPANSIONS[[norm]]
  if (!is.null(whole)) out <- c(out, whole)

  toks <- strsplit(norm, "[^a-z]+")[[1L]]
  toks <- toks[nzchar(toks)]
  for (tk in toks) {
    hit <- ASSISTANT_QUERY_EXPANSIONS[[tk]]
    if (!is.null(hit)) out <- c(out, hit)
  }

  unique(out[nzchar(out)])
}

#' Does this phrase already name an establishment/workplace context?
#'
#' @return logical(1).
assistant_phrase_has_establishment_hint <- function(phrase) {
  p <- .assistant_scalar_chr(phrase)
  if (is.null(p)) return(FALSE)
  norm <- tolower(p)
  any(vapply(ASSISTANT_ESTABLISHMENT_HINTS,
             function(h) grepl(h, norm, fixed = TRUE), logical(1)))
}

#' Structured slot contract for a paired coding request.
#'
#' The model supplies the slots it extracted; this function decides,
#' deterministically, whether there is enough establishment context to
#' attempt a PSIC at all. That decision is NOT left to model prose --
#' spec 8: "safety-critical downstream logic must not depend solely on
#' free-form model prose".
#'
#' @param occupation character(1) or NULL.
#' @param establishment_activity character(1) or NULL.
#'
#' @return list(occupation_query, psic_activity_query, context_known,
#'   needs_psic_clarification, clarification_reason).
assistant_slot_contract <- function(occupation = NULL, establishment_activity = NULL) {
  occ <- .assistant_scalar_chr(occupation)
  act <- .assistant_scalar_chr(establishment_activity)

  # PSA survey guidance, column 15: a description consisting only of
  # refused wording ("store", "school", "government", "company", ...) is
  # NOT establishment context, however confidently it is supplied. Treat
  # it exactly as if nothing had been said, so the resolver probes rather
  # than coding a placeholder.
  vague <- !is.null(act) && assistant_activity_is_vague(act)

  # Column 16, outsourced personnel: "Persons hired in different industries
  # through recruitment agencies should be coded on the corresponding
  # industries where they worked IF they receive their wage/salary in this
  # establishment. Otherwise ... they should be coded in this agency."
  # Until we know who pays, the industry is genuinely undetermined -- two
  # different valid codes are in play -- so this blocks rather than merely
  # annotating.
  outsourced <- !is.null(act) && assistant_activity_mentions_outsourcing(act)

  context_known <- !is.null(act) && !vague && !outsourced

  reason <- if (context_known) {
    NA_character_
  } else if (outsourced) {
    paste(
      "The description mentions an agency or outsourcing arrangement.",
      "PSA survey guidance codes the industry to whoever actually pays the",
      "worker's wage - the establishment where the work is done, or the",
      "manpower/outsourcing agency - so the two possibilities give",
      "different codes and the payer must be established first."
    )
  } else if (vague) {
    sprintf(
      paste(
        "'%s' is one of the general descriptions PSA survey coding guidance",
        "refuses for industry coding: it does not say what the establishment",
        "actually produces or provides."
      ),
      act
    )
  } else if (is.null(occ)) {
    "No occupation and no establishment activity were supplied."
  } else {
    paste(
      "The establishment's principal activity was not supplied.",
      "PSIC classifies what the establishment does, not the worker's",
      "occupation, so it cannot be determined from the occupation alone."
    )
  }

  list(
    occupation_query = if (is.null(occ)) NA_character_ else occ,
    psic_activity_query = if (context_known) act else NA_character_,
    context_known = context_known,
    activity_too_vague = vague,
    activity_outsourced = outsourced,
    supplied_activity = if (is.null(act)) NA_character_ else act,
    needs_psic_clarification = !context_known,
    clarification_reason = reason,
    # Supplementary, non-blocking. A government description CAN be coded
    # (e.g. "city government" -> public administration, local government),
    # but column 15 still asks which office and which tier of local
    # government, so the probe is offered alongside the answer rather than
    # instead of it.
    context_probe = if (!is.null(act) && assistant_activity_mentions_government(act)) {
      ASSISTANT_GUIDANCE_GOVERNMENT_PROBE
    } else {
      NA_character_
    }
  )
}

# Real-world clarification prompts (spec 15). Deliberately about facts the
# user knows, never "which code do you want?" -- the user is not required
# to understand PSIC to answer any of these.
ASSISTANT_ESTABLISHMENT_QUESTIONS <- c(
  "What is the main activity of the establishment or business where the person works?",
  "What product does it make, or what service does it provide?",
  "Is it public (government) or privately owned?",
  "What type of institution or business is it?"
)

#' The single best real-world clarification question for a missing or
#' ambiguous establishment context.
#'
#' @param occupation character(1) or NULL, used only to make the question
#'   concrete ("...where the carpenter works?").
#' @return character(1).
assistant_establishment_question <- function(occupation = NULL) {
  occ <- .assistant_scalar_chr(occupation)
  if (is.null(occ)) return(ASSISTANT_ESTABLISHMENT_QUESTIONS[[1L]])
  sprintf(
    "What is the main activity of the establishment or business where the %s works? For example, what does it mainly produce or what service does it provide, and is it public or private?",
    tolower(occ)
  )
}
