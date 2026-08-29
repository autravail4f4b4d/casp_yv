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

test_that("ordinary assistant text is completely unaffected by the override", {
  skip_if_not_installed("ellmer")
  skip_if_not_installed("shinychat")

  txt <- ellmer::ContentText(text = "PSOC 8332 is HEAVY TRUCK AND LORRY DRIVERS.")
  out <- assistant_render_tool_content(txt)
  expect_identical(out, "PSOC 8332 is HEAVY TRUCK AND LORRY DRIVERS.")
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
