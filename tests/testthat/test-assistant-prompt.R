# Wave 1C: RM system prompt content + provider-configurable client.
# No test here may make a network call or require a real API key.

# --- helpers ---------------------------------------------------------------

prompt_txt <- function() rm_system_prompt()

# Case-insensitive substring assertion with a readable failure message.
# Whitespace runs are collapsed first so an assertion is not broken merely by
# where the markdown source happens to wrap a line.
expect_contains_ci <- function(haystack, needle) {
  flat <- gsub("\\s+", " ", haystack)
  testthat::expect_true(
    grepl(needle, flat, fixed = FALSE, ignore.case = TRUE),
    info = paste0("expected to find /", needle, "/i in the text")
  )
}

# Run `code` with the given env vars set, restoring the prior state after.
# Uses withr when available; falls back to Sys.setenv/Sys.unsetenv. A value of
# NA means "unset this variable".
with_rm_env <- function(vars, code) {
  if (requireNamespace("withr", quietly = TRUE)) {
    return(withr::with_envvar(vars, code))
  }
  set_one <- function(n, v) {
    if (is.na(v)) {
      Sys.unsetenv(n)
    } else {
      args <- list(as.character(v))
      names(args) <- n
      do.call(Sys.setenv, args)
    }
  }
  nms <- names(vars)
  old <- Sys.getenv(nms, unset = NA_character_, names = TRUE)
  on.exit(for (n in nms) set_one(n, old[[n]]), add = TRUE)
  for (n in nms) set_one(n, vars[[n]])
  force(code)
}

# Env baseline that guarantees no provider credential is visible.
NO_CREDS <- list(OPENAI_API_KEY = NA, ANTHROPIC_API_KEY = NA, RM_PROVIDER = NA, RM_MODEL = NA)

# --- prompt file -----------------------------------------------------------

test_that("the RM system prompt file exists, loads, and is non-empty", {
  txt <- prompt_txt()
  expect_type(txt, "character")
  expect_length(txt, 1L)
  expect_true(nzchar(trimws(txt)))
})

test_that("the RM system prompt stays compact (no dataset or rules dump)", {
  # Ships on every request (spec 13.2). Well under this bound in practice;
  # the assertion exists to catch a classification table or the PSIC rules
  # markdown being pasted in.
  expect_lt(nchar(prompt_txt()), 8000L)
})

test_that("the RM system prompt states the absolute grounding rule", {
  txt <- prompt_txt()
  expect_contains_ci(txt, "grounding rule")
  expect_contains_ci(txt, "never invent a classification code")
  expect_contains_ci(txt, "never recall one from memory")
  expect_contains_ci(txt, "autocomplete")
  expect_contains_ci(txt, "registered classification tools")
  expect_contains_ci(txt, "could not verify it")
  expect_contains_ci(txt, "available classification data")
})

test_that("the RM system prompt names every supported classification system", {
  txt <- prompt_txt()
  for (sys in c("PSOC", "PSIC", "PSGC", "PSCED", "PCOICOP", "PCPC", "PSCCS")) {
    expect_true(grepl(sys, txt, fixed = TRUE), info = paste("missing system:", sys))
  }
})

test_that("the RM system prompt carries the PSIC vague-term probing guidance", {
  txt <- prompt_txt()
  expect_contains_ci(txt, "trading")
  expect_contains_ci(txt, "contractor")
  expect_contains_ci(txt, "general services")
  expect_contains_ci(txt, "probing question")
  expect_contains_ci(txt, "business name or physical appearance")
})

test_that("the RM system prompt forbids inferring PSIC from occupation", {
  expect_contains_ci(
    prompt_txt(),
    "do not infer the employer's PSIC from the worker's occupation"
  )
})

test_that("the RM system prompt treats common pairings as evidence only", {
  txt <- prompt_txt()
  expect_contains_ci(txt, "supporting evidence only")
  expect_contains_ci(txt, "never proves")
})

test_that("the RM system prompt names the supported languages", {
  txt <- prompt_txt()
  expect_contains_ci(txt, "English")
  expect_contains_ci(txt, "Filipino/Tagalog")
  expect_contains_ci(txt, "Cebuano/Bisaya")
  expect_contains_ci(txt, "code-switched")
  expect_contains_ci(txt, "official PSA title")
})

test_that("the RM system prompt includes intent routing across systems", {
  txt <- prompt_txt()
  expect_contains_ci(txt, "intent routing")
  expect_contains_ci(txt, "barangay")
  expect_contains_ci(txt, "do not force every query into PSOC or PSIC")
})

# --- rm_system_prompt() ----------------------------------------------------

test_that("rm_system_prompt() memoizes: repeated calls return the same text", {
  expect_identical(rm_system_prompt(), rm_system_prompt())
})

test_that("rm_system_prompt() errors clearly for a missing explicit path", {
  bad <- file.path(tempdir(), "definitely-not-here-RM_SYSTEM_PROMPT.md")
  expect_false(file.exists(bad))
  expect_error(rm_system_prompt(path = bad), "RM system prompt file not found")
  expect_error(rm_system_prompt(path = bad), basename(bad), fixed = TRUE)
})

# --- greeting and footer ---------------------------------------------------

test_that("RM_GREETING opens with the required Madayaw sentence", {
  # Tolerate leading markdown emphasis / whitespace around the sentence.
  plain <- gsub("[*_]", "", RM_GREETING)
  plain <- trimws(plain)
  expect_true(
    startsWith(plain, "Madayaw! I am RM."),
    info = paste0("greeting starts with: ", substr(plain, 1, 60))
  )
})

test_that("RM_GREETING carries the four starter suggestions in shinychat markup", {
  suggestions <- c(
    "Find the PSOC for an occupation",
    "Help me classify a business under PSIC",
    "Explain a classification code",
    "Which classification system should I use?"
  )
  for (s in suggestions) {
    expect_true(
      grepl(paste0("<span class='suggestion submit'>", s, "</span>"), RM_GREETING, fixed = TRUE),
      info = paste("missing suggestion markup for:", s)
    )
  }
  expect_equal(
    length(gregexpr("class='suggestion submit'", RM_GREETING, fixed = TRUE)[[1]]),
    4L
  )
})

test_that("RM_GREETING mentions the classification systems and languages", {
  for (sys in c("PSOC", "PSIC", "PSGC", "PSCED", "PCOICOP", "PCPC", "PSCCS")) {
    expect_true(grepl(sys, RM_GREETING, fixed = TRUE), info = paste("greeting missing:", sys))
  }
  expect_contains_ci(RM_GREETING, "Cebuano/Bisaya")
  expect_contains_ci(RM_GREETING, "follow-up question rather than guess")
})

test_that("RM_FOOTER_TEXT is a non-empty single string", {
  expect_type(RM_FOOTER_TEXT, "character")
  expect_length(RM_FOOTER_TEXT, 1L)
  expect_true(nzchar(trimws(RM_FOOTER_TEXT)))
  expect_contains_ci(RM_FOOTER_TEXT, "classification search and interpretation")
})

# --- provider gating: disabled (spec 21) -----------------------------------

test_that("the assistant is disabled by default when RM_ASSISTANT_ENABLED is unset", {
  with_rm_env(c(list(RM_ASSISTANT_ENABLED = NA), NO_CREDS), {
    expect_false(rm_assistant_enabled())
    st <- rm_assistant_status()
    expect_false(st$enabled)
    expect_false(st$available)
    expect_true(nzchar(st$reason))
    expect_null(create_rm_chat_client())
  })
})

test_that("false-y RM_ASSISTANT_ENABLED values all disable the assistant", {
  for (v in c("false", "FALSE", "False", "0", "no", "NO", "off", "Off", "")) {
    with_rm_env(c(list(RM_ASSISTANT_ENABLED = v), NO_CREDS), {
      expect_false(rm_assistant_enabled(), info = paste("value:", v))
      expect_false(rm_assistant_status()$available, info = paste("value:", v))
      expect_null(create_rm_chat_client())
    })
  }
})

test_that("truthy RM_ASSISTANT_ENABLED values flip the master switch on", {
  for (v in c("true", "TRUE", "1", "yes", "on")) {
    with_rm_env(list(RM_ASSISTANT_ENABLED = v), {
      expect_true(rm_assistant_enabled(), info = paste("value:", v))
    })
  }
})

# --- provider gating: missing credential -----------------------------------

test_that("an enabled assistant with no provider credential is unavailable, not an error", {
  with_rm_env(c(list(RM_ASSISTANT_ENABLED = "true"), NO_CREDS), {
    st <- suppressMessages(rm_assistant_status())
    expect_true(st$enabled)
    expect_false(st$available)
    expect_true(nzchar(st$reason))
    expect_false(grepl("Error in", st$reason, fixed = TRUE))
    expect_false(grepl("OPENAI_API_KEY", st$reason, fixed = TRUE))
    expect_null(suppressMessages(create_rm_chat_client()))
  })
})

test_that("an unsupported RM_PROVIDER is reported as unavailable without leaking detail", {
  with_rm_env(list(
    RM_ASSISTANT_ENABLED = "true",
    RM_PROVIDER = "not-a-real-provider",
    OPENAI_API_KEY = NA,
    ANTHROPIC_API_KEY = NA
  ), {
    st <- suppressMessages(rm_assistant_status())
    expect_false(st$available)
    expect_true(nzchar(st$reason))
    expect_false(grepl("not-a-real-provider", st$reason, fixed = TRUE))
    expect_null(suppressMessages(create_rm_chat_client()))
  })
})

test_that("the anthropic provider is gated on ANTHROPIC_API_KEY", {
  with_rm_env(list(
    RM_ASSISTANT_ENABLED = "true",
    RM_PROVIDER = "anthropic",
    ANTHROPIC_API_KEY = NA,
    OPENAI_API_KEY = "sk-openai-should-not-count"
  ), {
    st <- suppressMessages(rm_assistant_status())
    expect_false(st$available)
    expect_true(nzchar(st$reason))
    expect_null(suppressMessages(create_rm_chat_client()))
  })
})

# --- missing system prompt --------------------------------------------------

test_that("a missing system prompt file makes the assistant unavailable, not fatal", {
  old <- RM_SYSTEM_PROMPT_PATH
  RM_SYSTEM_PROMPT_PATH <<- file.path("prompts", "RM_SYSTEM_PROMPT_MISSING_FIXTURE.md")
  on.exit(RM_SYSTEM_PROMPT_PATH <<- old, add = TRUE)

  with_rm_env(list(
    RM_ASSISTANT_ENABLED = "true",
    RM_PROVIDER = "openai",
    OPENAI_API_KEY = "sk-test-not-a-real-key-0000"
  ), {
    st <- suppressMessages(rm_assistant_status())
    expect_true(st$enabled)
    expect_false(st$available)
    expect_true(nzchar(st$reason))
    expect_false(grepl("sk-test-not-a-real-key-0000", st$reason, fixed = TRUE))
    expect_null(suppressMessages(create_rm_chat_client()))
  })
})

# --- secret leakage ---------------------------------------------------------

test_that("no status reason ever contains a provider API key value", {
  fake <- "sk-RMTESTFAKEKEY-do-not-use-1234567890"
  scenarios <- list(
    list(RM_ASSISTANT_ENABLED = NA, OPENAI_API_KEY = fake),
    list(RM_ASSISTANT_ENABLED = "false", OPENAI_API_KEY = fake),
    list(RM_ASSISTANT_ENABLED = "true", RM_PROVIDER = "bogus", OPENAI_API_KEY = fake),
    list(RM_ASSISTANT_ENABLED = "true", RM_PROVIDER = "anthropic", ANTHROPIC_API_KEY = NA,
         OPENAI_API_KEY = fake)
  )
  for (sc in scenarios) {
    with_rm_env(sc, {
      st <- suppressMessages(rm_assistant_status())
      expect_false(grepl(fake, st$reason, fixed = TRUE))
      expect_false(grepl("sk-", st$reason, fixed = TRUE))
    })
  }
})

# --- config surface ---------------------------------------------------------

test_that("the model id defaults to RM_DEFAULT_MODEL and is env-overridable", {
  expect_type(RM_DEFAULT_MODEL, "character")
  expect_true(nzchar(RM_DEFAULT_MODEL))
  with_rm_env(list(RM_MODEL = NA), expect_identical(.rm_model_id(), RM_DEFAULT_MODEL))
  with_rm_env(list(RM_MODEL = "some-other-model"), expect_identical(.rm_model_id(), "some-other-model"))
})

test_that("the provider defaults to openai and is env-overridable", {
  with_rm_env(list(RM_PROVIDER = NA), expect_identical(.rm_provider_id(), "openai"))
  with_rm_env(list(RM_PROVIDER = "Anthropic"), expect_identical(.rm_provider_id(), "anthropic"))
})

# --- session isolation ------------------------------------------------------

test_that("no Chat object is cached at file scope", {
  # Guards the spec-10 session-isolation requirement structurally: the only
  # memoizing environment in the assistant prompt/client layer holds prompt
  # text, never a mutable Chat.
  cached <- mget(ls(.rm_prompt_cache), envir = .rm_prompt_cache)
  for (obj in cached) {
    expect_true(is.character(obj))
  }
})
