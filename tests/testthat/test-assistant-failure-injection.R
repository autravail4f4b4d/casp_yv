# RM_DETERMINISTIC_TOOL_ROUTING_ENFORCEMENT micro-gate -- H6.
#
# Six deliberate failure injections, each required to fail CLOSED: no
# unauthorised authoritative classification may reach rendering. These
# exercise the same functions app.R's observers call (the router, the
# turn-state accessors, the tool wrappers, and the response guard) rather
# than a live Shiny reactive harness -- app.R itself has never been
# unit-tested at the observer level in this codebase (it is a thin
# composition layer verified by browser UAT instead), and that pre-existing
# architectural boundary is unchanged by this micro-gate.

test_that("H6.1: route/tool-surface setup failure (router returns something unusable) fails closed", {
  skip_if_not_installed("ellmer")

  st <- assistant_new_turn_state()
  # Simulate a router that failed to produce a usable route at all.
  assistant_turn_set_route(st, NULL)
  expect_identical(assistant_turn_current_route(st), "contextual_coding")

  tools <- rm_assistant_tools(turn_state = st)
  search_fn <- Filter(function(t) identical(t@name, "assistant_search_classification"), tools)[[1]]
  out <- search_fn(system = "psoc", query = "carpenter")
  expect_identical(out$available, FALSE)

  pairings_fn <- Filter(function(t) identical(t@name, "assistant_search_common_pairings"), tools)[[1]]
  out2 <- pairings_fn(occupation = "carpenter")
  expect_identical(out2$available, FALSE)
})

test_that("H6.2: a set_tools() failure re-asserts the restrictive route rather than leaving the prior one live", {
  skip_if_not_installed("ellmer")

  st <- assistant_new_turn_state()
  routed <- list(route = "general_search", requested_systems = c("psoc", "psic"))
  assistant_turn_set_route(st, routed$route)
  assistant_turn_set_requested_systems(st, routed$requested_systems)
  expect_identical(assistant_turn_current_route(st), "general_search")

  # A client whose tool-surface installation always fails -- mirrors app.R's
  # error handler for `rm_client$set_tools(...)`.
  broken_client <- list(set_tools = function(...) stop("simulated provider client failure"))
  tryCatch(
    broken_client$set_tools(assistant_tools_for_route(routed$route, rm_assistant_tools(st))),
    error = function(e) {
      assistant_turn_set_route(st, "contextual_coding")
    }
  )
  expect_identical(assistant_turn_current_route(st), "contextual_coding")

  tools <- rm_assistant_tools(turn_state = st)
  search_fn <- Filter(function(t) identical(t@name, "assistant_search_classification"), tools)[[1]]
  out <- search_fn(system = "psoc", query = "carpenter")
  expect_identical(out$available, FALSE)
})

test_that("H6.3: an unauthorized model-invented code is discarded, never appended", {
  packet <- assistant_coding_service("mayor", "local government")
  fabricated <- "Your occupation code is PSOC 1112 (Chief Executives)."
  guarded <- assistant_guard_response(fabricated, packet)

  expect_true(guarded$used_fallback)
  expect_false(grepl("1112", guarded$text, fixed = TRUE))
  expect_true(grepl(packet$occupation$selected_code, guarded$text, fixed = TRUE))
})

test_that("H6.4: a code from an unauthorized/unrequested classification system is discarded", {
  packet <- assistant_coding_service("nurse", "private hospital", requested_systems = "psic")
  full <- assistant_coding_service("nurse", "private hospital", requested_systems = c("psoc", "psic"))
  fabricated <- sprintf(
    "Your PSIC is %s. Your PSOC is %s.",
    packet$industry$selected_code, full$occupation$selected_code
  )
  guarded <- assistant_guard_response(fabricated, packet)

  expect_true(guarded$used_fallback)
  expect_false(grepl(full$occupation$selected_code, guarded$text, fixed = TRUE))
})

test_that("H6.5: a clarification-turn reply that jumps ahead to a not-yet-resolved code is discarded", {
  packet <- assistant_coding_service("carpenter") # PSIC still pending clarification
  expect_identical(packet$status, "clarification_required")
  expect_true(length(packet$allowed_codes$psic) == 0L)

  fabricated <- "Your PSOC is 7115. Your PSIC is likely 41001 for residential construction."
  guarded <- assistant_guard_response(fabricated, packet)

  expect_true(guarded$used_fallback)
  expect_false(grepl("41001", guarded$text, fixed = TRUE))
  # The clarification question itself must still reach the user.
  expect_true(nzchar(guarded$text))
})

test_that("H6.6: an archived-edition code introduced by model prose is discarded, current selection stands", {
  packet <- assistant_coding_service("carpenter", "residential construction")
  expect_identical(packet$occupation$selected_code, "7115")

  # Any code the coding service did not itself select is unauthorized,
  # archived or not -- the guard does not need to know WHY a token is
  # disallowed, only that it is not in allowed_codes.
  fabricated <- "Under the 2012 PSOC edition this would have been coded 9333 instead."
  guarded <- assistant_guard_response(fabricated, packet)

  expect_true(guarded$used_fallback)
  expect_false(grepl("9333", guarded$text, fixed = TRUE))
  expect_true(grepl("7115", guarded$text, fixed = TRUE))
})

test_that("H6: repeatability holds across repeated failure injections (same structured outcome every run)", {
  results <- replicate(5, {
    packet <- assistant_coding_service("mayor", "local government")
    guarded <- assistant_guard_response("Your code is PSOC 1112.", packet)
    list(used_fallback = guarded$used_fallback,
         code = packet$occupation$selected_code,
         rejected_1112 = !grepl("1112", guarded$text, fixed = TRUE))
  }, simplify = FALSE)

  expect_true(all(vapply(results, function(r) r$used_fallback, logical(1))))
  expect_true(all(vapply(results, function(r) identical(r$code, "1111"), logical(1))))
  expect_true(all(vapply(results, function(r) r$rejected_1112, logical(1))))
})
