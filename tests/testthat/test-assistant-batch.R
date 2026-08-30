# W3: multi-input (batch) parsing.
#
# The live defect: six independent coding requests pasted one per line
# collapsed into ONE request, because the router normalises whitespace
# before routing and the newlines were gone by then. The last line's answer
# (PSOC 3424) became the whole turn's answer and then leaked forward.
#
# The splitter is false-negative-safe by design: not detecting a batch
# degrades to today's single-request behaviour, whereas falsely detecting
# one would shred a legitimate sentence. Every test below is therefore
# either "this exact batch splits" or "this must NOT split".

.batch_six <- paste(
  c("grab taxi driver psoc",
    "food panda bicycle driver psoc",
    "vulcanizer psoc",
    "online seller psoc",
    "data scientist psoc",
    "esports player psoc"),
  collapse = "\n"
)

test_that("the exact six-line batch splits into six items with per-item text", {
  parsed <- assistant_batch_parse(.batch_six)
  expect_true(parsed$is_batch)
  expect_length(parsed$items, 6L)
  expect_false(parsed$truncated)

  expect_identical(
    vapply(parsed$items, function(it) it$text, character(1)),
    c("grab taxi driver psoc", "food panda bicycle driver psoc",
      "vulcanizer psoc", "online seller psoc",
      "data scientist psoc", "esports player psoc")
  )
  # The resolver query drops the system token the user typed; the original
  # line is retained for rendering the request back (spec 28).
  expect_identical(
    vapply(parsed$items, function(it) it$query, character(1)),
    c("grab taxi driver", "food panda bicycle driver", "vulcanizer",
      "online seller", "data scientist", "esports player")
  )
  expect_identical(vapply(parsed$items, function(it) it$index, numeric(1)), as.numeric(1:6))
  for (it in parsed$items) expect_identical(it$requested_systems, "psoc")
})

test_that("windows line endings and list markers split identically", {
  crlf <- gsub("\n", "\r\n", .batch_six, fixed = TRUE)
  bullets <- paste0("- ", strsplit(.batch_six, "\n", fixed = TRUE)[[1L]], collapse = "\n")
  numbered <- paste0(1:6, ". ", strsplit(.batch_six, "\n", fixed = TRUE)[[1L]], collapse = "\n")
  for (variant in list(crlf, bullets, numbered)) {
    parsed <- assistant_batch_parse(variant)
    expect_true(parsed$is_batch)
    expect_identical(vapply(parsed$items, function(it) it$query, character(1)),
                     c("grab taxi driver", "food panda bicycle driver", "vulcanizer",
                       "online seller", "data scientist", "esports player"))
  }
})

test_that("blank lines between requests do not create empty items", {
  spaced <- paste("vulcanizer psoc", "", "   ", "online seller psoc", sep = "\n")
  parsed <- assistant_batch_parse(spaced)
  expect_true(parsed$is_batch)
  expect_length(parsed$items, 2L)
})

# --- everything that must NOT split ----------------------------------------

test_that("a single-line request is never a batch", {
  for (q in c("teacher in a private high school psoc psic",
              "grab taxi driver psoc",
              "what is the PSIC of a janitor deployed through manpower agency",
              "PSOC 833")) {
    expect_false(assistant_batch_parse(q)$is_batch, info = q)
    expect_identical(assistant_batch_split(q), character(0), info = q)
  }
})

test_that("a single question containing commas is not split", {
  q <- "I am a teacher, a coach, and a canteen owner, which psoc applies"
  expect_false(assistant_batch_parse(q)$is_batch)
})

test_that("ordinary multi-sentence prose is not split", {
  prose <- paste(
    "I want to ask about how classification works.",
    "My cousin runs a small store in the province.",
    "I am not sure which system I should be using here.",
    sep = "\n"
  )
  expect_false(assistant_batch_parse(prose)$is_batch)
})

test_that("a hard-wrapped single request is not split into two", {
  # This is why every line must carry its OWN explicit signal: without that
  # gate the router's three-character catch-all would send both fragments
  # to contextual_coding and one request would become two.
  wrapped <- "teacher in a private\nhigh school psoc psic"
  expect_false(assistant_batch_parse(wrapped)$is_batch)
})

test_that("one non-qualifying line vetoes the whole split", {
  expect_false(assistant_batch_parse("vulcanizer psoc\nthanks so much for the help")$is_batch)
  expect_false(assistant_batch_parse("hello po\nvulcanizer psoc")$is_batch)
  # A dangling connector means the request continues on the next line.
  expect_false(assistant_batch_parse("vulcanizer psoc and\nonline seller psoc")$is_batch)
  expect_false(assistant_batch_parse("vulcanizer psoc,\nonline seller psoc")$is_batch)
  # A leading conjunction means this line continues the one above.
  expect_false(assistant_batch_parse("vulcanizer psoc\nand online seller psoc")$is_batch)
})

test_that("lines without an explicit system or coding verb do not batch", {
  # Conservative on purpose: two bare nouns are as likely to be one wrapped
  # thought as two requests, so we decline and behave exactly as today.
  expect_false(assistant_batch_parse("vulcanizer\nonline seller")$is_batch)
})

test_that("code lookups, system questions and edition questions are not batch items", {
  expect_false(assistant_batch_parse("PSOC 833\nPSOC 8332")$is_batch)
  expect_false(assistant_batch_parse("what is psccs\nwhat is ptscs")$is_batch)
  expect_false(assistant_batch_parse("compare PSIC 2019 and 2026 editions\nvulcanizer psoc")$is_batch)
})

test_that("an over-long line is treated as prose, not a batch member", {
  long <- paste(rep("word", 20), collapse = " ")
  expect_false(assistant_batch_parse(paste("vulcanizer psoc", paste(long, "psoc"), sep = "\n"))$is_batch)
})

# --- bounds and determinism -------------------------------------------------

test_that("the batch is bounded and overflow is reported, never silently dropped", {
  n <- ASSISTANT_BATCH_MAX_ITEMS + 3L
  # Letters, not digits: a digit plus a named system is an exact code
  # lookup, which is correctly refused as a batch member.
  many <- paste(sprintf("driver type %s psoc", letters[seq_len(n)]), collapse = "\n")
  parsed <- assistant_batch_parse(many)
  expect_true(parsed$is_batch)
  expect_length(parsed$items, ASSISTANT_BATCH_MAX_ITEMS)
  expect_true(parsed$truncated)
  expect_length(parsed$dropped, 3L)
})

test_that("batch parsing is deterministic across repeated calls", {
  first <- assistant_batch_parse(.batch_six)
  for (i in 1:15) expect_identical(assistant_batch_parse(.batch_six), first)
})

test_that("empty, NA and non-scalar input never error", {
  for (x in list(NULL, NA, "", character(0), c("a", "b"), 5)) {
    expect_false(assistant_batch_parse(x)$is_batch)
  }
})

# --- per-item argument isolation --------------------------------------------

test_that("each item's resolver arguments come only from that item", {
  items <- assistant_batch_parse(.batch_six)$items
  a1 <- assistant_batch_item_args(items[[1L]])
  a6 <- assistant_batch_item_args(items[[6L]])
  expect_identical(a1$occupation, "grab taxi driver")
  expect_identical(a6$occupation, "esports player")
  # No slot from a sibling item ever appears.
  for (a in list(a1, a6)) {
    expect_null(a$establishment_activity)
    expect_null(a$wage_payer)
    expect_identical(a$requested_systems, "psoc")
  }
})

test_that("each item resolves independently to its own code", {
  # Spec 49: the six requests must produce six distinct answers, and the
  # last one must not overwrite the earlier ones.
  items <- assistant_batch_parse(.batch_six)$items
  codes <- vapply(items, function(it) {
    p <- do.call(assistant_coding_service, assistant_batch_item_args(it))
    as.character(p$occupation$selected_code)
  }, character(1))
  expect_identical(codes, c("8325", "9335", "8141", "5247", "2124", "3424"))
})

test_that("merging item packets unions their allowed codes and renders nothing itself", {
  p1 <- list(status = "resolved", allowed_codes = list(psoc = "8325", psic = character(0)))
  p2 <- list(status = "resolved", allowed_codes = list(psoc = c("9335", "8325"), psic = "49321"))
  merged <- assistant_batch_merge_packets(list(p1, p2, NULL))
  expect_setequal(merged$allowed_codes$psoc, c("8325", "9335"))
  expect_identical(merged$allowed_codes$psic, "49321")
  # No single answer to render from a batch.
  expect_null(merged$occupation)
  expect_null(merged$industry)
  # The guard reads the union through its normal accessor.
  expect_setequal(assistant_allowed_codes(merged), c("8325", "9335", "49321"))
})

test_that("a merged batch packet still refuses a code no item retrieved", {
  items <- assistant_batch_parse(.batch_six)$items
  pkts <- lapply(items, function(it) do.call(assistant_coding_service,
                                             assistant_batch_item_args(it)))
  merged <- assistant_batch_merge_packets(pkts)
  expect_true(assistant_guard_check("PSOC 8325 and PSOC 3424", merged)$ok)
  expect_false(assistant_guard_check("The answer is PSOC 1112.", merged)$ok)
})
