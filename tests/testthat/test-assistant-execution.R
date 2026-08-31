# RM-W1 (v10) -- deterministic server-side coding execution.
#
# These tests exercise `assistant_handle_turn()`, which is the SAME entry
# point app.R calls. That equivalence is the point: pre-staging-v9 passed
# every local test and still failed live because the tested surface
# (`assistant_coding_service()`) was not the surface the browser reached.
# The browser reached gpt-4o-mini, which chose the service's arguments.

# --- deterministic slot extraction ----------------------------------------

test_that("system tokens and coding verbs are stripped from the occupation", {
  s <- assistant_extract_slots("mayor psoc psic", c("psoc", "psic"))
  expect_identical(s$occupation, "mayor")

  s2 <- assistant_extract_slots("what is the psoc code of a vulcanizer", "psoc")
  expect_identical(s2$occupation, "vulcanizer")
})

test_that("an establishment preposition splits occupation from establishment", {
  s <- assistant_extract_slots("teacher in a private high school psoc psic",
                               c("psoc", "psic"))
  expect_identical(s$occupation, "teacher")
  expect_identical(s$establishment_activity, "private high school")

  s2 <- assistant_extract_slots("nurse at a private general hospital", c("psoc", "psic"))
  expect_identical(s2$occupation, "nurse")
  expect_identical(s2$establishment_activity, "private general hospital")
})

test_that("no establishment wording yields NO establishment slot -- never an invented one", {
  # The carpenter -> 08106 defect: the model fabricated an activity from
  # the occupation. Deterministic extraction must refuse to.
  s <- assistant_extract_slots("carpenter psoc psic", c("psoc", "psic"))
  expect_identical(s$occupation, "carpenter")
  expect_null(s$establishment_activity)

  s2 <- assistant_extract_slots("vulcanizer psoc", "psoc")
  expect_null(s2$establishment_activity)
})

test_that("outsourcing wording is preserved into the establishment slot", {
  # The janitor -> 86111 defect: the model passed "hospital" and silently
  # dropped "through a manpower agency", so the wage-payer precondition
  # never saw its own evidence.
  s <- assistant_extract_slots(
    "I am a janitor deployed at a hospital through a manpower agency. What is my PSIC?",
    "psic"
  )
  expect_identical(s$occupation, "janitor")
  expect_true(grepl("manpower agency", s$establishment_activity, fixed = TRUE))
  expect_true(assistant_activity_mentions_outsourcing(s$establishment_activity))
})

test_that("a government office supplies its own definitional establishment context", {
  s <- assistant_extract_slots("mayor psoc psic", c("psoc", "psic"))
  expect_true(s$government_context)
  expect_identical(s$establishment_activity, "public administration local government")

  # ...but never overrides an establishment the user actually stated.
  s2 <- assistant_extract_slots("mayor in a private consultancy", c("psoc", "psic"))
  expect_identical(s2$establishment_activity, "private consultancy")
  expect_false(s2$government_context)
})

test_that("a crop-naming farming occupation implies its own cultivation activity", {
  # spec 21: `palay farmer` must reach 0112, not ask what the farm does.
  # The occupation names the CROP, and a farm growing palay grows palay
  # whoever owns it -- so the establishment activity is already stated.
  s <- assistant_extract_slots("palay farmer psoc psic", c("psoc", "psic"))
  expect_identical(s$establishment_activity, "palay farming")

  s2 <- assistant_extract_slots("corn farmer psoc psic", c("psoc", "psic"))
  expect_identical(s2$establishment_activity, "corn farming")

  # A bare head names no crop and must still be probed.
  s3 <- assistant_extract_slots("farmer psoc psic", c("psoc", "psic"))
  expect_null(s3$establishment_activity)

  # ...and it never overrides an activity the user actually stated.
  s4 <- assistant_extract_slots("corn farmer in a rice mill", c("psoc", "psic"))
  expect_identical(s4$establishment_activity, "rice mill")
})

test_that("palay and corn resolve per spec 21 through the handler", {
  st <- assistant_new_turn_state()
  p <- assistant_handle_turn("palay farmer psoc psic", st)
  expect_identical(p$packet$occupation$selected_code, "6111")
  expect_identical(p$packet$industry$selected_code, "0112")
  expect_identical(p$packet$clarification$missing_slot, "establishment_activity_detail")
  expect_false(identical(p$packet$industry$selected_code, "10611"))

  up <- assistant_handle_turn("upland", st)
  expect_identical(up$packet$industry$selected_code, "01123")

  c1 <- assistant_handle_turn("corn farmer psoc psic", assistant_new_turn_state())
  expect_identical(c1$packet$occupation$selected_code, "6112")
  expect_identical(c1$packet$industry$selected_code, "01130")
})

test_that("statistician at PSA reaches the canonical ceiling, not a whole Division", {
  # spec 13: 8411 is the current canonical maximum for national context.
  # There is no national sub-class, and the answer must not degrade to the
  # Division 84 or the Section P.
  for (q in c("statistician at PSA psoc psic",
              "statistician in a national government agency psoc psic")) {
    res <- assistant_handle_turn(q, assistant_new_turn_state())
    expect_identical(res$packet$occupation$selected_code, "2122", info = q)
    expect_identical(res$packet$industry$selected_code, "8411", info = q)
    # National context supplied -- never a regional/local forced choice,
    # and never the outsourcing rule.
    expect_false(identical(res$packet$clarification$missing_slot, "wage_payer"), info = q)
    expect_false(identical(res$packet$industry$selected_code, "84112"), info = q)
    expect_false(identical(res$packet$industry$selected_code, "84113"), info = q)
  }
})

test_that("government-office context is definitional, not general occupation inference", {
  # A private-sector occupation must never acquire an establishment this
  # way -- that is the rule the project forbids.
  for (occ in c("carpenter", "nurse", "teacher", "janitor", "statistician",
                "call center agent", "truck driver")) {
    s <- assistant_extract_slots(occ, "psoc")
    expect_null(s$establishment_activity, info = occ)
    expect_false(s$government_context, info = occ)
  }
})

# --- the handler ------------------------------------------------------------

test_that("mayor resolves fully on the FIRST turn, with no establishment question", {
  st <- assistant_new_turn_state()
  res <- assistant_handle_turn("mayor psoc psic", st)

  expect_true(res$handled)
  expect_identical(res$route, "contextual_coding")
  expect_identical(res$status, "resolved")
  expect_identical(res$packet$occupation$selected_code, "1111")
  expect_identical(res$packet$industry$selected_code, "84113")
  expect_true(is.na(res$packet$clarification$missing_slot))
})

test_that("carpenter never receives an inferred industry", {
  st <- assistant_new_turn_state()
  res <- assistant_handle_turn("carpenter psoc psic", st)

  expect_identical(res$packet$occupation$selected_code, "7115")
  expect_identical(res$status, "clarification_required")
  expect_identical(res$packet$clarification$missing_slot, "establishment_activity")
  expect_length(res$packet$allowed_codes$psic, 0L)
  expect_false(grepl("08106", res$render, fixed = TRUE))
})

test_that("the outsourcing precondition cannot be reached around", {
  st <- assistant_new_turn_state()
  res <- assistant_handle_turn(
    "I am a janitor deployed at a hospital through a manpower agency. What is my PSIC?", st)

  expect_identical(res$packet$clarification$missing_slot, "wage_payer")
  expect_length(res$packet$allowed_codes$psic, 0L)
  expect_false(grepl("86111", res$render, fixed = TRUE))
})

test_that("a clarification reply continues the SAME request", {
  st <- assistant_new_turn_state()
  first <- assistant_handle_turn("carpenter psoc psic", st)
  expect_identical(first$status, "clarification_required")

  second <- assistant_handle_turn("residential construction", st)
  expect_identical(second$packet$occupation$selected_code, "7115")
  expect_identical(second$packet$industry$selected_code, "41001")
  expect_identical(second$status, "resolved")
})

test_that("a non-coding turn is NOT handled server-side and falls through to the model", {
  st <- assistant_new_turn_state()
  res <- assistant_handle_turn("hello, what can you do?", st)
  expect_false(res$handled)
  expect_true(is.na(res$render))
})

test_that("a handler failure fails closed with no authorised codes", {
  st <- assistant_new_turn_state()
  # NA text cannot route to a coding route; nothing may be authorised.
  res <- assistant_handle_turn(NA_character_, st)
  expect_false(res$handled)
  expect_length(res$allowed_codes, 0L)
})

# --- batch ------------------------------------------------------------------

test_that("the three-driver batch returns three independent results", {
  st <- assistant_new_turn_state()
  res <- assistant_handle_turn(
    "truck driver psoc\nheavy truck driver psoc\nbus driver psoc", st)

  expect_true(res$handled)
  expect_identical(res$route, "batch_contextual_coding")
  expect_length(res$packets, 3L)
  expect_identical(
    vapply(res$packets, function(p) p$occupation$selected_code %||% NA_character_, character(1)),
    c("8332", "8332", "8331")
  )
})

test_that("the six-item batch returns six independent results", {
  st <- assistant_new_turn_state()
  res <- assistant_handle_turn(paste(c(
    "grab taxi driver psoc", "food panda bicycle driver psoc", "vulcanizer psoc",
    "online seller psoc", "data scientist psoc", "esports player psoc"
  ), collapse = "\n"), st)

  expect_identical(
    vapply(res$packets, function(p) p$occupation$selected_code %||% NA_character_, character(1)),
    c("8325", "9335", "8141", "5247", "2124", "3424")
  )
  # One user batch -> ONE deterministic response (spec 35).
  expect_false(is.na(res$render))
  expect_true(nzchar(res$render))
  expect_null(assistant_turn_pending(st))
})

test_that("a batch leaves no state behind for the next turn", {
  st <- assistant_new_turn_state()
  assistant_handle_turn(paste(c(
    "grab taxi driver psoc", "food panda bicycle driver psoc", "vulcanizer psoc",
    "online seller psoc", "data scientist psoc", "esports player psoc"
  ), collapse = "\n"), st)

  a <- assistant_handle_turn("angkas driver psoc", st)
  expect_identical(a$packet$occupation$selected_code, "8323")
  expect_false(grepl("3424", a$render, fixed = TRUE))

  f <- assistant_handle_turn("food panda bicycle driver psoc", st)
  expect_identical(f$packet$occupation$selected_code, "9335")
})

# --- repeatability through the SAME surface app.R uses (spec 34) -----------

.exec_outcome <- function(text, follow_up = NULL) {
  st <- assistant_new_turn_state()
  res <- assistant_handle_turn(text, st)
  if (!is.null(follow_up)) res <- assistant_handle_turn(follow_up, st)
  list(
    route = res$route,
    status = res$status,
    psoc = res$packet$occupation$selected_code %||% NA_character_,
    psic = res$packet$industry$selected_code %||% NA_character_,
    missing = res$packet$clarification$missing_slot %||% NA_character_,
    allowed = sort(res$allowed_codes),
    codes = sort(vapply(res$packets,
                        function(p) p$occupation$selected_code %||% NA_character_,
                        character(1)))
  )
}

test_that("every critical case is identical across 10 fresh-state runs", {
  cases <- list(
    list(t = "mayor psoc psic"),
    list(t = "teacher in a private high school psoc psic"),
    list(t = "palay farmer psoc psic"),
    list(t = "corn farmer psoc psic", f = "growing of corn"),
    list(t = "carpenter psoc psic"),
    list(t = "I am a janitor deployed at a hospital through a manpower agency. What is my PSIC?"),
    list(t = "truck driver psoc\nheavy truck driver psoc\nbus driver psoc"),
    list(t = paste(c("grab taxi driver psoc", "food panda bicycle driver psoc",
                     "vulcanizer psoc", "online seller psoc",
                     "data scientist psoc", "esports player psoc"), collapse = "\n"))
  )
  for (case in cases) {
    runs <- lapply(seq_len(10L), function(i) .exec_outcome(case$t, case$f))
    for (i in seq_len(10L)) {
      expect_identical(runs[[i]], runs[[1L]],
                       info = sprintf("%s (run %d)", substr(case$t, 1, 40), i))
    }
  }
})
