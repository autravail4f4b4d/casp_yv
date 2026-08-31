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

# ESTABLISHMENT-ACTIVITY wording, kept in a SEPARATE table on purpose.
#
# The table above maps occupation wording to occupation wording. This one
# maps establishment/activity wording to establishment/activity wording.
# Keeping them apart is what makes "no expansion maps an occupation to an
# industry activity" a structural property that a test can check, rather
# than a convention a future edit could quietly break: an entry can only
# violate the rule by being put in the wrong table, and each table is
# tested for the kind of key it is allowed to hold.
#
# Both tables are consulted by `assistant_expand_query()`, which is called
# per SLOT -- so an activity expansion only ever widens an activity search.
# No entry here maps to a code; every target is official activity wording
# that still goes through ordinary retrieval, the context gate, the
# compatibility gate and canonical verification.
ASSISTANT_ACTIVITY_EXPANSIONS <- list(
  # --- Agriculture activity wording (spec 23) ---------------------------
  #
  # PSA titles are gerunds of the ACT ("Growing of corn", "Growing of
  # rice"); users name the crop and the practice ("corn farming", "palay
  # farming"). Measured: "corn farming", "rice farming" and "corn farming
  # in their own farm" all retrieved NOTHING for PSIC, because no lexical
  # tier bridges "farming" to "growing".
  #
  # A bare `"farming" = "growing"` was tried and REMOVED: "growing" alone
  # matches every "Growing of ..." row in PSIC, and the noise displaced
  # the 0112 PARENT out of the bounded candidate list -- which silently
  # turned "palay farming" from "rice-growing aggregate + irrigation
  # question" into a confident 01121 irrigated lowland. Crop-specific
  # phrases are distinctive enough to bridge on their own; an unlisted
  # crop is a recall gap for the semantic tier to close, which is strictly
  # safer than a wrong confident subclass.
  "corn farming"           = c("growing of corn"),
  "maize"                  = c("corn"),
  "maize farming"          = c("growing of corn"),
  "rice farming"           = c("growing of rice"),
  "palay farming"          = c("growing of rice"),
  "paddy rice"             = c("growing of rice"),
  "paddy"                  = c("rice"),

  # --- Government context wording (spec 21/22) ---------------------------
  #
  # Canonical PSIC titles are "Public administration, local government"
  # (84113) and "Public administration, regional government" (84112).
  # Users say "city government", "LGU", "national government agency".
  # Measured: none of those retrieved any PSIC row at all. Normalizing the
  # wording lets ordinary retrieval + canonical verification do the rest,
  # so the user is never asked to describe a city hall as if it were a
  # private business.
  #
  # The national entries expand to the bare distinctive phrase "public
  # administration" rather than to the full canonical title "General
  # public administration activities": the words "general" and
  # "activities" are so common across PSIC that including them retrieved
  # 86111 PUBLIC GENERAL hospital ACTIVITIES for "national government
  # agency" -- measured, and exactly the kind of confident wrong answer
  # this phase exists to remove.
  "lgu"                    = c("public administration local government"),
  "local government"       = c("public administration local government"),
  "local government unit"  = c("public administration local government"),
  "city government"        = c("public administration local government"),
  "municipal government"   = c("public administration local government"),
  "provincial government"  = c("public administration local government"),
  "barangay government"    = c("public administration local government"),
  "city hall"              = c("public administration local government"),
  "municipal hall"         = c("public administration local government"),
  "regional government"    = c("public administration regional government"),
  "national government"    = c("public administration"),
  "national government agency" = c("public administration"),
  "government agency"      = c("public administration"),
  "government office"      = c("public administration"),

  # A named national agency normalizes to the TIER first and the activity
  # second (spec 13: "PSA -> national government agency"). Both halves
  # matter and neither is a code:
  #   * "public administration" is what makes the activity retrievable;
  #   * "national government agency" carries the word `national`, which is
  #     the controlled government-tier value (assistant_compat.R). Without
  #     it a bare "PSA" states no tier, and the regional/local subclasses
  #     survive into the candidate set and produce a forced choice the
  #     respondent has already answered -- measured live.
  # Deliberately wording-level and agency-agnostic: any national agency
  # added here inherits the same behaviour, and none of them names a code.
  "psa"                    = c("national government agency", "public administration"),
  "philippine statistics authority" =
    c("national government agency", "public administration"),
  "national agency"        = c("national government agency", "public administration"),
  "national government office" = c("national government agency", "public administration"),

  # --- Trade wording that names a practice, not the industry -------------
  #
  # "carpentry" on its own retrieves 1622 Manufacture of builders'
  # carpentry and joinery -- a MANUFACTURING class. When the user says
  # residential carpentry they mean building work, so the residential
  # qualifier is what disambiguates. Normalizes wording only.
  "residential carpentry"  = c("construction of residential buildings"),
  "house carpentry"        = c("construction of residential buildings"),
  "building carpentry"     = c("construction of residential buildings")
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
#' Matching is on the WHOLE normalized phrase first, then on any MULTI-WORD
#' key contained in it as whole words, then on individual normalized
#' tokens. So "palay farmer", a bare "palay", and "private high school"
#' (which contains the two-word key "high school") all expand.
#' The original phrase is always first in the result and is never dropped.
#'
#' The multi-word containment pass closes a measured recall hole: the table
#' has carried `"high school" = "secondary education"` since the PSOC
#' milestone, but it only ever fired when the user typed exactly "high
#' school". A real query says "teacher in a private high school", whose
#' TOKENS are {teacher, in, a, private, high, school} -- none of which is
#' the two-word key -- so the expansion never applied and the PSIC slot
#' "private high school" could not reach 85312 Private general secondary
#' education at all. It matched 85102 Private PRE-PRIMARY education
#' instead, on the shared token "private".
#'
#' @param phrase character(1) user wording.
#' @return character vector of search texts, original first, de-duplicated.
assistant_expand_query <- function(phrase) {
  p <- .assistant_scalar_chr(phrase)
  if (is.null(p)) return(character(0))

  norm <- tolower(trimws(gsub("\\s+", " ", p)))
  out <- p
  table <- .assistant_expansion_table()

  whole <- table[[norm]]
  if (!is.null(whole)) out <- c(out, whole)

  toks <- strsplit(norm, "[^a-z]+")[[1L]]
  toks <- toks[nzchar(toks)]

  # Multi-word keys, matched as whole words anywhere in the phrase. Skipped
  # when the phrase IS the key (already handled above) so nothing is added
  # twice. Longest keys first, so "senior high school" wins over
  # "high school" when both are present.
  for (key in .assistant_expansion_multiword_keys()) {
    if (identical(key, norm)) next
    if (grepl(paste0("\\b", gsub("\\s+", "\\\\s+", key), "\\b"), norm)) {
      out <- c(out, table[[key]])
    }
  }

  for (tk in toks) {
    hit <- table[[tk]]
    if (!is.null(hit)) out <- c(out, hit)
  }

  unique(out[nzchar(out)])
}

# The two tables are consulted as one lookup. They stay SEPARATE at
# definition so each can be tested for the kind of key it may hold (see
# ASSISTANT_ACTIVITY_EXPANSIONS); merging happens only here, at use.
.assistant_expansion_cache <- new.env(parent = emptyenv())

.assistant_expansion_table <- function() {
  if (!is.null(.assistant_expansion_cache$table)) {
    return(.assistant_expansion_cache$table)
  }
  merged <- c(ASSISTANT_QUERY_EXPANSIONS, ASSISTANT_ACTIVITY_EXPANSIONS)
  .assistant_expansion_cache$table <- merged
  merged
}

# Multi-word expansion keys, longest first. Computed once per process --
# both tables are file-scope constants, so this can never go stale.
.assistant_expansion_multiword_keys <- function() {
  if (!is.null(.assistant_expansion_cache$multi)) {
    return(.assistant_expansion_cache$multi)
  }
  keys <- names(.assistant_expansion_table())
  keys <- keys[grepl(" ", keys, fixed = TRUE)]
  keys <- keys[order(-nchar(keys))]
  .assistant_expansion_cache$multi <- keys
  keys
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
