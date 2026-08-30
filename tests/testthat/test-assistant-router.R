# W1-A: deterministic server-side intent router.
#
# The router is pure R and takes no model call, so the same text must
# always produce the same route. That determinism IS the fix for the live
# defect where one query took different authoritative routes in different
# sessions.

test_that("every route name is from the declared taxonomy", {
  for (q in c("PSOC 833", "mayor psoc psic", "What is PSCCS?", "hello",
              "compare PSIC 2019 and 2026 editions", "carpenter")) {
    expect_true(assistant_route_request(q)$route %in% ASSISTANT_ROUTES, info = q)
  }
})

test_that("an explicit system plus a code is an exact lookup, not coding", {
  # Spec 22: "PSOC 833" must return 833, never descend to a Unit Group.
  for (q in c("PSOC 833", "PSOC 8332", "PSIC 8612", "psoc 2221")) {
    expect_identical(assistant_route_request(q)$route, "exact_code_lookup", info = q)
  }
})

test_that("coding requests route to contextual_coding", {
  for (q in c("mayor psoc psic", "call center agent psoc",
              "barangay health worker psoc", "nurse in a private hospital",
              "teacher in private high school psoc psic", "corn farmer psoc psic",
              "carpenter psoc psic",
              "what is the PSIC of a janitor deployed through manpower agency")) {
    expect_identical(assistant_route_request(q)$route, "contextual_coding", info = q)
  }
})

test_that("system questions route to system_information, not coding", {
  for (q in c("What is PSCC?", "What is PSCCS?",
              "What are the components of PTSCS?",
              "What is the difference between PSCC and PSCCS?")) {
    expect_identical(assistant_route_request(q)$route, "system_information", info = q)
  }
})

test_that("edition questions route to edition_comparison", {
  expect_identical(assistant_route_request("compare PSIC 2019 and 2026 editions")$route,
                   "edition_comparison")
  expect_identical(assistant_route_request("show the correspondence for 4933")$route,
                   "edition_comparison")
})

test_that("greetings are not treated as classification requests", {
  for (q in c("hello", "hi", "thanks", "who are you")) {
    expect_identical(assistant_route_request(q)$route, "non_classification", info = q)
  }
})

test_that("requested systems are read from the registry, not a fixed list", {
  r <- assistant_route_request("mayor psoc psic")
  expect_setequal(r$requested_systems, c("psoc", "psic"))
  expect_setequal(assistant_route_request("What is PTSCS?")$requested_systems, "ptscs")
})

test_that("routing is deterministic across repeated calls", {
  for (q in c("mayor psoc psic", "PSOC 833", "What is PSCCS?", "carpenter")) {
    routes <- vapply(1:20, function(i) assistant_route_request(q)$route, character(1))
    expect_length(unique(routes), 1L)
  }
})

# --- route-specific tool surface (W1-E) ------------------------------------

test_that("the coding route exposes no low-level authoritative alternative", {
  allowed <- assistant_route_tool_names("contextual_coding")
  expect_false("assistant_search_classification" %in% allowed)
  expect_false("assistant_search_common_pairings" %in% allowed)
  expect_true("assistant_code_occupation_and_activity" %in% allowed)
})

test_that("common pairings are not model-selectable on ANY route", {
  # They remain available to the coding service internally, but never as a
  # route the model can pick as authority.
  for (rt in ASSISTANT_ROUTES) {
    expect_false("assistant_search_common_pairings" %in% assistant_route_tool_names(rt),
                 info = rt)
  }
})

test_that("route tool sets resolve to real registered ellmer tools", {
  skip_if_not_installed("ellmer")
  all_tools <- rm_assistant_tools()
  registered <- vapply(all_tools, function(t) t@name, character(1))
  for (rt in ASSISTANT_ROUTES) {
    nms <- assistant_route_tool_names(rt)
    expect_true(all(nms %in% registered), info = rt)
    picked <- vapply(assistant_tools_for_route(rt, all_tools),
                     function(t) t@name, character(1))
    expect_setequal(picked, nms)
  }
})

test_that("the exact-code route cannot reach the contextual resolver", {
  allowed <- assistant_route_tool_names("exact_code_lookup")
  expect_false("assistant_code_occupation_and_activity" %in% allowed)
  expect_true("assistant_get_classification_entry" %in% allowed)
})

# --- clarification-reply routing (spec 13) ---------------------------------

test_that("a short reply to a pending question stays on the coding route", {
  pending <- list(active = TRUE, missing_slot = "establishment_activity")
  r <- assistant_route_request("residential construction", pending = pending)
  expect_identical(r$route, "contextual_coding")
  expect_true(r$is_clarification_reply)
})

test_that("an explicit new code lookup supersedes a pending question", {
  pending <- list(active = TRUE, missing_slot = "establishment_activity")
  r <- assistant_route_request("PSOC 8332", pending = pending)
  expect_identical(r$route, "exact_code_lookup")
  expect_false(r$is_clarification_reply)
})

test_that("a system question supersedes a pending question", {
  pending <- list(active = TRUE, missing_slot = "establishment_activity")
  r <- assistant_route_request("What is PSCCS?", pending = pending)
  expect_identical(r$route, "system_information")
  expect_false(r$is_clarification_reply)
})
