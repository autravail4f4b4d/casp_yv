# Build-time normalization pipeline for the RM Classification Assistant's
# supplementary knowledge artifacts.
#
# Invoke from the repository root:
#   Rscript scripts/build_assistant_assets.R
#
# OUTPUTS
# -----------------------------------------------------------------
#   data/assistant_common_pairings.rds  -- CBMS 2024 occupation -> 2022 PSOC
#                                          -> PSIC Rev. 5 pairing table.
#   data/assistant_psic_rules.rds       -- compact, topic-keyed distillation
#                                          of the PSIC classification rules.
#   data/assistant_synonyms.rds         -- NOT BUILT in V1: no approved
#                                          source exists (see below).
#
# These artifacts are *supplementary*. They never substitute for the
# canonical classification repository: any individual code surfaced from
# them must still be verified against the official PSIC/PSOC artifacts
# before being shown to a user. Both are optional at runtime -- the
# accessors in R/assistant/assistant_data.R degrade to NULL when an
# artifact is absent so the assistant can keep operating on official
# classification search alone.
#
# SOURCE 1 -- PAIRINGS WORKBOOK
# -----------------------------------------------------------------
# data-raw/CBMS_2024_2022_PSOC_PSIC_Rev5_Mapping.xlsx
#
# The workbook has 6 sheets. Only "PSIC Rev5 Mapping" is used: it carries
# the same occupation rows as the plainer "2022 PSOC Mapping" sheet *plus*
# the Revision 5 codes, rules, confidence grades, and mapping notes, so it
# supersedes that sheet entirely.
#
# Verified structure (direct inspection, not assumed): two banner rows, so
# `skip = 2` puts the header on the real header row, yielding 253 data rows
# across 9 columns.
#
# DATA-INTEGRITY INVARIANTS (the entire point of this pipeline)
#
#   1. Everything is read with col_types = "text" and stays character.
#      PSOC/PSIC codes carry significant leading zeros (e.g. "01121").
#      Nothing here may ever be passed through as.numeric().
#
#   2. A substantial minority of rows have NA in "PSIC Rev. 5 Code(s)".
#      Those are the deliberate "no fixed PSIC / the activity must be
#      reported separately / N/A" cases published by PSA. They are
#      preserved as NA -- never filled, never guessed, never dropped --
#      and flagged via has_fixed_psic = FALSE.
#
#   3. psic_rev5_code is frequently NOT a single code. Published values
#      include alternatives ("96211 / 96220", "01121 / 01122 / 01123") and
#      ranges written with an EN DASH ("01171-01189" with U+2013, and
#      compound forms like "03211-03219 / 03221-03229"). The string is kept
#      verbatim: not split into rows, not dash-normalized, not reduced to a
#      single pick. Downstream tools present it as published.
#
#   4. Text fields are trimmed and internal newlines collapse to single
#      spaces. Otherwise the text is preserved verbatim, including the
#      curly apostrophe in source strings such as "Gov't".
#
# SOURCE 2 -- PSIC CLASSIFICATION RULES
# -----------------------------------------------------------------
# PSIC_Chatbot_Classification_Rules.md (~55,700 characters)
#
# The full document is deliberately NOT shipped into the runtime artifact.
# Sending 55K characters of prose to the model on every turn is exactly
# what this artifact exists to avoid. Instead the substantive rule content
# (sections 2-11) is hand-compacted below into 12 topic entries, each a
# few hundred characters carrying the operative decision logic: the
# diagnostic questions, the decision criteria, and the hard prohibitions.
#
# The compaction is a source-code literal on purpose. Keeping it in the
# build script -- rather than deriving it by a fragile markdown parse --
# makes every editorial compression decision reviewable in version control
# and diffable when the source document is revised.
#
# Excluded on purpose: sections 12-13 (chatbot algorithm / output
# structure -- that is prompt-layer material owned elsewhere), section 15
# (an alternative compact prompt), and Appendix A / Appendix B, which are
# presentation speaker notes and slide transcriptions. None of that
# appendix material belongs in the runtime rule set.
#
# SOURCE 3 -- SYNONYMS (NOT AVAILABLE)
# -----------------------------------------------------------------
# data-raw/classification_synonyms.csv does not exist in this repository.
# No approved synonym source has been supplied, and synonym data cannot be
# invented: a fabricated colloquial-term mapping would silently steer
# classification decisions. The build therefore skips synonyms with a
# console notice and no artifact is written; assistant_synonyms() returns
# NULL and the synonym tool is correctly unavailable in V1.

suppressPackageStartupMessages({
  library(readxl)
  library(tibble)
})

# ---------------------------------------------------------------------
# Paths
# ---------------------------------------------------------------------

PAIRINGS_SOURCE_XLSX <- "data-raw/CBMS_2024_2022_PSOC_PSIC_Rev5_Mapping.xlsx"
PAIRINGS_SOURCE_SHEET <- "PSIC Rev5 Mapping"
PAIRINGS_OUTPUT_RDS <- "data/assistant_common_pairings.rds"

RULES_SOURCE_MD <- "PSIC_Chatbot_Classification_Rules.md"
RULES_OUTPUT_RDS <- "data/assistant_psic_rules.rds"

SYNONYMS_SOURCE_CSV <- "data-raw/classification_synonyms.csv"
SYNONYMS_OUTPUT_RDS <- "data/assistant_synonyms.rds"

# ---------------------------------------------------------------------
# Frozen output contracts
# ---------------------------------------------------------------------

PAIRINGS_COLUMNS <- c(
  "occupation", "confirmed_psoc", "source_industry", "original_psic",
  "psic_rev5_code", "psic_rev5_rule", "mapping_confidence", "mapping_note",
  "psa_source", "has_fixed_psic"
)

# Source column name -> contract column name. Order here is also the
# contract order for the nine character columns.
PAIRINGS_COLUMN_MAP <- c(
  "Occupation"                     = "occupation",
  "Confirmed 2022 PSOC"            = "confirmed_psoc",
  "Source Industry"                = "source_industry",
  "Original PSIC"                  = "original_psic",
  "PSIC Rev. 5 Code(s)"            = "psic_rev5_code",
  "PSIC Rev. 5 Description / Rule" = "psic_rev5_rule",
  "PSIC Mapping Confidence"        = "mapping_confidence",
  "Mapping Note"                   = "mapping_note",
  "PSA Source"                     = "psa_source"
)

RULES_COLUMNS <- c("topic", "title", "rule", "example")

RULES_TOPIC_KEYS <- c(
  "unit_of_classification", "economic_activity", "principal_activity",
  "secondary_activity", "ancillary_activity", "independent_mixed",
  "top_down_bottom_up", "horizontal_integration", "vertical_integration",
  "outsourced_subcontracted", "vague_information", "common_mistakes"
)

# ---------------------------------------------------------------------
# Small helpers
# ---------------------------------------------------------------------

log_step <- function(...) cat("[build_assistant_assets] ", ..., "\n", sep = "")

fail <- function(...) stop(paste0("[build_assistant_assets] ", ...), call. = FALSE)

warn <- function(...) {
  cat("[build_assistant_assets] WARNING: ", paste0(...), "\n", sep = "")
  invisible(NULL)
}

# Trims surrounding whitespace and collapses any internal newline/tab run
# to a single space. NA in, NA out -- emptiness is never manufactured and
# an NA is never turned into "".
clean_text <- function(x) {
  x <- as.character(x)
  cleaned <- gsub("[\r\n\t]+", " ", x)
  cleaned <- gsub("[[:space:]]{2,}", " ", cleaned)
  cleaned <- trimws(cleaned)
  # A cell that was pure whitespace is genuinely empty information, which
  # is NA, not "".
  cleaned[!is.na(cleaned) & cleaned == ""] <- NA_character_
  cleaned
}

# ---------------------------------------------------------------------
# The compacted PSIC rule set
#
# Each entry compresses the cited source sections down to the operative
# decision logic. This is a compression, not a summary: the diagnostic
# questions, criteria, and prohibitions that actually drive a
# classification decision are retained verbatim in substance.
# ---------------------------------------------------------------------

ASSISTANT_PSIC_RULES_SOURCE <- list(

  list(
    topic = "unit_of_classification",
    title = "Unit of classification",
    # Source: 2.1 (Establishment, Enterprise, required behavior)
    rule = paste0(
      "The unit of classification is the unit of observation for which data are collected. ",
      "For PSIC the production unit is either an establishment or an enterprise. ",
      "An ESTABLISHMENT generally has a single ownership, engages in one (or predominantly one) kind of ",
      "economic activity, and sits at a single physical location. ",
      "An ENTERPRISE is the whole business organization or company: it may own several branches, run ",
      "different business activities, and manage multiple locations. ",
      "Before assigning any PSIC code, establish which unit is being classified. Ask when necessary: ",
      "'Are we classifying this particular establishment/location, or the entire enterprise/company?' and ",
      "'Does this location conduct its own distinct activity, or are you describing the activities of the ",
      "whole company?' ",
      "Never mix establishment-level and enterprise-level information without making the unit explicit."
    ),
    example = NA_character_
  ),

  list(
    topic = "economic_activity",
    title = "Economic activity",
    # Source: 2.2 (definition, inputs/outputs, required behavior)
    rule = paste0(
      "An economic activity is a productive activity that uses inputs (capital, labor, energy, materials) ",
      "to produce outputs of goods or services. ",
      "Do not rely on the question 'What is your business?' alone -- a business self-description is not an ",
      "economic activity. Determine instead: What does the establishment actually do? What goods does it ",
      "produce? What goods does it sell? What service does it provide? Who receives or purchases those ",
      "goods/services? How are the outputs produced? ",
      "The actual productive activity -- not the business's label, trade name, or industry self-image -- is ",
      "the basis for classification."
    ),
    example = NA_character_
  ),

  list(
    topic = "principal_activity",
    title = "Principal activity",
    # Source: 3.1 + 4.1 + 4.2 + 4 critical constraint
    rule = paste0(
      "The principal activity is the activity contributing the MOST TO VALUE ADDED, and it is the primary ",
      "basis for classifying the statistical unit. ",
      "Primary criterion: highest share of value added. ",
      "Substitute criteria, used only when value added is unavailable, are an appropriate available proxy: ",
      "revenue or sales, value of shipments, wages and salaries, hours worked, or number of employees. ",
      "Use the most appropriate and available criterion for the case. ",
      "CRITICAL CONSTRAINT: do NOT assume the physically largest, most visible, most familiar, or most ",
      "prominent-looking activity is the principal activity. The principal activity is whichever activity ",
      "contributes the most economically under the applicable criterion. ",
      "If no contribution evidence is available, ask for it rather than inferring it from prominence."
    ),
    example = paste0(
      "A multi-purpose cooperative visibly runs a large grocery store, but salary loans generate the ",
      "highest income, so the principal activity is credit-cooperative activity, not retail."
    )
  ),

  list(
    topic = "secondary_activity",
    title = "Secondary activity",
    # Source: 3.2 (+ 11.3 prohibition on classifying by a secondary activity)
    rule = paste0(
      "A secondary activity is a separate activity that produces separate goods or services FOR THIRD ",
      "PARTIES and is not the principal activity of the unit. ",
      "It is a genuine market activity -- its output leaves the unit -- so it is counted when comparing ",
      "contributions, unlike an ancillary activity. ",
      "But it never determines the classification by its mere existence: the presence of a restaurant, ",
      "warehouse, recreational facility, or other supporting operation does not make that operation the ",
      "principal activity. Rank secondary against principal activities by value added (or the appropriate ",
      "substitute criterion) and classify on the winner."
    ),
    example = NA_character_
  ),

  list(
    topic = "ancillary_activity",
    title = "Ancillary activity",
    # Source: 3.3 (definition, source example, required behavior)
    rule = paste0(
      "An ancillary activity is a separate activity undertaken to SUPPORT the main productive activities of ",
      "the unit rather than to produce goods or services for the market. ",
      "Ancillary activities are excluded when determining the principal activity. ",
      "Do not automatically count every internal function as a separate market activity. Ask: 'Is the output ",
      "of this activity sold or provided to third parties, or is it used only internally to support the ",
      "establishment's other activities?' Internal-only output means ancillary. ",
      "Do not select an ancillary activity as principal merely because it has a dedicated facility, dedicated ",
      "equipment, or its own workers."
    ),
    example = paste0(
      "A restaurant/catering business runs a commissary kitchen producing sauces and partially cooked meals ",
      "exclusively for its own restaurant and catering operations: the commissary is ancillary, not an ",
      "independent market activity."
    )
  ),

  list(
    topic = "independent_mixed",
    title = "Independent mixed activities",
    # Source: 6.1 definition, diagnostic question, 6.2 rule
    rule = paste0(
      "Independent mixed activities occur when an establishment undertakes two or more distinct economic ",
      "activities that are operationally separate, economically independent, and capable of functioning ",
      "individually using separate processes, workers, facilities, or organizational arrangements. ",
      "DIAGNOSTIC QUESTION: 'If one of these activities were removed, could the other activity still operate ",
      "on its own?' A yes is a strong indication the activities are independent. ",
      "RULE: determine the principal activity using value added, or an appropriate substitute criterion when ",
      "value added is unavailable, and classify the unit on that principal activity. ",
      "Remove or flag ancillary activities before making the comparison."
    ),
    example = paste0(
      "A hotel with a full-service restaurant and a recreational facility, where most revenue is hotel ",
      "accommodation: independent mixed activities, classified as operation of hotels."
    )
  ),

  list(
    topic = "top_down_bottom_up",
    title = "Top-down and bottom-up methods",
    # Source: 6.3 (top-down, bottom-up, source preference, important distinction)
    rule = paste0(
      "Two approaches navigate the PSIC hierarchy when determining the principal activity. ",
      "TOP-DOWN: start at the broadest level and move downward -- Section, Division, Group, Class, Subclass ",
      "-- aggregating contributions at each hierarchical level and selecting the highest-contributing branch ",
      "before descending to the next level. ",
      "BOTTOM-UP: identify the detailed activity with the highest contribution and trace its classification ",
      "upward. ",
      "IMPLEMENTATION PREFERENCE: the source states PSA acknowledges the top-down method, but PSA-SCD ",
      "recommends the BOTTOM-UP method for practical application and efficient coding of large volumes of ",
      "records, being more straightforward and less burdensome for data processors. ",
      "IMPORTANT DISTINCTION: do not confuse the principal-activity CRITERION (highest value added, or an ",
      "appropriate substitute) with the hierarchical METHOD used to navigate the PSIC structure. They are ",
      "separate choices."
    ),
    example = NA_character_
  ),

  list(
    topic = "horizontal_integration",
    title = "Horizontally integrated activities",
    # Source: 7.1 definition, diagnostic question, 7.2 rule, 'do not make this mistake'
    rule = paste0(
      "Horizontal integration occurs when an establishment simultaneously produces multiple outputs with ",
      "different characteristics using the SAME production process, workers, machinery, and raw materials, ",
      "such that separating the activities into distinct economic processes is impractical. ",
      "DIAGNOSTIC QUESTION: 'Can the production of these outputs realistically be separated into different ",
      "production activities?' If no -- because the outputs naturally arise from the same process -- ",
      "horizontal integration applies. ",
      "RULE: classify the activities in the SAME SUBCLASS, even though their outputs have different ",
      "characteristics. Do not determine a principal activity among them. ",
      "DO NOT MAKE THIS MISTAKE: do not treat every separately sold output as a separate independent ",
      "activity. The determining factor is HOW the outputs are produced, not merely whether each output is ",
      "sold."
    ),
    example = paste0(
      "Palay milled into rice, with rice bran and rice husk arising automatically from the same milling ",
      "process and also sold: one activity, classified as rice milling."
    )
  ),

  list(
    topic = "vertical_integration",
    title = "Vertically integrated activities",
    # Source: 8.1 definition, diagnostic question, 8.2 rule
    rule = paste0(
      "Vertical integration occurs when an establishment performs two or more SUCCESSIVE STAGES OF ",
      "PRODUCTION, where the output of one process serves as the input to the next: stage 1 output becomes ",
      "stage 2 input, stage 2 output becomes stage 3 input, and so on. ",
      "DIAGNOSTIC QUESTION: 'Does the output of one activity become an input into the next activity performed ",
      "by the same establishment?' If yes, vertical integration applies. ",
      "RULE: classify the establishment on its PRINCIPAL ACTIVITY -- determine which stage contributes the ",
      "most according to value added, or an appropriate substitute criterion when value added is ",
      "unavailable. Do not default to the first stage, the last stage, or the most visible stage."
    ),
    example = paste0(
      "An establishment cultivates coffee beans, roasts them, and runs a cafe; roasting generates the ",
      "highest revenue, so it is classified under processing of coffee and tea."
    )
  ),

  list(
    topic = "outsourced_subcontracted",
    title = "Outsourced or subcontracted activities",
    # Source: 9.1 rule, required behavior, examples
    rule = paste0(
      "Subcontractors, and units carrying out an activity on a contract basis, are classified according to ",
      "the SPECIFIC ECONOMIC ACTIVITY THEY ACTUALLY PERFORM. The contractual arrangement does not determine ",
      "the PSIC classification. ",
      "Do not classify an establishment merely as 'contractor', 'subcontractor', or 'outsourced service ",
      "provider' -- those describe the arrangement, not the activity. ",
      "Instead ask: 'What does this contractor/subcontractor actually do?' and classify that work. ",
      "The identity of the customer, and the fact that the work is outsourced, do not change the nature of ",
      "the activity being performed."
    ),
    example = paste0(
      "A subcontractor that builds complete residential houses performs residential building construction; ",
      "a firm serving as an outsourced accounting department performs accounting/bookkeeping services."
    )
  ),

  list(
    topic = "vague_information",
    title = "Vague or insufficient activity descriptions",
    # Source: 10.1 definition, 10.2 rule, 10.3 probing questions (all five categories)
    rule = paste0(
      "Vague information means a business description too general, incomplete, or ambiguous to determine the ",
      "actual economic activity. The source names: 'buy and sell', 'trading', 'contractor', 'financial ",
      "services', 'online business', 'general services'. ",
      "RULE: DO NOT assign a detailed PSIC code immediately. Probe or validate until the actual goods ",
      "produced/sold or services provided are known. ",
      "PROBING QUESTIONS. Trading / buy and sell: What specific products do you buy and sell? Do you sell ",
      "wholesale or retail? Who are your usual buyers? Do you sell to other businesses, final consumers, or ",
      "both? ",
      "Contractor: What type of contracting service do you provide? What work do your workers actually ",
      "perform? What is the final output or service delivered to the client? ",
      "Financial services: What specific financial service do you provide? Is it lending, insurance, ",
      "remittance, investment activity, payment processing, or another service? What transactions are ",
      "actually performed? ",
      "Online business: What goods or services are sold or provided online? Does the business own the goods ",
      "being sold, act as an intermediary, provide a platform, or provide another service? ",
      "General services: What specific service is performed? What does the customer pay the business to do?"
    ),
    example = NA_character_
  ),

  list(
    topic = "common_mistakes",
    title = "Common classification mistakes (hard prohibitions)",
    # Source: 11.1 - 11.5
    rule = paste0(
      "These are hard prohibitions, not preferences. ",
      "1. DO NOT classify based on the BUSINESS NAME -- a name may mention an activity that is not the ",
      "principal one (a 'Golden Spoon Restaurant' may earn most of its income from catering). ",
      "2. DO NOT classify based on the APPEARANCE of the establishment -- the most visible operation may not ",
      "be the principal activity (a cooperative's large grocery store versus its higher-earning lending). ",
      "3. DO NOT classify based on a SECONDARY OR ANCILLARY activity -- the existence of a restaurant, ",
      "warehouse, recreational facility, commissary, or other supporting operation does not automatically ",
      "make it principal. ",
      "4. DO NOT accept VAGUE descriptions without validation -- 'trading', 'contractor', 'financial ",
      "services' and the like are never sufficient for a detailed PSIC assignment. ",
      "5. DO NOT classify by CONTRACTUAL ARRANGEMENT -- 'outsourced' and 'subcontracted' describe the ",
      "arrangement, not the economic activity."
    ),
    example = NA_character_
  )
)

# ---------------------------------------------------------------------
# Builder: common pairings
# ---------------------------------------------------------------------

build_common_pairings <- function(source_path = PAIRINGS_SOURCE_XLSX,
                                  output_path = PAIRINGS_OUTPUT_RDS) {
  log_step("--- common pairings ---")

  if (!file.exists(source_path)) {
    fail("Pairings source workbook not found at '", source_path, "'. ",
         "This build requires the official CBMS 2024 mapping workbook to be present; ",
         "no pairing data may be synthesized.")
  }

  sheets <- readxl::excel_sheets(source_path)
  if (!PAIRINGS_SOURCE_SHEET %in% sheets) {
    fail("Sheet '", PAIRINGS_SOURCE_SHEET, "' not found in ", source_path,
         ". Sheets present: ", paste(sheets, collapse = ", "))
  }

  # col_types = "text" is load-bearing: it is what keeps leading zeros on
  # PSOC/PSIC codes. Never relax it.
  raw <- readxl::read_excel(
    source_path,
    sheet = PAIRINGS_SOURCE_SHEET,
    col_types = "text",
    skip = 2
  )

  # -- validation 1 (hard): all nine expected source columns present ----
  expected_src <- names(PAIRINGS_COLUMN_MAP)
  missing_src <- setdiff(expected_src, names(raw))
  if (length(missing_src) > 0) {
    fail("Expected source columns missing from sheet '", PAIRINGS_SOURCE_SHEET, "': ",
         paste(missing_src, collapse = ", "),
         ". Columns found: ", paste(names(raw), collapse = " | "),
         ". The workbook layout changed -- fix the parse rather than the expectation.")
  }
  if (length(setdiff(names(raw), expected_src)) > 0) {
    warn("Unexpected extra source columns ignored: ",
         paste(setdiff(names(raw), expected_src), collapse = ", "))
  }
  log_step("all ", length(expected_src), " expected source columns present")

  # -- validation 2 (hard): plausible row count ------------------------
  if (nrow(raw) <= 200) {
    fail("Only ", nrow(raw), " data rows parsed (expected > 200). ",
         "The header offset (skip = 2) or the sheet layout has changed.")
  }
  log_step("row count: ", nrow(raw))

  # -- rename onto the frozen contract, in contract order --------------
  out <- raw[, expected_src, drop = FALSE]
  names(out) <- unname(PAIRINGS_COLUMN_MAP[expected_src])

  # -- clean text; codes stay character throughout ---------------------
  for (nm in names(out)) {
    out[[nm]] <- clean_text(out[[nm]])
  }

  # -- validation 3 (hard): confirmed_psoc character and complete ------
  if (!is.character(out$confirmed_psoc)) {
    fail("confirmed_psoc is ", class(out$confirmed_psoc)[1],
         ", not character. Codes must never be numeric -- leading zeros would be lost.")
  }
  n_missing_psoc <- sum(is.na(out$confirmed_psoc))
  if (n_missing_psoc > 0) {
    fail(n_missing_psoc, " row(s) have a missing confirmed_psoc. ",
         "Every pairing row must carry a confirmed 2022 PSOC code.")
  }
  log_step("confirmed_psoc: character, non-NA for all ", nrow(out), " rows")

  # -- has_fixed_psic: derived strictly from NA-ness of the code -------
  # NA here is published information ("no fixed PSIC / activity must be
  # reported / N/A"), not a defect. It is preserved as NA.
  out$has_fixed_psic <- !is.na(out$psic_rev5_code)

  # -- validation 4 (hard): the no-fixed-PSIC rows survived the parse --
  n_no_fixed <- sum(!out$has_fixed_psic)
  if (n_no_fixed == 0) {
    fail("Zero rows have an NA psic_rev5_code. The source is known to contain ",
         "deliberate 'no fixed PSIC' rows, so a count of zero means the parse broke ",
         "(or NAs were silently filled). Investigate before shipping this artifact.")
  }
  log_step("no-fixed-PSIC rows (psic_rev5_code is NA, has_fixed_psic = FALSE): ", n_no_fixed)
  log_step("rows with a published PSIC Rev. 5 code: ", sum(out$has_fixed_psic))

  # -- validation 5 (report): mapping_confidence breakdown -------------
  conf <- table(out$mapping_confidence, useNA = "ifany")
  log_step("mapping_confidence breakdown:")
  for (i in seq_along(conf)) {
    label <- names(conf)[i]
    if (is.na(label)) label <- "<NA>"
    log_step("  ", label, ": ", conf[[i]])
  }
  if (length(conf) == 0) warn("mapping_confidence has no values at all.")

  # -- cosmetic reporting: multi-code and range forms preserved --------
  n_multi <- sum(grepl(" / ", out$psic_rev5_code, fixed = TRUE), na.rm = TRUE)
  n_range <- sum(grepl("–", out$psic_rev5_code, fixed = TRUE), na.rm = TRUE)
  log_step("psic_rev5_code values kept verbatim -- multi-code ('a / b'): ", n_multi,
           "; en-dash ranges: ", n_range)
  if (n_multi == 0) warn("No multi-code psic_rev5_code values found; expected some.")
  if (n_range == 0) warn("No en-dash range psic_rev5_code values found; expected some.")

  n_leading_zero <- sum(grepl("^0", out$original_psic), na.rm = TRUE) +
    sum(grepl("^0", out$psic_rev5_code), na.rm = TRUE)
  log_step("code values retaining a leading zero: ", n_leading_zero)
  if (n_leading_zero == 0) {
    fail("No code values start with '0'. Leading zeros have been lost -- ",
         "the workbook was almost certainly read as numeric.")
  }

  # -- final shape assertions against the frozen contract --------------
  out <- tibble::as_tibble(out)
  out <- out[, PAIRINGS_COLUMNS, drop = FALSE]
  stopifnot(identical(names(out), PAIRINGS_COLUMNS))
  stopifnot(all(vapply(out[, setdiff(PAIRINGS_COLUMNS, "has_fixed_psic")],
                       is.character, logical(1))))
  stopifnot(is.logical(out$has_fixed_psic), !any(is.na(out$has_fixed_psic)))

  dir.create(dirname(output_path), showWarnings = FALSE, recursive = TRUE)
  saveRDS(out, output_path)
  log_step("wrote ", output_path, " (", nrow(out), " rows x ", ncol(out),
           " cols, ", file.size(output_path), " bytes)")

  invisible(out)
}

# ---------------------------------------------------------------------
# Builder: PSIC rules
# ---------------------------------------------------------------------

build_psic_rules <- function(source_path = RULES_SOURCE_MD,
                             output_path = RULES_OUTPUT_RDS) {
  log_step("--- PSIC rules ---")

  # The source document is not parsed; the compaction is authored above.
  # It is still read for a size reference so the build report can show how
  # much was compressed away, and so a missing source is visible.
  source_chars <- NA_integer_
  if (file.exists(source_path)) {
    source_chars <- sum(nchar(readLines(source_path, warn = FALSE), type = "chars")) +
      length(readLines(source_path, warn = FALSE))
    log_step("source document ", source_path, ": ~", source_chars, " characters")
  } else {
    warn("Source document '", source_path, "' not found. The compacted rules below are ",
         "authored in this script and are still written, but they can no longer be ",
         "checked against the source. Restore the document before revising them.")
  }

  rules <- tibble::tibble(
    topic   = vapply(ASSISTANT_PSIC_RULES_SOURCE, function(r) as.character(r$topic), character(1)),
    title   = vapply(ASSISTANT_PSIC_RULES_SOURCE, function(r) as.character(r$title), character(1)),
    rule    = vapply(ASSISTANT_PSIC_RULES_SOURCE, function(r) as.character(r$rule), character(1)),
    example = vapply(ASSISTANT_PSIC_RULES_SOURCE, function(r) {
      if (is.null(r$example) || is.na(r$example)) NA_character_ else as.character(r$example)
    }, character(1))
  )

  # -- hard validations ------------------------------------------------
  if (!identical(names(rules), RULES_COLUMNS)) {
    fail("Rules columns are ", paste(names(rules), collapse = ", "),
         "; contract requires ", paste(RULES_COLUMNS, collapse = ", "))
  }
  if (anyDuplicated(rules$topic) > 0) {
    fail("Duplicate rule topic(s): ",
         paste(unique(rules$topic[duplicated(rules$topic)]), collapse = ", "))
  }
  if (!setequal(rules$topic, RULES_TOPIC_KEYS)) {
    fail("Rule topics do not match the frozen 12-key contract. Missing: ",
         paste(setdiff(RULES_TOPIC_KEYS, rules$topic), collapse = ", "),
         "; unexpected: ", paste(setdiff(rules$topic, RULES_TOPIC_KEYS), collapse = ", "))
  }
  # Emit in the canonical contract order.
  rules <- rules[match(RULES_TOPIC_KEYS, rules$topic), , drop = FALSE]

  if (any(is.na(rules$rule) | trimws(rules$rule) == "")) {
    fail("Empty rule text for topic(s): ",
         paste(rules$topic[is.na(rules$rule) | trimws(rules$rule) == ""], collapse = ", "))
  }
  if (any(is.na(rules$title) | trimws(rules$title) == "")) {
    fail("Empty title for topic(s): ",
         paste(rules$topic[is.na(rules$title) | trimws(rules$title) == ""], collapse = ", "))
  }

  rule_chars <- nchar(rules$rule, type = "chars")
  total_chars <- sum(rule_chars) + sum(nchar(rules$example, type = "chars"), na.rm = TRUE)

  # Compaction is the whole point; a runaway entry means the source text
  # was pasted rather than compressed.
  if (any(rule_chars > 2000)) {
    fail("Rule text over the 2000-character compaction ceiling for topic(s): ",
         paste(rules$topic[rule_chars > 2000], collapse = ", "),
         ". Compress the operative logic further rather than raising the ceiling.")
  }
  if (any(rule_chars < 300)) {
    warn("Unusually short rule text (< 300 chars) for topic(s): ",
         paste(rules$topic[rule_chars < 300], collapse = ", "),
         ". Check that the operative decision logic was not dropped.")
  }

  log_step("topics: ", nrow(rules), "/", length(RULES_TOPIC_KEYS), " present")
  log_step("rule length: min ", min(rule_chars), ", median ", stats::median(rule_chars),
           ", max ", max(rule_chars), " chars")
  log_step("examples supplied: ", sum(!is.na(rules$example)), "/", nrow(rules))
  log_step("total compacted size: ", total_chars, " chars",
           if (!is.na(source_chars)) {
             paste0(" (", round(100 * total_chars / source_chars, 1),
                    "% of the ~", source_chars, "-char source)")
           } else "")

  stopifnot(all(vapply(rules, function(x) is.character(x), logical(1))))

  dir.create(dirname(output_path), showWarnings = FALSE, recursive = TRUE)
  saveRDS(rules, output_path)
  log_step("wrote ", output_path, " (", nrow(rules), " rows x ", ncol(rules),
           " cols, ", file.size(output_path), " bytes)")

  invisible(rules)
}

# ---------------------------------------------------------------------
# Builder: synonyms (skipped -- no approved source)
# ---------------------------------------------------------------------

build_synonyms <- function(source_path = SYNONYMS_SOURCE_CSV,
                           output_path = SYNONYMS_OUTPUT_RDS) {
  log_step("--- synonyms ---")

  if (!file.exists(source_path)) {
    log_step("SKIPPED: no synonym source at '", source_path, "'.")
    log_step("  No approved synonym list has been supplied for this repository, and ",
             "synonym data must never be invented -- a fabricated colloquial-term ")
    log_step("  mapping would silently steer classification decisions. ",
             "No artifact is written.")
    log_step("  Runtime effect: assistant_synonyms() returns NULL and ",
             "assistant_data_status()$synonyms is FALSE, so the synonym")
    log_step("  tool is correctly unavailable rather than silently wrong. ",
             "To enable it, add an official/approved CSV at the path above")
    log_step("  and extend this builder.")
    return(invisible(NULL))
  }

  # Deliberately not implemented: if a source ever appears, its schema must
  # be agreed and validated here before an artifact is produced. Failing
  # loudly beats writing an unvalidated artifact.
  fail("A synonym source appeared at '", source_path, "' but no validated schema or ",
       "build step exists for it yet. Define and review the synonym contract before ",
       "writing ", output_path, ".")
}

# ---------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------

main <- function() {
  log_step("build started ", format(Sys.time(), "%Y-%m-%d %H:%M:%S"))
  if (!dir.exists("R") || !dir.exists("data-raw")) {
    fail("Run this script from the repository root (expected R/ and data-raw/ here). ",
         "Current working directory: ", getwd())
  }

  build_common_pairings()
  build_psic_rules()
  build_synonyms()

  log_step("build finished OK")
  invisible(NULL)
}

if (sys.nframe() == 0L || identical(environment(), globalenv())) {
  main()
}
