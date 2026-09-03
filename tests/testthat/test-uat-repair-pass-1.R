# UAT Repair Pass 1 — the defects this pass exists to close.
#
# Each block names the defect it pins. These are the regressions that would
# be silent: an "Ask RM" button that attaches and says nothing, a grounding
# block that lets the model invent duties, a docking rule that squeezes the
# workspace, a review dialog that quietly implies the pair is correct.

.render <- function(tag) paste(as.character(htmltools::renderTags(tag)$html),
                               collapse = "")

# Strips R comments, so prose documenting a defect cannot fail a
# structural assertion about the CODE.
.r_code_only_uat <- function(src) {
  paste(sub("#.*$", "", strsplit(src, "\n", fixed = TRUE)[[1]]), collapse = "\n")
}

.repo <- normalizePath(file.path(getwd(), "..", ".."), mustWork = TRUE)

.read_file <- function(...) {
  path <- file.path(.repo, ...)
  expect_true(file.exists(path), info = paste("missing file:", path))
  paste(readLines(path, warn = FALSE), collapse = "\n")
}


# ===========================================================================
# UAT-RM-01 — "Ask RM" must actually ask
# ===========================================================================

test_that("every automatic intent is recognised as a referential turn", {
  # THE FAILURE THIS PREVENTS. A wording the detector does not recognise
  # routes the automatic turn into the CODING path, which would classify
  # the sentence "Explain this classification entry" as if it described
  # somebody's job. Each intent is checked, not assumed.
  for (intent in c(RM_INTENT_ENTRY, RM_INTENT_CORRESPONDENCE,
                   RM_INTENT_CODING_PAIR)) {
    expect_true(assistant_explanation_requested(intent), info = intent)
  }

  # And the wording that ISN'T recognised is documented as rejected rather
  # than silently used.
  expect_false(assistant_explanation_requested("Review this coding pair."))
})

test_that("the automatic turn goes through the ordinary composer", {
  src <- .read_file("R", "ui", "ui_sidecar.R")
  # ONE entry point. `update_chat_user_input(submit = TRUE)` fills and
  # submits the real composer, so the message arrives on the same
  # `rm_assistant-chat_user_input` input as anything the user types --
  # same observer, same assistant_handle_turn(), same response guard.
  expect_true(grepl("shinychat::update_chat_user_input(", src, fixed = TRUE))
  expect_true(grepl("submit = TRUE", src, fixed = TRUE))

  # THE NAMESPACED CHAT ELEMENT ID, not the module id. `chat_mod_ui("rm_
  # assistant")` mounts its chat as NS(id)("chat"), and this call is made
  # from the app's session rather than the module's -- so the bare
  # "rm_assistant" addresses nothing and the turn is silently never sent.
  # Found in browser UAT: the panel opened, the chip attached, and RM said
  # nothing, which is the very defect this workstream exists to fix.
  expect_identical(RM_CHAT_ELEMENT_ID, "rm_assistant-chat")
  expect_true(grepl("RM_CHAT_ELEMENT_ID, value = prompt", src, fixed = TRUE))
  expect_false(grepl('update_chat_user_input(\n      "rm_assistant",', src, fixed = TRUE))

  # A synthesised exchange appended straight to the transcript would be a
  # second assistant path, which is the thing this design must not have.
  expect_false(grepl("chat_append(", src, fixed = TRUE))
  expect_false(grepl("assistant_handle_turn", .r_code_only_uat(src), fixed = TRUE))
})

test_that("all three contextual actions attach AND ask", {
  src <- .read_file("R", "ui", "ui_sidecar.R")
  # Each observer ends in ask(), not merely in an attach + open.
  for (intent in c("ask(RM_INTENT_ENTRY)", "ask(RM_INTENT_CORRESPONDENCE)",
                   "ask(RM_INTENT_CODING_PAIR)")) {
    expect_true(grepl(intent, src, fixed = TRUE), info = intent)
  }
  # The panel is opened by the same helper, so no action can ask without
  # showing the answer arriving.
  expect_true(grepl("rm_sidecar_open(session)", src, fixed = TRUE))
})

test_that("the chip survives the automatic turn", {
  # Attaching is what makes the turn answerable; the chip is what makes it
  # visible and removable. `ask()` must not clear either.
  src <- .read_file("R", "ui", "ui_sidecar.R")
  ask_body <- regmatches(
    src, regexpr("ask <- function\\(prompt\\)[^}]*\\}", src, perl = TRUE)
  )
  expect_gt(length(ask_body), 0L)
  expect_false(grepl("attached(", ask_body, fixed = TRUE))
  expect_false(grepl("sync_turn_state", ask_body, fixed = TRUE))
})


# ===========================================================================
# UAT-RM-02 — no unsupported contextual prose
# ===========================================================================

test_that("the grounding block states the verified fields it may use", {
  v <- assistant_verify_attached_context(
    assistant_context_descriptor_entry("psoc", "2022", "1112")
  )
  skip_if(is.null(v), "PSOC 2022 1112 not present in this build")
  note <- assistant_render_attached_context(v)

  # Present: only what the repository actually returned.
  expect_true(grepl(v$code, note, fixed = TRUE))
  expect_true(grepl(v$label, note, fixed = TRUE))
  expect_true(grepl("Philippine Statistics Authority", note, fixed = TRUE))
})

test_that("absent descriptive metadata is acknowledged, not invented", {
  # A record the descriptive artifact does not cover at all. PSOC 1112 is
  # deliberately NOT used here any more: since the PSOC 2022 descriptive
  # integration it HAS an official definition, tasks and examples, and a
  # model handed the definition must not also be told the definition is
  # unavailable. The safeguard is unchanged -- say what is missing, never
  # invent it -- but which fields are missing is now per record.
  v <- assistant_verify_attached_context(
    assistant_context_descriptor_entry("psgc", "Q2_2026", "1001300000")
  )
  skip_if(is.null(v), "PSGC Q2 2026 1001300000 not present in this build")
  note <- assistant_render_attached_context(v)

  # The block SAYS the descriptive fields are absent...
  expect_true(grepl("does not currently load", note, fixed = TRUE))
  for (absent in ASSISTANT_CONTEXT_ABSENT_FIELDS) {
    expect_true(grepl(absent, note, fixed = TRUE), info = absent)
  }
  # ...and instructs the model to say so rather than supply them.
  expect_true(grepl("Do not supply any of them from general knowledge",
                    note, fixed = TRUE))
  expect_true(grepl("not available in this application", note, fixed = TRUE))
  expect_true(grepl("do not infer", note, fixed = TRUE))
})

test_that("a described record states the boundary against its own content", {
  # The other half of the same rule: where official text IS loaded, the
  # block must not claim it is missing, and must still forbid extending it.
  v <- assistant_verify_attached_context(
    assistant_context_descriptor_entry("psoc", "2022", "1112")
  )
  skip_if(is.null(v$descriptive), "PSOC 2022 1112 has no descriptive metadata")
  note <- assistant_render_attached_context(v)

  expect_false(grepl("does not currently load definitions", note, fixed = TRUE))
  expect_true(grepl("official published text for this exact code",
                    note, fixed = TRUE))
  expect_true(grepl("do not extend it", note, fixed = TRUE))
})

test_that("the boundary is generic, never prose about one code", {
  # UAT saw generalised prose about PSOC 1112. The fix must not be
  # hard-coded 1112 text: the boundary names no code, system or edition.
  boundary <- .assistant_context_boundary()
  for (specific in c("1112", "PSOC", "PSIC", "PSGC", "2022", "2026")) {
    expect_false(grepl(specific, boundary, fixed = TRUE), info = specific)
  }
  # No code appears in the CODE. It does appear in the comments, which
  # record which live UAT observation this boundary exists to answer --
  # that is provenance, not hard-coded prose.
  src <- .read_file("R", "assistant", "assistant_attached_context.R")
  expect_false(grepl("1112", .r_code_only_uat(src), fixed = TRUE))
})

test_that("hierarchy is carried because the repository returns it", {
  v <- assistant_verify_attached_context(
    assistant_context_descriptor_entry("psic", "2026", "84113")
  )
  skip_if(is.null(v), "PSIC 2026 84113 not present in this build")
  expect_true("hierarchy" %in% names(v))
  # Read through the SAME service the Search detail card uses, not a second
  # traversal.
  src <- .read_file("R", "assistant", "assistant_attached_context.R")
  expect_true(grepl("hierarchy_ancestors(", src, fixed = TRUE))
})


# ===========================================================================
# UAT-RM-03 — outsourced-janitor partial state
# ===========================================================================

test_that("an employment arrangement no longer erases the occupation", {
  # ROOT CAUSE. "outsourced" is establishment-side wording: it correctly
  # raises the PSIC wage-payer question, and it is in no PSOC title. The
  # occupation lookup was handed the whole phrase and failed, so the user
  # was told no occupation could be verified for an occupation the system
  # resolves one word shorter.
  bare <- assistant_coding_service(occupation = "janitor",
                                   requested_systems = "psoc")
  arranged <- assistant_coding_service(occupation = "outsourced janitor",
                                       requested_systems = "psoc")

  expect_identical(bare$occupation$status, "resolved")
  # NOT a new result: the same code the ordinary path already produces.
  expect_identical(arranged$occupation$selected_code,
                   bare$occupation$selected_code)
  expect_identical(arranged$occupation$selected_label,
                   bare$occupation$selected_label)
})

test_that("both dimensions keep their own state on one turn", {
  st <- assistant_new_turn_state()
  r <- assistant_handle_turn("outsourced janitor", st)

  # PSOC resolved AND PSIC still asking -- that is the partial state the
  # defect collapsed. One dimension's clarification must not erase the
  # other's answer.
  expect_identical(r$packet$occupation$status, "resolved")
  expect_false(is.na(r$packet$occupation$selected_code))
  expect_identical(r$packet$clarification$missing_slot, "wage_payer")
  expect_identical(r$status, "clarification_required")

  # And the occupation is actually shown to the user, not merely present.
  expect_true(grepl(r$packet$occupation$selected_code, r$render, fixed = TRUE))
})

test_that("the wage-payer answer still reaches 78200", {
  st <- assistant_new_turn_state()
  assistant_handle_turn(
    "I am a janitor deployed at a hospital through a manpower agency. What is my PSIC?", st)
  r <- assistant_handle_turn("the agency pays my wages", st)
  expect_identical(r$status, "resolved")
  expect_identical(as.character(r$packet$industry$selected_code), "78200")
})

test_that("the retry is a fallback and cannot change a resolved lookup", {
  # Any occupation that resolves today resolves identically: the narrower
  # retry only runs where the first attempt found nothing.
  expect_null(.assistant_occupation_without_arrangement("mayor"))
  expect_null(.assistant_occupation_without_arrangement("carpenter"))
  # "outsourced" on its own names no occupation and must keep asking.
  expect_null(.assistant_occupation_without_arrangement("outsourced"))
  expect_identical(.assistant_occupation_without_arrangement("outsourced janitor"),
                   "janitor")
  # "contractor" is a real occupational head and is NOT stripped.
  expect_null(.assistant_occupation_without_arrangement("labour contractor"))
})


# ===========================================================================
# UAT-UI-03 — Review coding pair
# ===========================================================================

test_that("the control is Review coding pair, and the old label is gone", {
  expect_identical(DUAL_SEARCH_REVIEW_LABEL, "Review coding pair")
  html <- .render(dual_search_ui())
  expect_false(grepl("Compare selected details", html, fixed = TRUE))

  # The ids did not move: the control was renamed, not replaced.
  expect_identical(DUAL_SEARCH_COMPARE_OUTPUT, "dual_search_compare")
  expect_identical(DUAL_SEARCH_COMPARE_INPUT, "dual_search_compare_open")
})

test_that("the coding pair reaches RM through the existing context path", {
  occ <- get_classification_entry("psoc", "2022", "1112")
  ind <- get_classification_entry("psic", "2026", "84113")
  skip_if(is.null(occ) || nrow(occ) == 0L, "PSOC 1112 absent")
  skip_if(is.null(ind) || nrow(ind) == 0L, "PSIC 84113 absent")

  d <- assistant_context_descriptor_coding_pair("2022", "1112", "2026", "84113")
  expect_identical(sort(names(d)),
                   sort(c("kind", "psoc_version", "psoc_code",
                          "psic_version", "psic_code")))

  v <- assistant_verify_attached_context(d)
  expect_identical(v$kind, "coding_pair")
  # Both halves authorised, and nothing else.
  p <- assistant_attached_context_packet(v)
  expect_setequal(assistant_allowed_codes(p), c("1112", "84113"))
  # Filed under their own systems: the packet is not where the PSOC/PSIC
  # distinction quietly disappears.
  expect_identical(p$occupation$selected_code, "1112")
  expect_identical(p$industry$selected_code, "84113")
})

test_that("the coding-pair review never claims the pair is correct", {
  v <- assistant_verify_attached_context(
    assistant_context_descriptor_coding_pair("2022", "1112", "2026", "84113")
  )
  skip_if(is.null(v), "coding pair not verifiable in this build")
  note <- assistant_render_attached_context(v)

  expect_true(grepl("neither code implies the other", note, fixed = TRUE))
  expect_true(grepl("Do NOT state that the pair is", note, fixed = TRUE))
  # It asks for the RIGHT things when more information is needed.
  expect_true(grepl("main duties", note, fixed = TRUE))
  expect_true(grepl("principal economic activity", note, fixed = TRUE))
})

test_that("PSOC/PSIC independence survives the rename", {
  html <- .render(dual_search_ui())
  expect_true(grepl("They never determine each other", html, fixed = TRUE))
  expect_true(grepl("never implies an equivalent PSIC code", html, fixed = TRUE))
})


# ===========================================================================
# UAT-UI-04 / UAT-UI-05 — Sources rhythm and restrained nav
# ===========================================================================

test_that("Sources cards stretch at the ROW and anchor their actions", {
  css <- .read_file("www", "ui-design.css")
  # The card already carried `margin-top: auto` on its link; it could never
  # fire, because `align-items: start` left the card no free space.
  expect_true(grepl(".psa-card-deck,\n  .psa-card-deck-2 { align-items: stretch; }",
                    css, fixed = TRUE))
  expect_true(grepl(".psa-source-card .psa-card-dl { flex: 1 1 auto; }",
                    css, fixed = TRUE))
  # No global fixed card height anywhere.
  expect_false(grepl(".psa-source-card { height: 3", css, fixed = TRUE))
  # Mobile keeps natural heights.
  expect_true(grepl(".psa-card-deck,\n  .psa-card-deck-2 { align-items: start; }",
                    css, fixed = TRUE))
  # A long LEVELS value wraps rather than widening or clipping the card.
  expect_true(grepl(".psa-source-card .psa-card-dl dd {", css, fixed = TRUE))
})

test_that("the active nav item is restrained and not colour-only", {
  # Owned by ui-glass.css, which governs the navbar chrome. A competing
  # block in the later sheet was measured losing to the four
  # `.navbar .nav-link` !important colour rules between them, so the rule
  # is fixed at its owner rather than out-cascaded.
  css <- .read_file("www", "ui-glass.css")
  # No filled white pill: the active surface is the quiet selected wash.
  expect_true(grepl("background: var(--ui-selected-bg) !important;",
                    css, fixed = TRUE))
  expect_false(grepl("background: var(--ui-primary-bg) !important;",
                     css, fixed = TRUE))

  # Two non-colour signals besides the surface: weight, and an indicator.
  expect_true(grepl("font-weight: var(--weight-semibold);", css, fixed = TRUE))
  expect_true(grepl(".navbar .nav-link.active::after,", css, fixed = TRUE))

  # Geometry is untouched, so the navbar cannot bulge as the destination
  # changes: no width, height or padding in the active rule.
  block <- regmatches(
    css,
    regexpr("\\.navbar \\.nav-link\\.active,\\n\\.navbar \\.nav-link:not\\(:empty\\)\\.active \\{[^}]*\\}", css)
  )
  expect_gt(length(block), 0L)
  for (geom in c("height:", "padding:", "width:", "margin:")) {
    expect_false(grepl(geom, block, fixed = TRUE), info = geom)
  }
})
