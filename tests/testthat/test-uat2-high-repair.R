# UAT Pass 2 — the two HIGH defects this pass exists to close.
#
#   UAT2-UI-01  the PSGC Edition/release list overlapped itself
#   UAT2-RM-01  "Ask RM about this entry" opened, spent a provider call and
#               showed nothing
#
# Both are pinned here as behaviour, not as prose: the picker by the CSS
# facts that made the rows collapse, the assistant by running the real turn
# handler over the real starter strings.

.render2 <- function(tag) paste(as.character(htmltools::renderTags(tag)$html),
                                collapse = "")

# Strips R comments, so prose documenting a defect cannot satisfy -- or
# fail -- a structural assertion about the CODE.
.code_only2 <- function(src) {
  paste(sub("#.*$", "", strsplit(src, "\n", fixed = TRUE)[[1]]), collapse = "\n")
}

.repo2 <- normalizePath(file.path(getwd(), "..", ".."), mustWork = TRUE)

.read2 <- function(...) {
  path <- file.path(.repo2, ...)
  expect_true(file.exists(path), info = paste("missing file:", path))
  paste(readLines(path, warn = FALSE), collapse = "\n")
}

# The stylesheet the picker's own layout lives in, with comments removed so
# the block explaining the defect cannot be mistaken for a rule.
.picker_css <- function() {
  css <- .read2("www", "ui-design.css")
  # (?s) so `.` crosses newlines -- CSS comments here are block comments
  # several lines long, and without it the prose explaining a defect stays
  # in the string and can satisfy an assertion about the rules.
  gsub("(?s)/\\*.*?\\*/", "", css, perl = TRUE)
}


# ===========================================================================
# UAT2-UI-01 — the Edition list is normal flow, and cannot collapse
# ===========================================================================

test_that("the release list is a block container, not a shrinkable flex column", {
  # MEASURED ROOT CAUSE (1440px, PSGC, 13 releases): the list was a column
  # flex container with `max-height: 268px` and a `scrollHeight` of 356px,
  # so every `.radio` was a flex item with the default `flex-shrink: 1`.
  # Bootstrap's own `.shiny-input-container .radio { min-height: 1.5rem }`
  # replaced the automatic content-based minimum, so the algorithm was free
  # to compress all thirteen rows to that 24px floor while each row's
  # 40-70px label kept its size and painted over the rows beneath it.
  #
  # In block flow the row's box IS its content's height and the shrink
  # algorithm never runs, which is why this is the assertion and not a
  # row height or a z-index.
  css <- .picker_css()
  expect_match(
    css,
    ".psa-edition-group .shiny-options-group {\n  display: block;\n}",
    fixed = TRUE
  )
})

test_that("row spacing survives the move out of flex layout", {
  # `gap` is a flex/grid property and silently does nothing in block flow,
  # so the 2px rhythm has to be restated. Without this the rows would touch.
  css <- .picker_css()
  expect_match(
    css,
    ".psa-edition-group .shiny-options-group > .radio + .radio {\n  margin-top: 2px;\n}",
    fixed = TRUE
  )
})

test_that("no stylesheet may describe a release row as shorter than its label", {
  # The Bootstrap floor is cleared rather than left to be harmless: it is
  # the exact property that let the row box become smaller than the label
  # inside it.
  css <- .picker_css()
  expect_match(
    css,
    ".psa-edition-group .shiny-options-group > .radio {\n  min-height: 0;",
    fixed = TRUE
  )
  # And the fix is structural. A z-index on the rows would have hidden the
  # symptom while leaving every row 24px tall and still un-clickable.
  rows_block <- regmatches(
    css,
    regexpr("\\.psa-edition-group \\.shiny-options-group[^}]*\\}", css, perl = TRUE)
  )
  expect_false(grepl("z-index", rows_block, fixed = TRUE))
})

test_that("the row label still carries a real target size", {
  # The row is content-sized now, so the LABEL is what has to be big enough
  # to hit: 40px in the rail, 44px at phone width.
  app_css <- .read2("www", "app.css")
  filters_css <- .read2("www", "ui-filters.css")
  expect_true(grepl("min-height: 38px", app_css, fixed = TRUE) ||
                grepl("min-height: 40px", app_css, fixed = TRUE))
  expect_true(grepl("min-height: 40px", filters_css, fixed = TRUE))
  expect_true(grepl(".psa-edition-group .radio label { min-height: 44px; }",
                    filters_css, fixed = TRUE))
})

test_that("the group heading is its own full-width block inside its row", {
  # `edition_choice_spec()` has to put the heading inside the option: the
  # input contract keeps `classification_version` a radioButtons group, and
  # `updateRadioButtons()` has no way to emit anything BETWEEN options. The
  # heading therefore earns its own line by being a full-width block in a
  # wrapping row rather than by being a sibling element.
  css <- .picker_css()
  head_block <- regmatches(
    css, regexpr("\\.psa-edition-group-head \\{[^}]*\\}", css, perl = TRUE)
  )
  expect_gt(length(head_block), 0L)
  expect_true(grepl("display: block", head_block, fixed = TRUE))
  expect_true(grepl("width: 100%", head_block, fixed = TRUE))
  # Never absolutely positioned: that is what would let it sit on top of
  # the row rather than above it.
  expect_false(grepl("position: absolute", head_block, fixed = TRUE))

  row_block <- regmatches(
    css, regexpr("\\.psa-edition-row \\{[^}]*\\}", css, perl = TRUE)
  )
  expect_true(grepl("flex-wrap: wrap", row_block, fixed = TRUE))
  expect_false(grepl("position: absolute", row_block, fixed = TRUE))
})

test_that("current release first, archived order untouched", {
  # The layout repair must not have moved a single release. This is the
  # same contract test-ui-release-order-and-focus.R pins, re-asserted here
  # because the fix touched the list the reader actually sees.
  versions <- classification_versions("psgc")
  current <- classification_registry()
  current <- current$current_version[current$id == "psgc"][[1]]
  spec <- edition_choice_spec(versions, current)

  expect_identical(spec$choiceValues[[1]], current)
  expect_setequal(unlist(spec$choiceValues), versions)
  expect_identical(spec$selected, current)

  archived <- setdiff(unlist(spec$choiceValues), current)
  expect_identical(archived, setdiff(release_newest_first(versions, current), current))
})

test_that("the internal scroll and the sheet treatment are both kept", {
  # A 13-release history must still scroll inside the panel rather than
  # growing it, and the phone sheet must still be a docked sheet.
  css <- .picker_css()
  expect_true(grepl("overflow-y: auto", .read2("www", "ui-filters.css"), fixed = TRUE) ||
                grepl("overflow-y: auto", .read2("www", "app.css"), fixed = TRUE))
  expect_true(grepl("max-height: 268px", .read2("www", "ui-filters.css"), fixed = TRUE))
  expect_true(grepl("inset: auto 0 0 0", css, fixed = TRUE))
})


# ===========================================================================
# UAT2-RM-01 — opening RM costs nothing
# ===========================================================================

test_that("no contextual launcher submits a turn", {
  src <- .read2("R", "ui", "ui_sidecar.R")
  code <- .code_only2(src)

  # THE DEFECT. Each launcher used to end in `ask(RM_INTENT_*)`, which
  # submitted "Explain this classification entry." the moment the panel
  # opened. Nothing may do that any more.
  expect_false(grepl("ask(RM_INTENT_", code, fixed = TRUE))

  # The launchers attach, then present. `present()` opens the panel and
  # nothing else -- in particular it never touches the composer.
  present_body <- regmatches(
    code, regexpr("present <- function\\(\\)[^}]*\\}", code, perl = TRUE)
  )
  expect_gt(length(present_body), 0L)
  expect_true(grepl("rm_sidecar_open(session)", present_body, fixed = TRUE))
  expect_false(grepl("update_chat_user_input", present_body, fixed = TRUE))
})

test_that("the only composer submission left is the starter's", {
  code <- .code_only2(.read2("R", "ui", "ui_sidecar.R"))
  # ONE call site. Two would be two ways for a prompt to reach the model.
  expect_equal(
    length(gregexpr("update_chat_user_input", code, fixed = TRUE)[[1]]), 1L
  )
  # And it is still the ordinary composer on the namespaced chat element,
  # so a starter prompt arrives on exactly the same input as typed text.
  expect_true(grepl("RM_CHAT_ELEMENT_ID, value = prompt", code, fixed = TRUE))
  expect_true(grepl("submit = TRUE", code, fixed = TRUE))
  # Only the four starter observers may call ask().
  expect_equal(length(gregexpr("ask(actions[[i]])", code, fixed = TRUE)[[1]]), 1L)
})

test_that("the sidecar never appends to the transcript or runs a turn itself", {
  code <- .code_only2(.read2("R", "ui", "ui_sidecar.R"))
  # A synthesised exchange written straight into the chat would be a second
  # assistant path; so would calling the turn handler from the UI layer.
  expect_false(grepl("chat_append", code, fixed = TRUE))
  expect_false(grepl("assistant_handle_turn", code, fixed = TRUE))
  expect_false(grepl("chat_mod_server", code, fixed = TRUE))
})

test_that("the starter renders from the attached descriptor", {
  items <- list(
    `entry:psoc:2022:1112` = list(
      label = "1112 · SENIOR GOVERNMENT OFFICIALS · PSOC 2022",
      descriptor = assistant_context_descriptor_entry("psoc", "2022", "1112")
    )
  )
  html <- .render2(rm_context_starter_ui(items))

  # It names the record the chip names, and says so plainly.
  expect_true(grepl("1112 · SENIOR GOVERNMENT OFFICIALS · PSOC 2022", html, fixed = TRUE))
  expect_true(grepl("is attached.", html, fixed = TRUE))
  expect_true(grepl("What would you like help with?", html, fixed = TRUE))

  # Four real controls on the four stable ids.
  for (id in RM_STARTER_INPUTS) {
    expect_true(grepl(paste0('id="', id, '"'), html, fixed = TRUE), info = id)
  }
  # Accessible: a group with a name, and a name on every action.
  expect_true(grepl('aria-label="Suggested questions about the attached record"',
                    html, fixed = TRUE))
  expect_true(grepl('aria-label="Ask RM: Why might an occupation fit here?"',
                    html, fixed = TRUE))
})

test_that("nothing attached means no starter", {
  expect_null(rm_context_starter_ui(NULL))
  expect_null(rm_context_starter_ui(list()))
})

test_that("the starter follows the newest attachment", {
  items <- list(
    a = list(label = "first",
             descriptor = assistant_context_descriptor_entry("psoc", "2022", "1112")),
    b = list(label = "second",
             descriptor = assistant_context_descriptor_entry("psic", "2026", "8411"))
  )
  html <- .render2(rm_context_starter_ui(items))
  expect_true(grepl("second", html, fixed = TRUE))
  # PSIC wording, because the newest attachment is a PSIC record.
  expect_true(grepl("Why might an establishment fit here?", html, fixed = TRUE))
  expect_false(grepl("Why might an occupation fit here?", html, fixed = TRUE))
})

test_that("the starter is built from the descriptor, not from a hard-coded code", {
  # Three different systems, three different wordings, no code anywhere in
  # the action text.
  psoc <- rm_context_starter_actions(assistant_context_descriptor_entry("psoc", "2022", "1112"))
  psic <- rm_context_starter_actions(assistant_context_descriptor_entry("psic", "2026", "8411"))
  psgc <- rm_context_starter_actions(assistant_context_descriptor_entry("psgc", "Q2_2026", "1001300000"))

  expect_false(identical(psoc, psic))
  expect_false(identical(psoc, psgc))
  for (set in list(psoc, psic, psgc)) {
    expect_length(set, 4L)
    expect_false(any(grepl("[0-9]{3,}", set)))
  }
  # A geographic or product record is never asked about "an occupation".
  expect_false(any(grepl("occupation", psgc, fixed = TRUE)))
  expect_false(any(grepl("establishment", psgc, fixed = TRUE)))
})

test_that("every starter prompt routes as a question ABOUT the record", {
  # THE FAILURE THIS PREVENTS. A starter is submitted verbatim, so its
  # WORDING picks its route. "Review with a PSIC code" -- the mock's own
  # shorthand -- is measured as `handled = TRUE`: RM would classify the
  # button's own sentence and answer a question nobody asked. Every action
  # actually shipped is run through the real handler here.
  descriptors <- list(
    assistant_context_descriptor_entry("psoc", "2022", "1112"),
    assistant_context_descriptor_entry("psic", "2026", "8411"),
    assistant_context_descriptor_entry("psgc", "Q2_2026", "1001300000"),
    assistant_context_descriptor_correspondence("2019", "0111", "2026", "0111"),
    assistant_context_descriptor_coding_pair("2022", "1112", "2026", "8411")
  )
  for (d in descriptors) {
    for (prompt in rm_context_starter_actions(d)) {
      state <- assistant_new_turn_state()
      assistant_turn_set_attached_context(state, list(d))
      res <- assistant_handle_turn(prompt, state)
      expect_false(isTRUE(res$handled),
                   info = paste(d$kind, "|", prompt))
    }
  }
})

test_that("the automatic entry intent is still a referential turn", {
  # It survives as the first action of the non-occupational starter, so the
  # detector contract Pass 1 established still has to hold.
  for (intent in c(RM_INTENT_ENTRY, RM_INTENT_CORRESPONDENCE,
                   RM_INTENT_CODING_PAIR)) {
    expect_true(assistant_explanation_requested(intent), info = intent)
  }
})

test_that("a rejected reply is said out loud, never appended as silence", {
  # THE ORPHANED TURN, reproduced without a provider.
  #
  # On the contextual_coding route assistant_render.R suppresses every
  # streamed chunk, so app.R's end-of-turn append is the ONLY thing the
  # reader sees. `assistant_guard_response()` falls back to
  # `assistant_render_coding_result(packet)`, and for an attached-context
  # packet that rendering is the EMPTY STRING -- so a reply naming any code
  # outside allowed_codes used to append nothing at all.
  state <- assistant_new_turn_state()
  descriptor <- assistant_context_descriptor_entry("psoc", "2022", "1112")
  assistant_turn_set_attached_context(state, list(descriptor))
  res <- assistant_handle_turn(RM_INTENT_ENTRY, state)
  skip_if(isTRUE(res$handled), "PSOC 2022 1112 not present in this build")

  packet <- assistant_turn_latest_packet(state)
  guarded <- assistant_guard_response(
    "The code 1112 belongs to sub-major group 111.", packet
  )
  expect_true(guarded$used_fallback)
  expect_false(nzchar(trimws(guarded$text %||% "")))

  # app.R must substitute the spoken refusal for that empty string.
  app <- .code_only2(.read2("app.R"))
  expect_true(grepl("shown <- ASSISTANT_UNVERIFIED_REPLY_TEXT", app, fixed = TRUE))
  expect_true(grepl("rm_chat$append(shown, role = \"assistant\")", app, fixed = TRUE))
  expect_false(grepl("rm_chat$append(guarded$text", app, fixed = TRUE))

  # And the sentence itself says what CLAUDE.md requires it to say, with no
  # code, no provider detail and no technical vocabulary.
  expect_true(grepl("could not verify", ASSISTANT_UNVERIFIED_REPLY_TEXT, fixed = TRUE))
  expect_false(grepl("[0-9]", ASSISTANT_UNVERIFIED_REPLY_TEXT))
})

test_that("the guard itself is unchanged: an authorised code still passes", {
  # The repair adds a sentence for the empty case. It must not have
  # loosened what may reach the DOM.
  state <- assistant_new_turn_state()
  descriptor <- assistant_context_descriptor_entry("psoc", "2022", "1112")
  assistant_turn_set_attached_context(state, list(descriptor))
  res <- assistant_handle_turn(RM_INTENT_ENTRY, state)
  skip_if(isTRUE(res$handled), "PSOC 2022 1112 not present in this build")
  packet <- assistant_turn_latest_packet(state)

  ok <- assistant_guard_response("PSOC 1112 is the attached entry.", packet)
  expect_false(ok$used_fallback)
  expect_true(nzchar(ok$text))
})

test_that("the starter block is mounted with the chips, not in the transcript", {
  src <- .read2("R", "ui", "ui_sidecar.R")
  expect_true(grepl("shiny::uiOutput(RM_STARTER_OUTPUT)", src, fixed = TRUE))
  # Same reactive source as the chips, so removing the last chip removes
  # the starter and New chat clears both.
  expect_true(grepl("rm_context_starter_ui(attached())", src, fixed = TRUE))
  expect_identical(RM_STARTER_OUTPUT, "rm_context_starter")
  expect_length(RM_STARTER_INPUTS, 4L)
})

test_that("semantic authority stays off", {
  # Nothing in this pass may have turned semantic retrieval into an
  # authority for a code.
  expect_false(retrieval_semantic_is_authoritative(retrieval_semantic_mode()))
})
