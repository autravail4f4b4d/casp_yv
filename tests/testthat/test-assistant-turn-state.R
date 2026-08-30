# W1-C: session-scoped clarification state and its lifecycle.

test_that("a fresh state has no pending question", {
  st <- assistant_new_turn_state()
  expect_null(assistant_turn_pending(st))
})

test_that("two states are independent (session isolation)", {
  a <- assistant_new_turn_state()
  b <- assistant_new_turn_state()
  assistant_turn_set_pending(a, assistant_coding_service("carpenter"),
                             occupation = "carpenter")
  expect_false(is.null(assistant_turn_pending(a)))
  expect_null(assistant_turn_pending(b))
})

test_that("no pending state is stored at file scope", {
  # A module-level store would leak one visitor's question into another's
  # session, which is exactly what the per-session environment prevents.
  st <- assistant_new_turn_state()
  expect_true(is.environment(st))
  expect_false(identical(st, assistant_new_turn_state()))
})

test_that("a resolved packet clears rather than stores a pending question", {
  st <- assistant_new_turn_state()
  assistant_turn_set_pending(st, assistant_coding_service("mayor", "local government"),
                             occupation = "mayor")
  expect_null(assistant_turn_pending(st))
})

test_that("a clarification packet stores only the minimal rerun context", {
  st <- assistant_new_turn_state()
  p <- assistant_coding_service("carpenter")
  assistant_turn_set_pending(st, p, occupation = "carpenter")
  pending <- assistant_turn_pending(st)

  expect_true(pending$active)
  expect_identical(pending$occupation, "carpenter")
  expect_identical(pending$missing_slot, "establishment_activity")
  # No prose, no candidate pool.
  expect_false("candidates" %in% names(pending))
  expect_false("response" %in% names(pending))
})

test_that("clearing removes the pending question", {
  st <- assistant_new_turn_state()
  assistant_turn_set_pending(st, assistant_coding_service("carpenter"),
                             occupation = "carpenter")
  assistant_turn_clear(st)
  expect_null(assistant_turn_pending(st))
})

# --- the lifecycle the live build lacked entirely --------------------------

test_that("a reply fills the missing slot and reruns the SAME request", {
  st <- assistant_new_turn_state()
  first <- assistant_coding_service("carpenter")
  assistant_turn_set_pending(st, first, occupation = "carpenter")

  args <- assistant_turn_apply_reply(st, "residential construction")
  # The occupation is carried forward, not forgotten.
  expect_identical(args$occupation, "carpenter")
  expect_identical(args$establishment_activity, "residential construction")

  second <- do.call(assistant_coding_service, args)
  expect_identical(second$occupation$selected_code, "7115")
  expect_identical(second$industry$selected_code, "41001")
  expect_identical(second$status, "resolved")
})

test_that("a reply with no pending question yields nothing to rerun", {
  st <- assistant_new_turn_state()
  expect_null(assistant_turn_apply_reply(st, "residential construction"))
})

test_that("the wage-payer answer routes to the right unit's activity", {
  st <- assistant_new_turn_state()
  first <- assistant_coding_service("janitor", "manpower agency at a hospital")
  expect_identical(first$clarification$missing_slot, "wage_payer")
  assistant_turn_set_pending(st, first, occupation = "janitor",
                             establishment_activity = "manpower agency at a hospital")

  # Establishment pays -> classify the deployment site.
  site <- assistant_turn_apply_reply(st, "the hospital pays them")
  expect_identical(site$wage_payer, "establishment")
  expect_false(grepl("agency", site$establishment_activity, ignore.case = TRUE))
  site_p <- do.call(assistant_coding_service, site)
  expect_true(length(site_p$allowed_codes$psic) > 0L)

  # Agency pays -> classify the agency's own activity instead.
  agency <- assistant_turn_apply_reply(st, "the agency pays them")
  expect_identical(agency$wage_payer, "agency")
  expect_match(agency$establishment_activity, "employment agency", ignore.case = TRUE)
  agency_p <- do.call(assistant_coding_service, agency)
  expect_identical(agency_p$industry$selected_code, "78200")
})

test_that("an ambiguous payer answer leaves the slot unfilled rather than guessing", {
  st <- assistant_new_turn_state()
  first <- assistant_coding_service("janitor", "manpower agency at a hospital")
  assistant_turn_set_pending(st, first, occupation = "janitor",
                             establishment_activity = "manpower agency at a hospital")
  args <- assistant_turn_apply_reply(st, "not sure")
  expect_null(args$wage_payer)
  again <- do.call(assistant_coding_service, args)
  expect_identical(again$clarification$missing_slot, "wage_payer")
})

# --- H1/H2 micro-gate: route, requested-systems and packet tracking --------

test_that("a fresh state defaults to the MOST RESTRICTIVE route, never unset/unrestricted", {
  st <- assistant_new_turn_state()
  expect_identical(assistant_turn_current_route(st), "contextual_coding")
})

test_that("NULL state also reads as the restrictive default route", {
  expect_identical(assistant_turn_current_route(NULL), "contextual_coding")
})

test_that("setting a recognised route is reflected back", {
  st <- assistant_new_turn_state()
  assistant_turn_set_route(st, "general_search")
  expect_identical(assistant_turn_current_route(st), "general_search")
})

test_that("an unrecognised or missing route falls back to the restrictive default, not NULL/unrestricted", {
  st <- assistant_new_turn_state()
  assistant_turn_set_route(st, "general_search")
  assistant_turn_set_route(st, "not_a_real_route")
  expect_identical(assistant_turn_current_route(st), "contextual_coding")

  st2 <- assistant_new_turn_state()
  assistant_turn_set_route(st2, "general_search")
  assistant_turn_set_route(st2, NULL)
  expect_identical(assistant_turn_current_route(st2), "contextual_coding")
})

test_that("requested systems default to both when unset", {
  st <- assistant_new_turn_state()
  expect_identical(sort(assistant_turn_requested_systems(st)), c("psic", "psoc"))
})

test_that("requested systems can be narrowed to one system", {
  st <- assistant_new_turn_state()
  assistant_turn_set_requested_systems(st, "psic")
  expect_identical(assistant_turn_requested_systems(st), "psic")
})

test_that("an empty or unrecognised requested-systems value falls back to both, not zero", {
  st <- assistant_new_turn_state()
  assistant_turn_set_requested_systems(st, character(0))
  expect_identical(sort(assistant_turn_requested_systems(st)), c("psic", "psoc"))

  st2 <- assistant_new_turn_state()
  assistant_turn_set_requested_systems(st2, "not_a_system")
  expect_identical(sort(assistant_turn_requested_systems(st2)), c("psic", "psoc"))
})

test_that("the latest coding-service packet round-trips through the turn state", {
  st <- assistant_new_turn_state()
  expect_null(assistant_turn_latest_packet(st))
  p <- assistant_coding_service("mayor", "local government")
  assistant_turn_set_latest_packet(st, p)
  expect_identical(assistant_turn_latest_packet(st)$occupation$selected_code,
                   p$occupation$selected_code)
})

test_that("route and requested-systems are independent per session", {
  a <- assistant_new_turn_state()
  b <- assistant_new_turn_state()
  assistant_turn_set_route(a, "general_search")
  assistant_turn_set_requested_systems(a, "psic")
  expect_identical(assistant_turn_current_route(b), "contextual_coding")
  expect_identical(sort(assistant_turn_requested_systems(b)), c("psic", "psoc"))
})
