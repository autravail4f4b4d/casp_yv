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

# --- multi-input routing (W3, spec 25/26) ----------------------------------
#
# The live defect: this exact paste routed as ONE contextual_coding request
# and collapsed to a single answer, because the router normalises
# whitespace before routing so the newlines were gone by then.

.router_batch_six <- paste(
  c("grab taxi driver psoc",
    "food panda bicycle driver psoc",
    "vulcanizer psoc",
    "online seller psoc",
    "data scientist psoc",
    "esports player psoc"),
  collapse = "\n"
)

test_that("six independent requests in one turn route as a batch, not one request", {
  r <- assistant_route_request(.router_batch_six)
  expect_identical(r$route, "batch_contextual_coding")
  expect_length(r$items, 6L)
  expect_identical(
    vapply(r$items, function(it) it$text, character(1)),
    c("grab taxi driver psoc", "food panda bicycle driver psoc",
      "vulcanizer psoc", "online seller psoc",
      "data scientist psoc", "esports player psoc")
  )
  # Each item carries its own systems; the turn's are the union.
  for (it in r$items) expect_identical(it$requested_systems, "psoc")
  expect_identical(r$requested_systems, "psoc")
})

test_that("the batch route is part of the declared taxonomy", {
  expect_true("batch_contextual_coding" %in% ASSISTANT_ROUTES)
  expect_true(assistant_route_request(.router_batch_six)$route %in% ASSISTANT_ROUTES)
})

test_that("the batch route is a coding route and is never wider than coding", {
  expect_true(assistant_route_is_coding("batch_contextual_coding"))
  expect_true(assistant_route_is_coding("contextual_coding"))
  expect_false(assistant_route_is_coding("general_search"))
  expect_false(assistant_route_is_coding("exact_code_lookup"))
  expect_false(assistant_route_is_coding(NULL))

  # A batch must not unlock a single tool the coding route does not have.
  batch_tools <- assistant_route_tool_names("batch_contextual_coding")
  expect_setequal(batch_tools, assistant_route_tool_names("contextual_coding"))
  expect_false("assistant_search_classification" %in% batch_tools)
  expect_false("assistant_search_common_pairings" %in% batch_tools)
  expect_false("assistant_get_classification_entry" %in% batch_tools)
})

test_that("single-request routing is unchanged field-for-field by batch support", {
  # No `items` field, no batch bookkeeping, on any non-batch route.
  for (q in c("carpenter psoc psic", "PSOC 833", "What is PSCCS?", "hello",
              "teacher in a private high school psoc psic")) {
    r <- assistant_route_request(q)
    expect_identical(names(r),
                     c("route", "requested_systems", "code_tokens",
                       "is_clarification_reply", "text"), info = q)
    expect_null(r$items, info = q)
  }
})

test_that("a multi-line turn that is not N coding requests routes exactly as before", {
  expect_identical(
    assistant_route_request("teacher in a private\nhigh school psoc psic")$route,
    "contextual_coding"
  )
  expect_identical(
    assistant_route_request("vulcanizer psoc\nthanks so much for the help")$route,
    "contextual_coding"
  )
})

test_that("a clarification reply is NEVER treated as a batch", {
  pending <- list(active = TRUE, missing_slot = "establishment_activity")
  # Even a reply that itself looks like several coding lines stays a reply:
  # the pending guard returns before batch detection is reached.
  r <- assistant_route_request("residential construction psoc\nschool building psoc",
                               pending = pending)
  expect_identical(r$route, "contextual_coding")
  expect_true(r$is_clarification_reply)
  expect_null(r$items)

  r2 <- assistant_route_request(.router_batch_six, pending = pending)
  expect_identical(r2$route, "contextual_coding")
  expect_true(r2$is_clarification_reply)
  expect_null(r2$items)
})

test_that("batch routing is deterministic across repeated calls", {
  routes <- vapply(1:20, function(i) assistant_route_request(.router_batch_six)$route,
                   character(1))
  expect_length(unique(routes), 1L)
  counts <- vapply(1:20, function(i) length(assistant_route_request(.router_batch_six)$items),
                   numeric(1))
  expect_length(unique(counts), 1L)
})
