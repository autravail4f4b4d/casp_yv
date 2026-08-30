# W2 -- context-compatibility gates (semantic and lexical alike).
#
# WHY THIS EXISTS, measured on the live pre-staging-v8 build:
#
#   "teacher" + "private high school"
#       -> PSOC 5312 TEACHERS' AIDES        (wanted 2330)
#       -> PSIC 85102 Private pre-primary   (wanted 85312 secondary)
#   "palay farming"
#       -> PSIC 10611 Rice milling          (wanted growing of rice)
#
# None of these is a RECALL failure -- the correct rows are retrieved too.
# Every wrong winner is lexically excellent: "teacher" is a whole token of
# "TEACHERS' AIDES", "private" is a whole token of "Private pre-primary or
# pre-school education", and "palay" expands to "rice" which is a whole
# token of "Rice milling". The existing context gate
# (assistant_context_plausible) asks "does ANY query token find support in
# this label?" and the honest answer for all three is yes. That gate was
# built to reject the UNRELATED ("nurse" -> nursery grower); it cannot
# reject the RELATED-BUT-INCOMPATIBLE.
#
# THE RULE HERE IS DIFFERENT AND NARROWER: along a small number of
# controlled facets where the classification itself draws a hard line, a
# candidate is rejected when its OWN facet value CONTRADICTS the facet
# value the user's wording states. Three properties keep this safe:
#
#   1. Conflict only, never absence. A facet the query does not state, or
#      the candidate does not state, yields no opinion and no rejection.
#      This is why "nurse"/"private hospital" is untouched by this module.
#   2. Controlled vocabularies, closed and small. No open-ended scoring, no
#      similarity, no model confidence -- a facet is present or it is not.
#   3. Survey-manual evidence outranks it. PSA's own published coding
#      decision for an exact phrase is authority; this heuristic is not,
#      and never vetoes it (see assistant_contextual_coding.R).
#
# This gate is deliberately placed where it covers EVERY candidate
# generator uniformly -- lexical, fuzzy, n-gram and (when enabled) semantic
# -- because spec 19 requires exactly that: cosine similarity must not be
# able to buy its way past a contradiction any more than a substring can.

# --- activity action (spec 17/18) ------------------------------------------
#
# The palay case is the canonical one: growing rice, milling rice and
# preparing rice for market are three different PSIC families that share
# almost all of their vocabulary. Only the VERB separates them.
#
# Keys are matched as whole tokens against normalized text. Deliberately
# minimal -- every entry below is one the canonical PSIC/PSOC distinctions
# actually turn on. Adding a vague verb here would start rejecting correct
# candidates, so absence is the safe default.
ASSISTANT_ACTION_VOCABULARY <- list(
  grow        = c("grow", "growing", "grows", "grown", "farming", "farm",
                  "farmer", "farmers", "cultivation", "cultivating",
                  "plantation", "planting", "orchard"),
  raise       = c("raising", "breeding", "livestock", "poultry", "piggery"),
  catch       = c("fishing", "catching", "aquaculture", "fishery"),
  manufacture = c("manufacture", "manufacturing", "manufactured"),
  mill        = c("milling", "mill", "mills", "milled"),
  process     = c("processing", "processed", "canning", "refining"),
  prepare     = c("preparation", "preparing", "postharvest"),
  repair      = c("repair", "repairing", "maintenance", "servicing"),
  transport   = c("transport", "transportation", "hauling", "freight"),
  educate     = c("education", "educational", "teaching", "school",
                  "schools", "instruction", "tutorial"),
  administer  = c("administration", "administrative", "governance"),
  # Health service delivery is a different PSIC section from public
  # administration entirely (Q vs O). Without this facet a government
  # query whose wording contains "public" could land on "PUBLIC general
  # hospital activities" -- measured, while wiring the government
  # normalization below.
  provide_health_service = c("hospital", "hospitals", "clinic", "clinics",
                             "medical", "health", "healthcare", "dental",
                             "dentistry", "midwifery", "nursing", "therapy"),
  construct   = c("construction", "constructing", "building", "buildings"),
  regulate    = c("regulation", "regulating", "regulatory")
)

# Actions that are NOT mutually exclusive in practice and must therefore
# never veto each other. "construction" work happens at a "building";
# "education" happens at a "school". Pairs listed here are treated as
# compatible in BOTH directions.
.ASSISTANT_ACTION_COMPATIBLE <- list(
  c("construct", "repair"),
  c("educate", "administer"),
  c("administer", "regulate"),
  c("grow", "raise"),
  c("manufacture", "process")
)

# --- education level (spec 19) ---------------------------------------------
#
# "private high school" must not match "Private pre-primary or pre-school
# education". PSA titles say secondary/primary; users say high
# school/elementary, so both vocabularies appear here.
ASSISTANT_EDUCATION_LEVELS <- list(
  pre_primary = c("preprimary", "preschool", "prekindergarten", "kindergarten",
                  "nursery", "daycare", "pre", "primaryorpreschool"),
  primary     = c("primary", "elementary", "grade"),
  secondary   = c("secondary", "highschool", "high", "junior", "senior"),
  tertiary    = c("tertiary", "college", "university", "higher", "collegiate"),
  post_secondary_non_tertiary = c("vocational", "technical", "postsecondary")
)

# --- ownership (spec 19) ---------------------------------------------------
#
# PSIC splits many service families strictly by sector: 85311 PUBLIC
# general secondary education vs 85312 PRIVATE general secondary
# education; public vs private hospitals; and so on. The user almost
# always states this ("private high school") and the classification always
# encodes it, so a contradiction here is never a near-miss -- it is the
# wrong half of a deliberate binary split.
ASSISTANT_OWNERSHIP_VALUES <- list(
  private = c("private", "privately", "proprietary", "nongovernment",
              "commercial"),
  public  = c("public", "government", "governmental", "state", "national",
              "municipal", "provincial", "barangay", "lgu")
)

# --- vehicle type (spec 20 "driver types", spec 48) ------------------------
#
# Measured: "truck driver" selected 8331 BUS AND TRAM DRIVERS. The word
# "truck" appears nowhere in that label; it won on "driver" -> "DRIVERS"
# alone, while 8332 HEAVY TRUCK AND LORRY DRIVERS sat lower in retrieval
# order. PSOC 833 is literally named "HEAVY TRUCK AND BUS DRIVERS", so the
# truck/bus split is a distinction the classification draws explicitly.
#
# The parent 833 names BOTH vehicles, so it yields both facet values and
# therefore never conflicts with either child -- an aggregate is not
# contradicted by its own children's specifics.
ASSISTANT_VEHICLE_VALUES <- list(
  truck      = c("truck", "trucks", "lorry", "lorries"),
  bus        = c("bus", "buses", "tram", "trams", "coach"),
  motorcycle = c("motorcycle", "motorcycles", "tricycle", "tricycles"),
  bicycle    = c("bicycle", "bicycles", "pedicab"),
  taxi       = c("taxi", "taxis", "taxicab"),
  train      = c("train", "trains", "locomotive", "rail")
)

# --- occupation role (spec 20) ---------------------------------------------
#
# "teacher" must not select "TEACHERS' AIDES" unless the duties described
# are actually aide/assistant duties. This is a two-value facet on purpose:
# principal practitioner versus support staff.
ASSISTANT_ROLE_SUPPORT_TERMS <- c(
  "aide", "aides", "assistant", "assistants", "helper", "helpers",
  "attendant", "attendants", "auxiliary", "apprentice", "trainee"
)

# --- unmatched specialization qualifiers -----------------------------------
#
# Distinct from a RESIDUAL marker (assistant_context.R), which flags a
# catch-all defined by what it is not ("... n.e.c.", "Other ..."). These
# are the opposite shape: a NARROWER sibling defined by an extra qualifier
# the plain category does not carry.
#
# Measured need. After the ownership veto below correctly removed every
# PUBLIC row, "private high school" still had four surviving detailed
# siblings, all genuinely private and genuinely secondary:
#
#   85312 Private general secondary education, children WITHOUT special needs
#   85314 Private general secondary education, children WITH special needs
#   85322 Private TECHNICAL AND VOCATIONAL secondary education ...
#   85324 Private TECHNICAL AND VOCATIONAL secondary education ...
#
# A plain "high school" states neither qualifier, so the unqualified
# reading (85312) is the intended one and the other three should not be
# treated as equal contenders -- asking the user to choose between them
# would be asking them to re-state something they never implied.
#
# Each entry: `marker` = regex on the normalized label, `query` = regex
# that, when present in the user's own wording, means they DID ask for the
# specialization and it must not be penalised.
.ASSISTANT_SPECIALIZATION_QUALIFIERS <- list(
  list(marker = "\\bvocational\\b|\\btechnical\\b",
       query  = "\\bvocational\\b|\\btechnical\\b|\\btech\\s*voc\\b|\\btvet\\b"),
  list(marker = "\\bwith\\s+special\\b|\\bspecial\\s+needs\\b|\\bspecial\\s+education\\b",
       query  = "\\bspecial\\b|\\bsped\\b|\\bdisab")
)

# "without special needs" contains "special needs" but is the DEFAULT
# population, not a specialization. Neutralised before matching.
.ASSISTANT_SPECIALIZATION_NEUTRAL <- "\\bwithout\\s+special\\s+needs?\\b"

#' How many specialization qualifiers does the candidate carry that the
#' user's wording never asked for?
#'
#' @return integer(1), 0 when the candidate is the plain reading.
assistant_compat_specialization_penalty <- function(query_texts, label) {
  lbl <- tolower(as.character(label))
  if (length(lbl) != 1L || is.na(lbl) || !nzchar(lbl)) return(0L)
  lbl <- gsub(.ASSISTANT_SPECIALIZATION_NEUTRAL, " ", lbl)
  q <- tolower(paste(as.character(query_texts), collapse = " "))

  sum(vapply(.ASSISTANT_SPECIALIZATION_QUALIFIERS, function(spec) {
    if (!grepl(spec$marker, lbl)) return(0L)
    if (grepl(spec$query, q)) return(0L)
    1L
  }, integer(1)))
}

.assistant_compat_tokens <- function(text) {
  t <- as.character(text)
  if (length(t) != 1L || is.na(t) || !nzchar(t)) return(character(0))
  # Fold the hyphen/space variants the vocabularies above are written
  # against ("pre-primary" -> preprimary, "high school" -> highschool) so a
  # two-word user phrase and a hyphenated canonical title agree.
  low <- tolower(t)
  low <- gsub("[-/]", "", low)
  low <- gsub("\\bhigh\\s+school\\b", "highschool", low)
  low <- gsub("\\bpre\\s*primary\\b", "preprimary", low)
  low <- gsub("\\bpre\\s*school\\b", "preschool", low)
  low <- gsub("\\bpost\\s*secondary\\b", "postsecondary", low)
  low <- gsub("\\bpost\\s*harvest\\b", "postharvest", low)
  n <- .assistant_norm_text(low)
  if (!nzchar(n)) return(character(0))
  tk <- strsplit(n, " ", fixed = TRUE)[[1L]]
  unique(tk[nzchar(tk)])
}

#' Which controlled facet values does a text state?
#'
#' A text may legitimately state more than one (PSOC 833 "HEAVY TRUCK AND
#' BUS DRIVERS" states both truck and bus), which is why this returns a
#' vector rather than a single value: an aggregate that names several
#' alternatives must not be judged to contradict any one of them.
#'
#' @param text character(1).
#' @param vocabulary named list of controlled value -> term vector.
#' @return character vector of facet values present; `character(0)` means
#'   the text states none, which callers must read as "no opinion".
assistant_compat_facets <- function(text, vocabulary) {
  tk <- .assistant_compat_tokens(text)
  if (length(tk) == 0L) return(character(0))
  hits <- names(vocabulary)[vapply(vocabulary, function(terms) {
    any(tk %in% terms)
  }, logical(1))]
  unique(hits)
}

.assistant_actions_compatible <- function(a, b) {
  if (identical(a, b)) return(TRUE)
  for (pair in .ASSISTANT_ACTION_COMPATIBLE) {
    if (all(c(a, b) %in% pair)) return(TRUE)
  }
  FALSE
}

#' Do the query and candidate CONTRADICT each other on a controlled facet?
#'
#' Returns TRUE only when both sides state a facet value and no stated
#' value is compatible. Either side stating nothing => FALSE (no opinion).
#'
#' @return logical(1), never NA.
assistant_compat_conflict <- function(query_texts, label, description = NA_character_) {
  q_text <- paste(as.character(query_texts), collapse = " ")
  if (!nzchar(trimws(q_text))) return(FALSE)
  c_text <- as.character(label)
  if (length(c_text) != 1L || is.na(c_text) || !nzchar(c_text)) return(FALSE)

  # --- action -------------------------------------------------------------
  q_act <- assistant_compat_facets(q_text, ASSISTANT_ACTION_VOCABULARY)
  c_act <- assistant_compat_facets(c_text, ASSISTANT_ACTION_VOCABULARY)
  if (length(q_act) > 0L && length(c_act) > 0L) {
    ok <- any(vapply(q_act, function(a) {
      any(vapply(c_act, function(b) .assistant_actions_compatible(a, b), logical(1)))
    }, logical(1)))
    if (!ok) return(TRUE)
  }

  # --- education level ----------------------------------------------------
  q_edu <- assistant_compat_facets(q_text, ASSISTANT_EDUCATION_LEVELS)
  c_edu <- assistant_compat_facets(c_text, ASSISTANT_EDUCATION_LEVELS)
  if (length(q_edu) > 0L && length(c_edu) > 0L && length(intersect(q_edu, c_edu)) == 0L) {
    return(TRUE)
  }

  # --- vehicle type -------------------------------------------------------
  q_veh <- assistant_compat_facets(q_text, ASSISTANT_VEHICLE_VALUES)
  c_veh <- assistant_compat_facets(c_text, ASSISTANT_VEHICLE_VALUES)
  if (length(q_veh) > 0L && length(c_veh) > 0L && length(intersect(q_veh, c_veh)) == 0L) {
    return(TRUE)
  }

  # --- ownership ----------------------------------------------------------
  #
  # "city government" / "local government unit" legitimately contain the
  # public marker, and their canonical labels do too, so this agrees
  # rather than conflicting. The case it exists for is "PRIVATE high
  # school" landing on "PUBLIC general secondary education".
  q_own <- assistant_compat_facets(q_text, ASSISTANT_OWNERSHIP_VALUES)
  c_own <- assistant_compat_facets(c_text, ASSISTANT_OWNERSHIP_VALUES)
  if (length(q_own) > 0L && length(c_own) > 0L && length(intersect(q_own, c_own)) == 0L) {
    return(TRUE)
  }

  # --- occupation role ----------------------------------------------------
  #
  # Asymmetric on purpose. A query that does NOT describe support duties
  # must not land on a support-staff category; but a query that DOES
  # describe them may legitimately match either, since many principal
  # titles ("TEACHERS' AIDES" aside) never say the word.
  q_tk <- .assistant_compat_tokens(q_text)
  c_tk <- .assistant_compat_tokens(c_text)
  q_support <- any(q_tk %in% ASSISTANT_ROLE_SUPPORT_TERMS)
  c_support <- any(c_tk %in% ASSISTANT_ROLE_SUPPORT_TERMS)
  if (c_support && !q_support) {
    # Only a veto when the query names a PRINCIPAL role that the candidate
    # is the support variant OF -- i.e. they share a non-support content
    # token. Without that shared token this is an unrelated candidate the
    # ordinary context gate already handles, and vetoing here would reject
    # legitimately-support occupations ("janitor" -> caretaker/attendant).
    #
    # Compared by SIMILARITY, not set intersection: the pair this rule
    # exists for is "teacher" vs "TEACHERS' AIDES", whose content tokens
    # are `teacher` and `teachers` -- an exact intersection is empty and
    # the veto silently never fired. Reuses the retrieval layer's own
    # similarity primitive and its established 0.8 floor rather than
    # inventing a second notion of "the same word".
    q_content <- retrieval_meaningful_tokens(setdiff(q_tk, ASSISTANT_ROLE_SUPPORT_TERMS))
    c_content <- retrieval_meaningful_tokens(setdiff(c_tk, ASSISTANT_ROLE_SUPPORT_TERMS))
    if (length(q_content) > 0L && length(c_content) > 0L) {
      c_nchar <- nchar(c_content)
      shared <- any(vapply(q_content, function(qt) {
        sim <- .retrieval_fuzzy_token_similarity(qt, c_content, c_nchar)
        any(sim >= RETRIEVAL_EVIDENCE_MIN_TOKEN_SIMILARITY)
      }, logical(1)))
      if (isTRUE(shared)) return(TRUE)
    }
  }

  FALSE
}

#' How many of the query's own meaningful tokens does this label support?
#'
#' A DISCRIMINATOR, not a filter: it never rejects anything, it only says
#' which surviving sibling answers more of what the user actually said.
#'
#' Measured need. Once the ownership veto correctly removed every PUBLIC
#' hospital row, "private general hospital" was left with three genuinely
#' private siblings -- 86121 general, 86122 mental, 86123 maternity -- and
#' the aggregate-vs-detailed rule saw a real sibling ambiguity where none
#' exists: the user said "general", and only 86121 says "general". The
#' public rows had previously masked this by occupying the bounded
#' candidate list.
#'
#' Deliberately NOT a hard-coded list of medical specialties (or school
#' types, or crop types). Counting matched query tokens generalises to
#' every family in every system, and it stays silent -- every sibling
#' scoring equally -- exactly where the ambiguity IS real: "growing paddy
#' rice" supports {growing, rice} equally against irrigated / rainfed /
#' upland, so the irrigation question is still asked.
#'
#' Uses the retrieval layer's own token-similarity primitive and its
#' established 0.8 floor, so "hospital"/"hospitals" and
#' "teacher"/"teachers" count as supported.
#'
#' @return integer(1) count of distinct supported query tokens.
assistant_compat_coverage <- function(query_texts, label) {
  lbl <- as.character(label)
  if (length(lbl) != 1L || is.na(lbl) || !nzchar(lbl)) return(0L)

  q_tokens <- unique(unlist(
    lapply(query_texts, function(x) retrieval_tokens(retrieval_normalize(x))[[1L]]),
    use.names = FALSE
  ))
  q_meaningful <- unique(retrieval_meaningful_tokens(q_tokens))
  if (length(q_meaningful) == 0L) return(0L)

  c_vocab <- unique(retrieval_meaningful_tokens(
    retrieval_tokens(retrieval_normalize(lbl))[[1L]]
  ))
  if (length(c_vocab) == 0L) return(0L)
  c_nchar <- nchar(c_vocab)

  sum(vapply(q_meaningful, function(qt) {
    sim <- .retrieval_fuzzy_token_similarity(qt, c_vocab, c_nchar)
    as.integer(any(sim >= RETRIEVAL_EVIDENCE_MIN_TOKEN_SIMILARITY))
  }, integer(1)))
}

#' Drop candidates that contradict the query on a controlled facet.
#'
#' @param rows data.frame with `label`, optionally `description`.
#' @param query_texts character vector (slot phrase plus expansions).
#' @param exempt logical vector, TRUE where a row must never be vetoed
#'   (survey-manual evidence -- PSA's own published decision).
#'
#' @return logical vector, TRUE = keep. Same length as `nrow(rows)`.
assistant_compat_keep <- function(rows, query_texts, exempt = NULL) {
  if (is.null(rows) || nrow(rows) == 0L) return(logical(0))
  n <- nrow(rows)
  if (is.null(exempt)) exempt <- rep(FALSE, n)
  exempt <- rep_len(as.logical(exempt), n)
  desc <- if ("description" %in% names(rows)) {
    as.character(rows$description)
  } else {
    rep(NA_character_, n)
  }
  vapply(seq_len(n), function(i) {
    if (isTRUE(exempt[[i]])) return(TRUE)
    !assistant_compat_conflict(query_texts, rows$label[[i]], desc[[i]])
  }, logical(1))
}
