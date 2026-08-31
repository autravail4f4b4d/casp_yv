# W5 -- the clarification lifecycle, driven through the SAME server entry
# point app.R uses (`assistant_handle_turn()`), so what is asserted here is
# what runs live. Every case in this file was a reproduced live-browser
# failure of pre-staging-v10; each one is reproduced against the real
# handler first (see the root-cause block in R/assistant/assistant_clarification.R)
# and then pinned.

psoc_of <- function(res) {
  c <- res$packet$occupation$selected_code
  if (is.null(c)) NA_character_ else as.character(c)
}

psic_of <- function(res) {
  c <- res$packet$industry$selected_code
  if (is.null(c)) NA_character_ else as.character(c)
}

missing_of <- function(res) {
  s <- res$packet$clarification$missing_slot
  if (is.null(s)) NA_character_ else as.character(s)
}

run_turns <- function(...) {
  st <- assistant_new_turn_state()
  msgs <- c(...)
  out <- vector("list", length(msgs))
  for (i in seq_along(msgs)) out[[i]] <- assistant_handle_turn(msgs[[i]], st)
  list(state = st, turns = out, last = out[[length(out)]])
}

TEACHER <- "teacher in a private high school psoc psic"

# ---------------------------------------------------------------------------
# Named regression matrix (spec 26)
# ---------------------------------------------------------------------------

test_that("mayor resolves to one authoritative answer with no clarification", {
  r <- run_turns("mayor psoc psic")
  expect_true(r$last$handled)
  expect_identical(r$last$status, "resolved")
  expect_identical(psoc_of(r$last), "1111")
  expect_identical(psic_of(r$last), "84113")
  expect_true(is.na(missing_of(r$last)))
  expect_null(assistant_turn_pending(r$state))
  expect_length(r$last$packets, 1L)
})

test_that("the outsourced janitor asks exactly one wage-payer question, then resolves", {
  r <- run_turns(
    "I am a janitor deployed at a hospital through a manpower agency. What is my PSIC?",
    "the manpower agency pays me"
  )
  first <- r$turns[[1L]]
  expect_identical(first$status, "clarification_required")
  expect_identical(missing_of(first), "wage_payer")
  expect_true(is.na(psic_of(first)))
  # One question, not two: the rendered clarification appears once.
  expect_length(gregexpr(first$packet$clarification$question, first$render,
                         fixed = TRUE)[[1L]], 1L)

  expect_identical(r$last$status, "resolved")
  expect_identical(psic_of(r$last), "78200")
  expect_null(assistant_turn_pending(r$state))
})

test_that("carpenter leaves PSIC unresolved and 'residential' cannot authorise 87100", {
  r <- run_turns("carpenter psoc psic", "residential")
  first <- r$turns[[1L]]
  expect_identical(psoc_of(first), "7115")
  expect_identical(first$status, "clarification_required")

  # The blocker: a bare qualifier must not reach unrestricted PSIC
  # retrieval, which returned 87100 Residential nursing care activities.
  expect_identical(r$last$status, "clarification_required")
  expect_true(is.na(psic_of(r$last)))
  expect_false(identical(psic_of(r$last), "87100"))
  expect_false(grepl("87100", r$last$render, fixed = TRUE))
  # PSOC already established is preserved across the refusal.
  expect_identical(psoc_of(r$last), "7115")
  # And the question narrows rather than repeating verbatim.
  expect_false(identical(first$packet$clarification$question,
                         r$last$packet$clarification$question))
  expect_false(is.null(assistant_turn_pending(r$state)))
})

test_that("carpenter + a real activity still resolves (the narrowing is not a wall)", {
  r <- run_turns("carpenter psoc psic", "residential construction")
  expect_identical(r$last$status, "resolved")
  expect_identical(psoc_of(r$last), "7115")
  expect_false(is.na(psic_of(r$last)))
})

test_that("teacher: the first turn offers a bounded, code-carrying option set", {
  r <- run_turns(TEACHER)
  expect_identical(psoc_of(r$last), "2330")
  expect_identical(psic_of(r$last), "8531")
  expect_identical(missing_of(r$last), "establishment_activity_detail")

  pending <- assistant_turn_pending(r$state)
  expect_false(is.null(pending))
  expect_gte(length(pending$options), 2L)
  for (o in pending$options) {
    expect_true(nzchar(o$code))
    expect_true(nzchar(o$label))
  }
  expect_identical(pending$system, "psic")
  expect_identical(pending$parent_code, "8531")
})

test_that("teacher -> 'latter' selects the second option and never searches globally", {
  r <- run_turns(TEACHER, "latter")
  expect_identical(r$last$status, "resolved")
  expect_identical(psoc_of(r$last), "2330")
  expect_identical(psic_of(r$last), "85314")
  # The live failure: "latter" retrieved 20224 Manufacture of prepared
  # pigments as an establishment activity.
  expect_false(identical(psic_of(r$last), "20224"))
  expect_false(grepl("20224", r$last$render, fixed = TRUE))
  # Answered questions leave no pending state (spec 16).
  expect_null(assistant_turn_pending(r$state))
})

test_that("teacher -> 'former' and numeric/ordinal forms select the same options", {
  expect_identical(psic_of(run_turns(TEACHER, "former")$last), "85312")
  expect_identical(psic_of(run_turns(TEACHER, "1")$last), "85312")
  expect_identical(psic_of(run_turns(TEACHER, "2")$last), "85314")
  expect_identical(psic_of(run_turns(TEACHER, "option 2")$last), "85314")
  expect_identical(psic_of(run_turns(TEACHER, "the second one")$last), "85314")
  expect_identical(psic_of(run_turns(TEACHER, "the first")$last), "85312")
})

test_that("teacher -> full option label completes the PSIC and preserves the PSOC", {
  r <- run_turns(
    TEACHER,
    "Private general secondary education for children with special needs"
  )
  expect_identical(r$last$status, "resolved")
  expect_identical(psoc_of(r$last), "2330")
  expect_identical(psic_of(r$last), "85314")
  expect_null(assistant_turn_pending(r$state))
})

test_that("a reply the bounded set cannot interpret re-asks instead of searching", {
  r <- run_turns(TEACHER, "special needs")
  expect_identical(r$last$status, "clarification_required")
  expect_identical(psoc_of(r$last), "2330")
  expect_identical(psic_of(r$last), "8531")
  pending <- assistant_turn_pending(r$state)
  expect_false(is.null(pending))
  expect_gte(length(pending$options), 2L)
})

test_that("an explicit new coding request supersedes a stale teacher clarification", {
  r <- run_turns(TEACHER, "statistician at PSA psoc psic")
  expect_identical(r$last$status, "resolved")
  expect_identical(psoc_of(r$last), "2122")
  expect_identical(psic_of(r$last), "8411")
  # The live failure: PSOC came back as the teacher's 2330 (or nothing at
  # all) and PSIC as 74994, because the sentence was applied to the
  # outstanding teacher slot.
  expect_false(identical(psic_of(r$last), "74994"))
  expect_null(assistant_turn_pending(r$state))
})

test_that("supersession also works after a RESOLVED teacher turn", {
  r <- run_turns(TEACHER, "latter", "statistician at PSA psoc psic")
  expect_identical(psoc_of(r$last), "2122")
  expect_identical(psic_of(r$last), "8411")
})

# ---------------------------------------------------------------------------
# Non-regression matrix (spec 27)
# ---------------------------------------------------------------------------

test_that("palay / upland and corn are unchanged by bounded resolution", {
  p <- run_turns("palay farmer", "upland")
  expect_identical(psoc_of(p$turns[[1L]]), "6111")
  expect_identical(psic_of(p$turns[[1L]]), "0112")
  expect_identical(p$turns[[1L]]$status, "clarification_required")
  expect_identical(psic_of(p$last), "01123")
  expect_null(assistant_turn_pending(p$state))

  cn <- run_turns("corn farmer psoc psic")
  expect_identical(psoc_of(cn$last), "6112")
  expect_identical(psic_of(cn$last), "01130")
})

test_that("AI prompt engineer still reports no verified current code", {
  r <- run_turns("AI prompt engineer psoc")
  expect_identical(r$last$status, "no_verified_match")
  expect_true(is.na(psoc_of(r$last)))
})

# ---------------------------------------------------------------------------
# Pending-state cleanup and session isolation (spec 16/29)
# ---------------------------------------------------------------------------

test_that("a new chat clears pending clarification and the render carrier", {
  st <- assistant_new_turn_state()
  assistant_handle_turn(TEACHER, st)
  expect_false(is.null(assistant_turn_pending(st)))
  assistant_turn_clear(st)
  expect_null(assistant_turn_pending(st))
  expect_false(assistant_turn_render_emitted(st))
})

test_that("two sessions never observe each other's pending options", {
  a <- assistant_new_turn_state()
  b <- assistant_new_turn_state()

  assistant_handle_turn(TEACHER, a)
  res_b <- assistant_handle_turn("statistician at PSA psoc psic", b)

  expect_identical(psoc_of(res_b), "2122")
  expect_identical(psic_of(res_b), "8411")
  expect_null(assistant_turn_pending(b))
  expect_false(is.null(assistant_turn_pending(a)))

  # Session A's own continuation is unaffected by B's traffic.
  res_a <- assistant_handle_turn("latter", a)
  expect_identical(psic_of(res_a), "85314")
})

# ---------------------------------------------------------------------------
# Repeatability (spec 28)
# ---------------------------------------------------------------------------

test_that("20 fresh-state repetitions produce identical routes, codes and state", {
  fingerprint <- function(msgs) {
    r <- run_turns(msgs)
    pending <- assistant_turn_pending(r$state)
    paste(
      r$last$route, r$last$status, psoc_of(r$last), psic_of(r$last),
      missing_of(r$last),
      paste(r$last$allowed_codes, collapse = "+"),
      if (is.null(pending)) "no-pending" else paste0(
        pending$missing_slot, "/",
        paste(vapply(pending$options, function(o) o$code, character(1)),
              collapse = ",")
      ),
      sep = "|"
    )
  }

  scenarios <- list(
    mayor = "mayor psoc psic",
    outsourcing = "I am a janitor deployed at a hospital through a manpower agency. What is my PSIC?",
    teacher_latter = c(TEACHER, "latter"),
    teacher_label = c(TEACHER, "Private general secondary education for children with special needs"),
    carpenter_residential = c("carpenter psoc psic", "residential"),
    statistician_after_teacher = c(TEACHER, "statistician at PSA psoc psic")
  )

  for (nm in names(scenarios)) {
    prints <- vapply(seq_len(20L), function(i) fingerprint(scenarios[[nm]]),
                     character(1))
    expect_length(unique(prints), 1L)
    expect_true(nzchar(prints[[1L]]), info = nm)
  }
})

# ---------------------------------------------------------------------------
# Deterministic-only rendering and explanation policy (spec 20/21/23)
# ---------------------------------------------------------------------------

test_that("a resolved coding turn carries its render and never a clarification", {
  r <- run_turns("mayor psoc psic")
  expect_true(nzchar(r$last$render))
  expect_false(grepl("\\?", r$last$render))
  # The stream, not a second appended message, carries the answer.
  expect_identical(assistant_turn_take_render(r$state), r$last$render)
  expect_true(assistant_turn_render_emitted(r$state))
  expect_null(assistant_turn_take_render(r$state))
})

test_that("a clarification turn renders its question exactly once", {
  r <- run_turns("carpenter psoc psic")
  q <- r$last$packet$clarification$question
  hits <- gregexpr(q, r$last$render, fixed = TRUE)[[1L]]
  expect_length(hits, 1L)
  expect_true(hits[[1L]] > 0L)
})

test_that("an explanation request does not re-code and does not consume the pending slot", {
  st <- assistant_new_turn_state()
  assistant_handle_turn(TEACHER, st)
  before <- assistant_turn_pending(st)

  res <- assistant_handle_turn("why?", st)
  expect_false(isTRUE(res$handled))
  expect_true(isTRUE(res$explanation_requested))
  expect_identical(res$route, "contextual_coding")

  after <- assistant_turn_pending(st)
  expect_false(is.null(after))
  expect_identical(after$missing_slot, before$missing_slot)
  expect_identical(
    vapply(after$options, function(o) o$code, character(1)),
    vapply(before$options, function(o) o$code, character(1))
  )
  # The packet the guard validates against is unchanged.
  expect_identical(assistant_turn_latest_packet(st)$industry$selected_code, "8531")
})

test_that("an explanation request with no prior packet is coded normally", {
  st <- assistant_new_turn_state()
  res <- assistant_handle_turn("why?", st)
  expect_false(isTRUE(res$explanation_requested))
})

# ---------------------------------------------------------------------------
# Transcript hygiene (spec 24/25)
# ---------------------------------------------------------------------------

test_that("no deterministic rendering contains internal or markup artefacts", {
  renders <- c(
    run_turns("mayor psoc psic")$last$render,
    run_turns("carpenter psoc psic")$last$render,
    run_turns("carpenter psoc psic", "residential")$last$render,
    run_turns(TEACHER)$last$render,
    run_turns(TEACHER, "latter")$last$render,
    run_turns("palay farmer")$last$render,
    run_turns("AI prompt engineer psoc")$last$render,
    run_turns(
      "I am a janitor deployed at a hospital through a manpower agency. What is my PSIC?"
    )$last$render
  )
  for (txt in renders) {
    expect_identical(assistant_transcript_artifacts(txt), character(0), info = txt)
    for (bad in c("svg", "<svg", "shinychat-raw-html", "shiny-tool-request",
                  "assistant_", "tool request", "tool result")) {
      expect_false(grepl(bad, tolower(txt), fixed = TRUE), info = bad)
    }
  }
})

test_that("the output guard rejects prose carrying internal artefacts", {
  packet <- assistant_coding_service("mayor", "local government")
  clean <- "The occupation is a local chief executive."
  expect_false(assistant_guard_response(clean, packet)$used_fallback)

  for (bad in c(
    "Here is the answer <svg width=\"10\"></svg>",
    "svg",
    "<shinychat-raw-html></shinychat-raw-html>",
    "I called assistant_search_classification(system = \"psoc\")",
    "tool result: {\"code\": \"1111\"}"
  )) {
    g <- assistant_guard_response(bad, packet)
    expect_true(g$used_fallback, info = bad)
    expect_identical(g$text, assistant_render_coding_result(packet), info = bad)
  }
})

test_that("grounding replaces the model's discarded turn instead of appending one", {
  skip_if_not_installed("ellmer")
  turns <- list(
    ellmer::Turn("user", "mayor psoc psic"),
    ellmer::Turn("assistant", "Ano ang mga tungkulin ng mayor?")
  )
  grounded <- assistant_ground_turns(turns, "**Occupation classification - PSOC**")
  expect_length(grounded, 2L)
  expect_identical(as.character(grounded[[2L]]@role), "assistant")
  expect_true(grepl("Occupation classification",
                    ellmer::contents_text(grounded[[2L]]), fixed = TRUE))

  # Nothing to replace, nothing to add.
  expect_length(assistant_ground_turns(list(), "text"), 0L)
  user_only <- list(ellmer::Turn("user", "hi"))
  expect_identical(assistant_ground_turns(user_only, "text"), user_only)
  expect_identical(assistant_ground_turns(turns, NULL), turns)
})
