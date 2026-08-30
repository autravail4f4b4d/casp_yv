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

# --- W3: the batch route must not relax any existing route check -----------
#
# Three enforcement sites read `current_route` and are written as
# `identical(route, "contextual_coding")`: the tool-body interlock, the
# live-render suppression and the validate-then-append output guard. A new
# route STRING would have disengaged all three for batch turns, so the
# batch route is canonicalised to contextual_coding here.

test_that("a batch route enforces as contextual_coding, never as its own looser route", {
  st <- assistant_new_turn_state()
  assistant_turn_set_route(st, "batch_contextual_coding")
  expect_identical(assistant_turn_current_route(st), "contextual_coding")
  expect_identical(assistant_turn_declared_route(st), "batch_contextual_coding")
  expect_true(assistant_turn_is_batch(st))
})

test_that("a batch turn keeps the low-level tool interlock engaged", {
  st <- assistant_new_turn_state()
  assistant_turn_set_route(st, "batch_contextual_coding")
  # This is the exact predicate assistant_tools.R uses to refuse the
  # low-level authoritative tools on a coding turn.
  expect_true(identical(assistant_turn_current_route(st), "contextual_coding"))
})

test_that("a non-batch route is unaffected and is_batch stays false", {
  st <- assistant_new_turn_state()
  assistant_turn_set_route(st, "general_search")
  expect_identical(assistant_turn_current_route(st), "general_search")
  expect_identical(assistant_turn_declared_route(st), "general_search")
  expect_false(assistant_turn_is_batch(st))
})

test_that("a fresh state is not a batch, and an unknown route is not a batch", {
  st <- assistant_new_turn_state()
  expect_false(assistant_turn_is_batch(st))
  assistant_turn_set_route(st, "batch_contextual_coding")
  assistant_turn_set_route(st, "not_a_real_route")
  expect_false(assistant_turn_is_batch(st))
  expect_identical(assistant_turn_current_route(st), "contextual_coding")
  expect_false(assistant_turn_is_batch(NULL))
})

# --- W3: batch state isolation (spec 27) -----------------------------------

.batch_state_items <- function(text) assistant_batch_parse(text)$items

.batch_state_run <- function(state, items) {
  assistant_turn_begin_batch(state, length(items))
  for (it in items) {
    args <- assistant_batch_item_args(it)
    packet <- do.call(assistant_coding_service, args)
    assistant_turn_record_batch_item(state, it, packet, occupation = args$occupation)
  }
  assistant_turn_finalize_batch(state)
}

.batch_six_text <- paste(
  c("grab taxi driver psoc", "food panda bicycle driver psoc",
    "vulcanizer psoc", "online seller psoc",
    "data scientist psoc", "esports player psoc"),
  collapse = "\n"
)

test_that("each batch item keeps its own result -- the last does not overwrite the rest", {
  # The live defect: all six collapsed to PSOC 3424 (the LAST line).
  st <- assistant_new_turn_state()
  items <- .batch_state_items(.batch_six_text)
  res <- .batch_state_run(st, items)

  expect_identical(res$n_items, 6L)
  expect_identical(res$n_unresolved, 0L)
  codes <- vapply(assistant_turn_last_batch(st),
                  function(e) as.character(e$packet$occupation$selected_code),
                  character(1))
  expect_identical(codes, c("8325", "9335", "8141", "5247", "2124", "3424"))
  expect_length(unique(codes), 6L)
})

test_that("after a batch with nothing unresolved the session pending state is empty", {
  st <- assistant_new_turn_state()
  res <- .batch_state_run(st, .batch_state_items(.batch_six_text))
  expect_identical(res$n_unresolved, 0L)
  expect_false(res$pending_activated)
  expect_null(assistant_turn_pending(st))
})

test_that("a leftover pending question cannot become the first item's context", {
  st <- assistant_new_turn_state()
  assistant_turn_set_pending(st, assistant_coding_service("carpenter"),
                             occupation = "carpenter")
  expect_false(is.null(assistant_turn_pending(st)))
  assistant_turn_begin_batch(st, 2L)
  expect_null(assistant_turn_pending(st))
})

test_that("exactly one unresolved item becomes the active pending clarification", {
  st <- assistant_new_turn_state()
  items <- .batch_state_items("vulcanizer psoc\ncarpenter psoc psic")
  expect_length(items, 2L)
  res <- .batch_state_run(st, items)

  expect_identical(res$n_unresolved, 1L)
  expect_true(res$pending_activated)
  expect_identical(res$pending_index, 2L)
  pending <- assistant_turn_pending(st)
  expect_false(is.null(pending))
  expect_identical(pending$occupation, "carpenter")
  expect_identical(pending$missing_slot, "establishment_activity")

  # And the reply reruns THAT item, with no trace of the resolved sibling.
  args <- assistant_turn_apply_reply(st, "residential construction")
  expect_identical(args$occupation, "carpenter")
  expect_identical(args$establishment_activity, "residential construction")
})

test_that("two or more unresolved items activate NO pending clarification", {
  # Auto-picking one would route the user's next reply into it and silently
  # discard the other -- the overwrite bug in a new costume.
  st <- assistant_new_turn_state()
  items <- .batch_state_items("carpenter psoc psic\nwelder psoc psic")
  expect_length(items, 2L)
  res <- .batch_state_run(st, items)

  expect_gte(res$n_unresolved, 2L)
  expect_false(res$pending_activated)
  expect_true(is.na(res$pending_index))
  expect_null(assistant_turn_pending(st))
  # Instead, one prompt per unresolved item is returned.
  expect_length(res$prompts, res$n_unresolved)
  expect_true(all(nzchar(res$prompts)))
  expect_true(any(grepl("carpenter", res$prompts, fixed = TRUE)))
  expect_true(any(grepl("welder", res$prompts, fixed = TRUE)))
})

test_that("no item's pending state is ever visible as session state mid-batch", {
  st <- assistant_new_turn_state()
  items <- .batch_state_items("carpenter psoc psic\nvulcanizer psoc")
  assistant_turn_begin_batch(st, length(items))
  for (it in items) {
    args <- assistant_batch_item_args(it)
    packet <- do.call(assistant_coding_service, args)
    assistant_turn_record_batch_item(st, it, packet, occupation = args$occupation)
    # Item 1 needs clarification, yet nothing is written to the shared slot,
    # so it can never be picked up as item 2's context.
    expect_null(assistant_turn_pending(st))
  }
  assistant_turn_finalize_batch(st)
})

test_that("recorded items hold only their own slots, never a sibling's", {
  st <- assistant_new_turn_state()
  items <- .batch_state_items("vulcanizer psoc\ncarpenter psoc psic")
  .batch_state_run(st, items)
  recorded <- assistant_turn_last_batch(st)
  expect_identical(recorded[[1L]]$occupation, "vulcanizer")
  expect_identical(recorded[[2L]]$occupation, "carpenter")
  expect_identical(recorded[[1L]]$requested_systems, "psoc")
  expect_setequal(recorded[[2L]]$requested_systems, c("psoc", "psic"))
  expect_null(recorded[[1L]]$establishment_activity)
  expect_false(isTRUE(recorded[[1L]]$unresolved))
  expect_true(isTRUE(recorded[[2L]]$unresolved))
})

test_that("re-recording an item replaces that item only", {
  st <- assistant_new_turn_state()
  items <- .batch_state_items(.batch_six_text)
  assistant_turn_begin_batch(st, length(items))
  for (it in items) {
    assistant_turn_record_batch_item(
      st, it, do.call(assistant_coding_service, assistant_batch_item_args(it)),
      occupation = it$query
    )
  }
  assistant_turn_record_batch_item(
    st, items[[3L]],
    list(status = "resolved", allowed_codes = list(psoc = "9999", psic = character(0))),
    occupation = "replaced"
  )
  recorded <- assistant_turn_batch_items(st)
  expect_length(recorded, 6L)
  expect_identical(recorded[[3L]]$occupation, "replaced")
  expect_identical(recorded[[1L]]$occupation, "grab taxi driver")
  expect_identical(recorded[[6L]]$occupation, "esports player")
})

test_that("batch results are independent per session", {
  a <- assistant_new_turn_state()
  b <- assistant_new_turn_state()
  .batch_state_run(a, .batch_state_items("vulcanizer psoc\ncarpenter psoc psic"))
  expect_length(assistant_turn_last_batch(a), 2L)
  expect_length(assistant_turn_last_batch(b), 0L)
  expect_false(is.null(assistant_turn_pending(a)))
  expect_null(assistant_turn_pending(b))
})

test_that("a new chat drops the batch as well as the pending question", {
  st <- assistant_new_turn_state()
  .batch_state_run(st, .batch_state_items("vulcanizer psoc\ncarpenter psoc psic"))
  assistant_turn_clear(st)
  expect_null(assistant_turn_pending(st))
  expect_length(assistant_turn_last_batch(st), 0L)
  expect_length(assistant_turn_batch_items(st), 0L)
})

test_that("on a batch turn every item's codes stay authorised, not just the last", {
  # The coding tool overwrites `latest_packet` on every call, so without
  # accumulation the output guard would strike out items 1-5 and keep only
  # the last -- the collapse defect one layer down.
  st <- assistant_new_turn_state()
  assistant_turn_set_route(st, "batch_contextual_coding")
  assistant_turn_set_latest_packet(
    st, list(status = "resolved", allowed_codes = list(psoc = "8325", psic = character(0))))
  assistant_turn_set_latest_packet(
    st, list(status = "resolved", allowed_codes = list(psoc = "9335", psic = "49321")))
  assistant_turn_set_latest_packet(
    st, list(status = "resolved", allowed_codes = list(psoc = "3424", psic = character(0))))

  allowed <- assistant_allowed_codes(assistant_turn_latest_packet(st))
  expect_setequal(allowed, c("8325", "9335", "3424", "49321"))
  expect_true(assistant_guard_check("PSOC 8325, PSOC 9335 and PSOC 3424",
                                    assistant_turn_latest_packet(st))$ok)
  # Still a closed set: a code no item retrieved is still refused.
  expect_false(assistant_guard_check("PSOC 1112", assistant_turn_latest_packet(st))$ok)
})

test_that("a non-batch turn still REPLACES the packet, never accumulates", {
  st <- assistant_new_turn_state()
  assistant_turn_set_route(st, "contextual_coding")
  assistant_turn_set_latest_packet(
    st, list(status = "resolved", allowed_codes = list(psoc = "8325", psic = character(0))))
  assistant_turn_set_latest_packet(
    st, list(status = "resolved", allowed_codes = list(psoc = "3424", psic = character(0))))
  expect_identical(assistant_allowed_codes(assistant_turn_latest_packet(st)), "3424")
})

test_that("the accumulation window is one turn and does not survive the next", {
  st <- assistant_new_turn_state()
  assistant_turn_set_route(st, "batch_contextual_coding")
  assistant_turn_set_latest_packet(
    st, list(status = "resolved", allowed_codes = list(psoc = "3424", psic = character(0))))
  # Next turn: an ordinary follow-up must not inherit the batch's codes.
  assistant_turn_set_route(st, "contextual_coding")
  assistant_turn_set_latest_packet(
    st, list(status = "resolved", allowed_codes = list(psoc = "8323", psic = character(0))))
  expect_identical(assistant_allowed_codes(assistant_turn_latest_packet(st)), "8323")
  expect_false(assistant_guard_check("PSOC 3424", assistant_turn_latest_packet(st))$ok)
})

test_that("clearing the packet also clears the batch accumulator", {
  st <- assistant_new_turn_state()
  assistant_turn_set_route(st, "batch_contextual_coding")
  assistant_turn_set_latest_packet(
    st, list(status = "resolved", allowed_codes = list(psoc = "3424", psic = character(0))))
  assistant_turn_set_latest_packet(st, NULL)
  expect_null(assistant_turn_latest_packet(st))
  assistant_turn_set_latest_packet(
    st, list(status = "resolved", allowed_codes = list(psoc = "8325", psic = character(0))))
  expect_identical(assistant_allowed_codes(assistant_turn_latest_packet(st)), "8325")
})

test_that("the turns after a batch inherit nothing from it (spec 49/50)", {
  # Live, the batch's last answer (PSOC 3424) leaked into the independent
  # turns that followed. This walks the full router -> state -> service
  # sequence twice in two sessions and asserts no leakage either time.
  run_session <- function() {
    st <- assistant_new_turn_state()

    routed <- assistant_route_request(.batch_six_text, pending = assistant_turn_pending(st))
    expect_identical(routed$route, "batch_contextual_coding")
    assistant_turn_set_route(st, routed$route)
    assistant_turn_set_requested_systems(st, routed$requested_systems)
    .batch_state_run(st, routed$items)
    expect_null(assistant_turn_pending(st))

    follow_up <- function(text, occupation) {
      r <- assistant_route_request(text, pending = assistant_turn_pending(st))
      expect_identical(r$route, "contextual_coding")
      expect_null(r$items)
      expect_false(r$is_clarification_reply)
      assistant_turn_set_route(st, r$route)
      assistant_turn_set_requested_systems(st, r$requested_systems)
      p <- assistant_coding_service(
        occupation, requested_systems = assistant_turn_requested_systems(st))
      assistant_turn_set_latest_packet(st, p)
      as.character(p$occupation$selected_code)
    }

    code <- follow_up("angkas driver psoc", "angkas driver")
    expect_identical(code, "8323")
    # The batch's last code is no longer authorised for this turn.
    expect_false(assistant_guard_check("PSOC 3424", assistant_turn_latest_packet(st))$ok)

    expect_identical(follow_up("food panda bicycle driver psoc", "food panda bicycle driver"),
                     "9335")
    invisible(TRUE)
  }
  run_session()
  run_session()
})

test_that("finalizing without any recorded item is a no-op, not an error", {
  st <- assistant_new_turn_state()
  res <- assistant_turn_finalize_batch(st)
  expect_identical(res$n_items, 0L)
  expect_false(res$pending_activated)
  expect_null(assistant_turn_pending(st))
  expect_identical(assistant_turn_finalize_batch(NULL)$n_items, 0L)
})
