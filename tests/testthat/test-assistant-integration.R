# Convergence-level tests: the assistant wired into the application.
#
# These sit above the per-workstream unit tests (test-assistant-data.R,
# test-assistant-tools.R, test-assistant-prompt.R) and assert the
# properties that only emerge once the pieces are combined:
#
#   * the deterministic classification app is COMPLETELY unaffected by the
#     assistant's availability (spec 21) -- this is the single most
#     important integration property, because a public deployment without
#     provider credentials must still be a working classification tool;
#   * each Shiny session gets its own mutable chat client (spec 10/22);
#   * the model's entire code-bearing surface is the five read-only tools.
#
# None of these tests make a network call or require a real API key.

.with_env <- function(vars, code) {
  old <- Sys.getenv(names(vars), names = TRUE, unset = NA)
  do.call(Sys.setenv, as.list(vars))
  on.exit({
    set_back <- old[!is.na(old)]
    if (length(set_back)) do.call(Sys.setenv, as.list(set_back))
    unset <- names(old)[is.na(old)]
    if (length(unset)) Sys.unsetenv(unset)
  }, add = TRUE)
  force(code)
}

# ---------------------------------------------------------------------------
# The deterministic application never depends on the assistant
# ---------------------------------------------------------------------------

test_that("every deterministic classification service still works with the assistant disabled", {
  .with_env(c(RM_ASSISTANT_ENABLED = "false"), {
    expect_false(rm_assistant_enabled())
    expect_null(create_rm_chat_client())

    # The full pre-existing service contract, exercised with RM off.
    reg <- classification_registry()
    expect_equal(nrow(reg), 10)

    expect_equal(classification_versions("psoc"), reg$available_versions[reg$id == "psoc"][[1]])

    psoc <- search_classification("psoc", "2022", "2121")
    expect_true(nrow(psoc) >= 1)
    expect_equal(psoc$code[[1]], "2121")

    psic <- search_classification("psic", "2026", "01111")
    expect_true(nrow(psic) >= 1)

    dual <- search_parallel_classifications("accountant")
    expect_equal(dual$metadata$psoc_version, "2022")
    expect_equal(dual$metadata$psic_version, "2026")

    corr <- get_psic_correspondence("01111", from_version = "2019", to_version = "2026")
    expect_true(nrow(corr) >= 1)
  })
})

test_that("the assistant's own read-only tools still work with the LLM provider disabled", {
  # Tool wrappers are plain R functions over the repository -- they must not
  # be coupled to provider availability. Only the *chat client* needs a
  # provider; retrieval never does.
  .with_env(c(RM_ASSISTANT_ENABLED = "false"), {
    res <- assistant_search_classification("psoc", "accountant")
    expect_true(length(res$results) > 0)

    entry <- assistant_get_classification_entry("psoc", "2022", "2121")
    expect_true(entry$found)
  })
})

# ---------------------------------------------------------------------------
# UI assembles in both states
# ---------------------------------------------------------------------------

test_that("the RM panel renders its available and unavailable bodies without error", {
  chat <- paste(as.character(rm_assistant_ui()), collapse = "")
  expect_true(nzchar(chat))
  expect_true(grepl("Madayaw! I am RM.", chat, fixed = TRUE))
  # The static greeting must be in the initial HTML -- no model call, no
  # server round-trip (spec 9).
  expect_true(grepl("suggestion submit", chat, fixed = TRUE))
  expect_true(grepl("rm_assistant-new_chat", chat, fixed = TRUE))

  down <- paste(as.character(rm_assistant_unavailable_ui("Assistant is turned off.")), collapse = "")
  expect_true(grepl("temporarily unavailable", down, fixed = TRUE))
  expect_true(grepl("still search and browse", down, fixed = TRUE))
  # Degraded state must never render a technical error surface.
  expect_false(grepl("Error in", down, fixed = TRUE))
  expect_false(grepl("Traceback", down, fixed = TRUE))
})

test_that("the unavailable panel tolerates a missing reason", {
  for (bad in list(NULL, NA_character_, "", "   ")) {
    out <- paste(as.character(rm_assistant_unavailable_ui(bad)), collapse = "")
    expect_true(grepl("temporarily unavailable", out, fixed = TRUE))
  }
})

# ---------------------------------------------------------------------------
# Session isolation (spec 10/22)
# ---------------------------------------------------------------------------

test_that("each call to create_rm_chat_client returns a NEW mutable client", {
  skip_if_not_installed("ellmer")

  # A syntactically-valid but fake key: ellmer builds the client object
  # without contacting the provider, so this stays offline.
  .with_env(
    c(RM_ASSISTANT_ENABLED = "true", RM_PROVIDER = "openai", OPENAI_API_KEY = "sk-test-not-a-real-key"),
    {
      st <- rm_assistant_status()
      skip_if_not(isTRUE(st$available), paste("client unavailable:", st$reason))

      a <- create_rm_chat_client()
      b <- create_rm_chat_client()

      expect_false(is.null(a))
      expect_false(is.null(b))
      # Distinct R6 objects: mutating one must never affect the other, or a
      # public user's conversation would leak into another session's.
      expect_false(identical(a, b))

      a$set_turns(list())
      expect_equal(length(a$get_turns()), 0L)
    }
  )
})

test_that("a fake API key is never echoed into user-visible status text", {
  secret <- "sk-test-SUPERSECRET-value"
  .with_env(
    c(RM_ASSISTANT_ENABLED = "true", RM_PROVIDER = "openai", OPENAI_API_KEY = secret),
    {
      st <- rm_assistant_status()
      expect_false(grepl(secret, st$reason %||% "", fixed = TRUE))
    }
  )
})

# ---------------------------------------------------------------------------
# The model's code-bearing surface is exactly the five read-only tools
# ---------------------------------------------------------------------------

test_that("exactly the five approved read-only tools are registered", {
  skip_if_not_installed("ellmer")

  tools <- rm_assistant_tools()
  nms <- vapply(tools, function(t) t@name, character(1))

  expect_setequal(nms, c(
    "assistant_search_classification",
    "assistant_get_classification_entry",
    "assistant_classification_registry",
    "assistant_search_common_pairings",
    "assistant_get_psic_rule"
  ))

  # No synonym capability in V1 -- no approved source exists, and a
  # fabricated one would be an ungrounded path to a code.
  expect_false("assistant_lookup_synonyms" %in% nms)

  # Nothing that could mutate state, read arbitrary paths, or reach the network.
  expect_false(any(grepl("write|delete|update|create|set_|exec|shell|fetch|http", nms)))
})

test_that("the client registers the tools it was given", {
  skip_if_not_installed("ellmer")

  .with_env(
    c(RM_ASSISTANT_ENABLED = "true", RM_PROVIDER = "openai", OPENAI_API_KEY = "sk-test-not-a-real-key"),
    {
      st <- rm_assistant_status()
      skip_if_not(isTRUE(st$available), paste("client unavailable:", st$reason))

      client <- create_rm_chat_client(tools = rm_assistant_tools())
      expect_false(is.null(client))
      expect_equal(length(client$get_tools()), 5L)
    }
  )
})

# ---------------------------------------------------------------------------
# End-to-end grounding: no retrieval => no code
# ---------------------------------------------------------------------------

test_that("an unverifiable code cannot be dressed up as a verified answer anywhere in the tool layer", {
  for (sv in list(
    list("psoc", "2022", "999999"),
    list("psic", "2026", "99999"),
    list("psoc", "2022", "ZZZZ")
  )) {
    res <- assistant_get_classification_entry(sv[[1]], sv[[2]], sv[[3]])
    expect_false(isTRUE(res$found))
    # No official label may be attached to an unverified code.
    expect_null(res$label)
    expect_true(nzchar(res$message))
  }
})

test_that("the assistant asset layer degrades without disabling official classification retrieval", {
  # Simulate both evidence artifacts being absent. Official search/verify
  # must keep working; only the supporting-evidence tools go unavailable.
  pair <- assistant_search_common_pairings(occupation = "clerk", .pairings = NULL)
  expect_false(isTRUE(pair$available))

  rule <- assistant_get_psic_rule("principal_activity", .rules = NULL)
  expect_false(isTRUE(rule$available))
  # Must tell the caller NOT to fall back on model memory (spec 21).
  expect_true(grepl("memory|unavailable", rule$reason %||% rule$message %||% "", ignore.case = TRUE))

  # Official retrieval is untouched.
  still <- assistant_get_classification_entry("psoc", "2022", "2121")
  expect_true(still$found)
})
