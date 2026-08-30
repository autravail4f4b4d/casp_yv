# RM orchestration hardening: tool-trace suppression.
#
# Exercises the SAME dispatch path the live chat uses --
# `shinychat:::contents_shinychat()` -- rather than a parallel
# reimplementation, so a pass here is evidence about what actually renders,
# not just about this application's own wrapper function.

test_that("a tool request never renders the internal tool name or raw arguments", {
  skip_if_not_installed("ellmer")
  skip_if_not_installed("shinychat")

  req <- ellmer::ContentToolRequest(
    id = "call_1", name = "assistant_search_classification",
    arguments = list(system = "psoc", query = "heavy truck driver")
  )
  out <- assistant_render_tool_content(req)
  out_chr <- paste(as.character(out), collapse = " ")

  for (nm in ASSISTANT_INTERNAL_TOOL_NAME_LITERALS) {
    expect_false(grepl(nm, out_chr, fixed = TRUE), info = nm)
  }
  expect_false(grepl("heavy truck driver", out_chr, fixed = TRUE))
  expect_false(grepl("psoc", out_chr, fixed = TRUE))
})

test_that("a tool result never renders raw tool output or the internal tool name", {
  skip_if_not_installed("ellmer")
  skip_if_not_installed("shinychat")

  req <- ellmer::ContentToolRequest(
    id = "call_1", name = "assistant_get_classification_entry",
    arguments = list(system = "psoc", code = "8332")
  )
  res <- ellmer::ContentToolResult(
    value = list(found = TRUE, code = "8332", label = "HEAVY TRUCK AND LORRY DRIVERS"),
    request = req
  )
  out <- assistant_render_tool_content(res)
  out_chr <- paste(as.character(out), collapse = " ")

  for (nm in ASSISTANT_INTERNAL_TOOL_NAME_LITERALS) {
    expect_false(grepl(nm, out_chr, fixed = TRUE), info = nm)
  }
  expect_false(grepl("HEAVY TRUCK AND LORRY DRIVERS", out_chr, fixed = TRUE))
})

test_that("a tool request renders only the neutral status text", {
  skip_if_not_installed("ellmer")
  skip_if_not_installed("shinychat")

  req <- ellmer::ContentToolRequest(
    id = "call_2", name = "assistant_get_classification_system_info",
    arguments = list(system = "pscc")
  )
  out <- assistant_render_tool_content(req)
  out_chr <- paste(as.character(out), collapse = " ")
  expect_true(grepl(ASSISTANT_TOOL_STATUS_TEXT, out_chr, fixed = TRUE))
})

test_that("assistant text on a non-coding route renders exactly as shinychat's default would", {
  skip_if_not_installed("ellmer")
  skip_if_not_installed("shinychat")

  txt <- ellmer::ContentText(text = "PSOC 8332 is HEAVY TRUCK AND LORRY DRIVERS.")
  for (route in setdiff(ASSISTANT_ROUTES, "contextual_coding")) {
    out <- assistant_render_text_content_for_route(txt, route)
    expect_identical(out, "PSOC 8332 is HEAVY TRUCK AND LORRY DRIVERS.", info = route)
  }
})

test_that("H2: assistant text on the contextual_coding route is suppressed, not streamed live", {
  skip_if_not_installed("ellmer")
  skip_if_not_installed("shinychat")

  txt <- ellmer::ContentText(text = "PSOC 1112 is CHIEF EXECUTIVES.")
  out <- assistant_render_text_content_for_route(txt, "contextual_coding")
  expect_null(out)
})

test_that("H2: an unresolvable route (NA) defaults to suppression, not to rendering", {
  skip_if_not_installed("ellmer")
  skip_if_not_installed("shinychat")

  txt <- ellmer::ContentText(text = "some generated prose")
  out <- assistant_render_text_content_for_route(txt, NA_character_)
  expect_null(out)
})

test_that("H2: the live S7 dispatch path suppresses for a session actually registered on contextual_coding", {
  skip_if_not_installed("ellmer")
  skip_if_not_installed("shinychat")
  skip_if_not_installed("shiny")

  st <- assistant_new_turn_state()
  assistant_turn_set_route(st, "contextual_coding")
  fake_session <- structure(
    list(token = "h2-render-test-session"),
    class = "ShinySession"
  )
  assistant_register_session_turn_state(fake_session, st)
  on.exit(assistant_session_registry_reset(), add = TRUE)

  txt <- ellmer::ContentText(text = "PSOC 9999 is a fabricated code.")
  out <- shiny::withReactiveDomain(fake_session, {
    assistant_render_tool_content(txt)
  })
  expect_null(out)
})

test_that("H2: the live S7 dispatch path renders normally for a session on a non-coding route", {
  skip_if_not_installed("ellmer")
  skip_if_not_installed("shinychat")
  skip_if_not_installed("shiny")

  st <- assistant_new_turn_state()
  assistant_turn_set_route(st, "general_search")
  fake_session <- structure(
    list(token = "h2-render-test-session-2"),
    class = "ShinySession"
  )
  assistant_register_session_turn_state(fake_session, st)
  on.exit(assistant_session_registry_reset(), add = TRUE)

  txt <- ellmer::ContentText(text = "Here is what you searched for.")
  out <- shiny::withReactiveDomain(fake_session, {
    assistant_render_tool_content(txt)
  })
  expect_identical(out, "Here is what you searched for.")
})

test_that("session registry lifecycle: register -> lookup works -> onSessionEnded unregisters", {
  skip_if_not_installed("shiny")

  # A minimal fake session whose onSessionEnded() actually STORES the
  # callback (unlike the other fakes in this file, which omit the field
  # entirely and rely on manual assistant_session_registry_reset() in
  # on.exit) -- this lets the test invoke the callback itself to simulate
  # Shiny ending the session, proving the registered cleanup mechanism
  # (session$onSessionEnded(), wired in assistant_register_session_turn_state())
  # actually removes the entry rather than merely existing unused.
  cb_store <- new.env()
  cb_store$fns <- list()
  fake_session <- structure(
    list(
      token = "h2-lifecycle-test-session",
      onSessionEnded = function(fn) {
        cb_store$fns[[length(cb_store$fns) + 1L]] <- fn
        invisible(NULL)
      }
    ),
    class = "ShinySession"
  )

  st <- assistant_new_turn_state()
  before <- assistant_session_registry_size()

  # session starts -> registry entry registered
  assistant_register_session_turn_state(fake_session, st)
  expect_equal(assistant_session_registry_size(), before + 1L)

  # session active -> route lookup works
  found <- shiny::withReactiveDomain(fake_session, assistant_current_session_turn_state())
  expect_identical(found, st)

  # session ends -> registry entry removed (invoke the stored callback,
  # exactly as Shiny's session-ended machinery would).
  expect_length(cb_store$fns, 1L)
  for (f in cb_store$fns) f()

  expect_equal(assistant_session_registry_size(), before)
  found_after <- shiny::withReactiveDomain(fake_session, assistant_current_session_turn_state())
  expect_null(found_after)
})

test_that("an unregistered/unknown session fails closed for contextual coding text, never falls back to unrestricted rendering", {
  skip_if_not_installed("ellmer")
  skip_if_not_installed("shinychat")
  skip_if_not_installed("shiny")

  # A session token that was NEVER registered (no assistant_register_session_
  # turn_state() call for it at all) -- e.g. a stale/foreign token, or a
  # registration step that never ran. assistant_current_session_turn_state()
  # must return NULL for it, and the live S7 dispatch must treat that NULL
  # the same as "contextual_coding" (fail closed), never as "no session, so
  # render normally."
  unknown_session <- structure(
    list(token = "never-registered-session-token"),
    class = "ShinySession"
  )
  expect_null(shiny::withReactiveDomain(unknown_session, assistant_current_session_turn_state()))

  txt <- ellmer::ContentText(text = "PSOC 4321 is a fabricated code.")
  out <- shiny::withReactiveDomain(unknown_session, {
    assistant_render_tool_content(txt)
  })
  expect_null(out)
})

test_that("the suppression registers cleanly and is idempotent", {
  skip_if_not_installed("ellmer")
  skip_if_not_installed("shinychat")

  expect_true(isTRUE(.assistant_register_tool_trace_suppression()))
  # Calling it again must not error (S7 allows re-registering a method).
  expect_true(isTRUE(.assistant_register_tool_trace_suppression()))
})

test_that("every tool name literal this module tracks matches an actually-registered tool", {
  skip_if_not_installed("ellmer")
  registered <- vapply(rm_assistant_tools(), function(t) t@name, character(1))
  expect_setequal(ASSISTANT_INTERNAL_TOOL_NAME_LITERALS, registered)
})
