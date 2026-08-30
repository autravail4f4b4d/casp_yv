# PSA survey coding guidance -- a VERSIONED evidence layer.
#
# Source: PSA household-survey enumerator's manual, Chapter 9.3 Section B
# (Economic Characteristics), columns 14 (PSOC) and 15/16 (PSIC).
#
# WHY THIS IS AN EVIDENCE LAYER AND NOT A CODE TABLE
# --------------------------------------------------
# The manual mixes classification vintages, and the two halves behave
# COMPLETELY differently against the current repository. Both were measured
# directly, not assumed:
#
#   PSOC half -- every one of the 21 occupation examples in the manual
#   resolves to a live PSOC 2022 unit group whose canonical label matches
#   the manual's own parenthetical label (2222 MIDWIFERY PROFESSIONALS,
#   3253 COMMUNITY HEALTH WORKERS, 8323 TNVS MOTORCYCLE DRIVERS, 2124 DATA
#   SCIENTIST, ...). The manual's `*` marks "2022 Updates to the 2012
#   PSOC", which is the edition the repository already carries. These are
#   therefore safe as CURRENT occupational evidence -- after verification.
#
#   PSIC half -- the manual codes industry with the "2019 Updates to the
#   2009 PSIC", and those code NUMBERS have been reused for different
#   activities in PSIC 2026. Measured collisions:
#
#     4781   2019: Retail sale via stalls and markets of food/beverages
#            2026: Retail sale of MOTOR VEHICLES
#     56107  2019: Carinderia or eatery
#            2026: Roasting and grilling of meat, poultry or fish
#     86225  2019: Dialysis center activities
#            2026: Private obstetrics and gynecology clinic activities
#     11053  2019: Water purifying and refilling station
#            2026: Manufacture of other non-carbonated flavored soft drinks
#
#   and several manual codes (4799, 4669, 8010, 4789, 4791, 49325, 86124,
#   82297, 45204) do not exist in 2026 at all.
#
# So a manual PSIC code copied forward is not merely stale, it can be
# CONFIDENTLY WRONG about a completely unrelated industry. Nothing in this
# file may ever present a manual PSIC code as an answer. The manual's PSIC
# rows are kept only as ACTIVITY TEXT -- the semantic intent -- which is
# then resolved against the current edition through ordinary retrieval and
# canonical verification, exactly like any user-supplied wording.

ASSISTANT_GUIDANCE_SOURCE <-
  "PSA household-survey enumerator's manual, Chapter 9.3 Section B (columns 14-16)"

ASSISTANT_GUIDANCE_PSOC_VINTAGE <- "2022 Updates to the 2012 PSOC"
ASSISTANT_GUIDANCE_PSIC_VINTAGE <- "2019 Updates to the 2009 PSIC (revised Feb 2011)"

# --- Occupation examples (column 14) --------------------------------------
#
# term -> PSOC code AS PRINTED IN THE MANUAL. Every code here was checked
# against PSOC 2022 and is re-verified at runtime before use, so a future
# repository change degrades this to "no evidence" rather than to a wrong
# answer. Terms are the manual's own wording, including Filipino phrasing.
ASSISTANT_GUIDANCE_PSOC_EXAMPLES <- list(
  list(term = "midwife who passed the board exam",     code = "2222"),
  list(term = "professional midwife",                   code = "2222"),
  list(term = "midwife non-board passer",               code = "3222"),
  list(term = "scavenging of plastics",                 code = "9612"),
  list(term = "scavenger of plastics and bottles",      code = "9612"),
  list(term = "refuse sorter",                          code = "9612"),
  list(term = "scavenging of leftover palay",           code = "6310"),
  list(term = "subsistence crop farmer",                code = "6310"),
  list(term = "tire maker",                             code = "8141"),
  list(term = "vulcanizer",                             code = "8141"),
  list(term = "e-load retailer",                        code = "5211"),
  list(term = "eload retailer",                         code = "5211"),
  list(term = "nagtitinda ng isda sa daan na may pwesto", code = "5211"),
  list(term = "online seller",                          code = "5247"),
  list(term = "online selling salesperson",             code = "5247"),
  list(term = "barangay health worker",                 code = "3253"),
  list(term = "bhw",                                    code = "3253"),
  list(term = "community health worker",                code = "3253"),
  list(term = "crypto currency trader",                 code = "3311"),
  list(term = "bitcoin trader",                         code = "3311"),
  list(term = "crypto currency manager",                code = "1211"),
  list(term = "angkas driver",                          code = "8323"),
  list(term = "joyride driver",                         code = "8323"),
  list(term = "toktok driver",                          code = "8323"),
  list(term = "grab express driver",                    code = "8323"),
  list(term = "tnvs motorcycle driver",                 code = "8323"),
  list(term = "grab driver using car",                  code = "8324"),
  list(term = "tnvs car driver",                        code = "8324"),
  list(term = "grab taxi driver",                       code = "8325"),
  list(term = "tnvs taxi driver",                       code = "8325"),
  list(term = "lalamove driver",                        code = "8326"),
  list(term = "transportify driver",                    code = "8326"),
  list(term = "tnvs van driver",                        code = "8326"),
  list(term = "grab bike driver",                       code = "9335"),
  list(term = "food panda driver",                      code = "9335"),
  list(term = "tnvs bicycle driver",                    code = "9335"),
  list(term = "mathematician",                          code = "2121"),
  list(term = "operations research analyst",            code = "2121"),
  list(term = "actuarial analyst",                      code = "2123"),
  list(term = "actuarial researcher",                   code = "2123"),
  list(term = "data miner",                             code = "2124"),
  list(term = "machine learning engineer",              code = "2124"),
  list(term = "data scientist",                         code = "2124"),
  list(term = "e-sport player",                         code = "3424"),
  list(term = "esports player",                         code = "3424"),
  list(term = "esports coach",                          code = "3424"),
  list(term = "electric vehicle mechanic",              code = "7414"),
  list(term = "evse repair and maintenance",            code = "7414"),
  list(term = "street vendor",                          code = "9520"),
  list(term = "naglalako",                              code = "9520")
)

# --- Industry activity hints (columns 15/16) -------------------------------
#
# NO CURRENT CODE IS RECORDED HERE ON PURPOSE. Each row keeps the manual's
# ACTIVITY WORDING plus the historical code purely for audit, so the
# activity can be re-resolved against the current edition.
ASSISTANT_GUIDANCE_PSIC_ACTIVITY_HINTS <- list(
  list(term = "e-load retailing",         activity = "retail sale of prepaid cards",         historical_code = "4789"),
  list(term = "online selling",           activity = "retail sale via mail order or internet", historical_code = "4791"),
  list(term = "security agency",          activity = "private security activities",          historical_code = "8010"),
  list(term = "barangay health center",   activity = "regulation of the activities of providing health care", historical_code = "8412"),
  list(term = "carinderia",               activity = "carinderia or eatery",                 historical_code = "56107"),
  list(term = "eatery",                   activity = "carinderia or eatery",                 historical_code = "56107"),
  list(term = "water refilling station",  activity = "water purifying and refilling station", historical_code = "11053"),
  list(term = "dialysis center",          activity = "dialysis center activities",           historical_code = "86225"),
  list(term = "car wash",                 activity = "car washing and auto-detailing services", historical_code = "45204"),
  list(term = "kpo",                      activity = "knowledge process outsourcing activities", historical_code = "82297"),
  list(term = "ride-sharing service",     activity = "operations of vehicles for transportation network service", historical_code = "49325")
)

# --- Methodology: descriptions the manual refuses to accept ----------------
#
# Verbatim from column 15: "DO NOT ACCEPT general answers like 'farm',
# 'store', 'retail store', 'wholesale store', 'mine', 'factory', 'shop',
# 'school', 'government', 'transportation', or 'company'. These are too
# vague ... DO NOT ACCEPT the name of the company alone."
ASSISTANT_GUIDANCE_VAGUE_ACTIVITIES <- c(
  "farm", "store", "retail store", "wholesale store", "mine", "factory",
  "shop", "school", "government", "transportation", "company",
  # Vague terms the project's own PSIC rules already listed, kept together
  # so there is one refusal list rather than two.
  "trading", "contractor", "general services", "financial services",
  "online business", "business", "office", "institution", "agency"
)

# The manual's own probing questions, verbatim in substance.
ASSISTANT_GUIDANCE_PROBES <- c(
  "What kind of retail store is this?",
  "Does the factory manufacture leather shoes, rubber shoes or something else?",
  "Does the company sell or repair the goods it handles?",
  "Was the work done at a shop or at the person's own home?"
)

# Column 15, government branch: "For work in a government office or
# institution, the name of the office, institution, school, or hospital may
# be used as the description. If the respondent works for the executive
# branch of a local government, specify whether it is a provincial, city,
# or municipal government."
ASSISTANT_GUIDANCE_GOVERNMENT_PROBE <- paste(
  "Which government office, institution, school or hospital is it?",
  "If it is the executive branch of a local government, is it a provincial,",
  "city, or municipal government?"
)

# Column 16, outsourced personnel: coded to the industry where they worked
# only if they are paid there; otherwise to the manpower/outsourcing agency.
# "Futher probe kung sino ang nagpapasweldo sa kanila."
ASSISTANT_GUIDANCE_OUTSOURCING_PROBE <- paste(
  "Who actually pays this person's wage or salary - the establishment where",
  "the work is done, or a manpower or outsourcing agency? The industry is",
  "coded to whichever one pays them."
)

ASSISTANT_GUIDANCE_OUTSOURCING_HINTS <- c(
  "agency", "manpower", "outsourc", "contractual", "job order",
  "deployed", "assigned", "recruitment", "third party", "3rd party"
)

.assistant_guidance_norm <- function(x) .assistant_norm_text(x)

#' Does a normalized guidance TERM match a normalized QUERY?
#'
#' A plain contiguous-substring check missed "food panda bicycle driver"
#' against the manual's own "food panda driver" (code 9335): inserting the
#' vehicle word between "panda" and "driver" broke the match, and the query
#' fell through to an unrelated current-label hit (5165 DRIVING
#' INSTRUCTORS) instead -- confirmed live. The fix tolerates EXTRA words
#' between the term's own words while still requiring every one of the
#' term's words to appear, in the term's own order, as whole words -- it
#' does not turn this into a bag-of-words or fuzzy matcher, and a term
#' whose words are simply absent still never matches.
.assistant_guidance_term_matches <- function(term_norm, query_norm) {
  if (identical(query_norm, term_norm)) return(TRUE)
  words <- strsplit(term_norm, " ", fixed = TRUE)[[1L]]
  words <- words[nzchar(words)]
  if (length(words) == 0L) return(FALSE)
  pattern <- paste0("\\b", words, "\\b", collapse = ".*")
  grepl(pattern, query_norm)
}

#' Verified current PSOC codes suggested by the survey manual for a phrase.
#'
#' Matching is on the whole normalized phrase, or on a manual term being
#' fully contained in it (so "i am a barangay health worker" still hits).
#' Every code is re-verified against the CURRENT edition before it is
#' returned; an unverifiable code is dropped silently rather than surfaced.
#'
#' @return character vector of current-edition PSOC codes, possibly empty.
assistant_survey_psoc_evidence <- function(phrase, version = NULL) {
  p <- .assistant_scalar_chr(phrase)
  if (is.null(p)) return(character(0))
  q <- .assistant_guidance_norm(p)
  if (!nzchar(q)) return(character(0))

  hits <- character(0)
  for (row in ASSISTANT_GUIDANCE_PSOC_EXAMPLES) {
    t <- .assistant_guidance_norm(row$term)
    if (.assistant_guidance_term_matches(t, q)) {
      hits <- c(hits, row$code)
    }
  }
  hits <- unique(hits)
  if (length(hits) == 0L) return(character(0))

  v <- tryCatch(.assistant_resolve_version("psoc", version), error = function(e) NULL)
  if (is.null(v)) return(character(0))
  keep <- vapply(hits, function(cd) {
    nrow(tryCatch(get_classification_entry("psoc", v, cd),
                  error = function(e) data.frame())) == 1L
  }, logical(1))
  hits[keep]
}

#' The manual's activity wording for an industry phrase, for RE-RESOLUTION.
#'
#' Never returns a code to present. `historical_code` is audit metadata
#' only and is explicitly tagged with the vintage it came from.
assistant_survey_activity_hint <- function(phrase) {
  p <- .assistant_scalar_chr(phrase)
  if (is.null(p)) return(NULL)
  q <- .assistant_guidance_norm(p)
  if (!nzchar(q)) return(NULL)

  for (row in ASSISTANT_GUIDANCE_PSIC_ACTIVITY_HINTS) {
    t <- .assistant_guidance_norm(row$term)
    if (.assistant_guidance_term_matches(t, q)) {
      return(list(
        activity_text = row$activity,
        historical_code = row$historical_code,
        historical_vintage = ASSISTANT_GUIDANCE_PSIC_VINTAGE,
        is_current_code = FALSE,
        caution = paste(
          "This code is from", ASSISTANT_GUIDANCE_PSIC_VINTAGE,
          "and MUST NOT be presented as a current PSIC code. Several codes",
          "from that vintage now denote entirely different activities.",
          "Use activity_text to search the current edition instead."
        )
      ))
    }
  }
  NULL
}

#' Is an establishment description too vague to code, per the manual?
#'
#' TRUE only when the description consists ENTIRELY of refused wording --
#' "school" alone is vague, "private general secondary school" is not.
assistant_activity_is_vague <- function(activity) {
  a <- .assistant_scalar_chr(activity)
  if (is.null(a)) return(TRUE)
  q <- .assistant_guidance_norm(a)
  if (!nzchar(q)) return(TRUE)

  if (q %in% .assistant_guidance_norm(ASSISTANT_GUIDANCE_VAGUE_ACTIVITIES)) return(TRUE)

  tokens <- strsplit(q, " ", fixed = TRUE)[[1L]]
  tokens <- tokens[nzchar(tokens)]
  meaningful <- retrieval_meaningful_tokens(tokens)
  if (length(meaningful) == 0L) return(TRUE)

  vague_tokens <- unique(unlist(
    strsplit(.assistant_guidance_norm(ASSISTANT_GUIDANCE_VAGUE_ACTIVITIES), " ", fixed = TRUE),
    use.names = FALSE
  ))
  vague_tokens <- vague_tokens[nzchar(vague_tokens)]
  all(meaningful %in% vague_tokens)
}

#' Does the description mention an outsourcing/agency arrangement?
assistant_activity_mentions_outsourcing <- function(activity) {
  a <- .assistant_scalar_chr(activity)
  if (is.null(a)) return(FALSE)
  q <- tolower(a)
  any(vapply(ASSISTANT_GUIDANCE_OUTSOURCING_HINTS,
             function(h) grepl(h, q, fixed = TRUE), logical(1)))
}

#' Does the description mention a government / public-sector context?
assistant_activity_mentions_government <- function(activity) {
  a <- .assistant_scalar_chr(activity)
  if (is.null(a)) return(FALSE)
  grepl("government|barangay|municipal|city hall|provincial|public sector|lgu|state",
        tolower(a))
}

#' The single most useful real-world probe for a vague or under-specified
#' establishment description, chosen by what the description already says.
assistant_activity_probe_question <- function(activity = NULL, occupation = NULL) {
  if (assistant_activity_mentions_outsourcing(activity)) {
    return(ASSISTANT_GUIDANCE_OUTSOURCING_PROBE)
  }
  if (assistant_activity_mentions_government(activity)) {
    return(ASSISTANT_GUIDANCE_GOVERNMENT_PROBE)
  }
  a <- .assistant_scalar_chr(activity)
  if (is.null(a)) return(assistant_establishment_question(occupation))
  sprintf(
    "\"%s\" is too general to classify on its own. What exactly does the establishment produce or what service does it provide, and is it public or private?",
    a
  )
}
