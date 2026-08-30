# W1-D / W2: output guard and deterministic rendering.
#
# The guard is the backstop for the one thing routing cannot prevent: the
# model simply typing a code. Live, "mayor" produced 1112 and the entry
# tool then confirmed 1112 exists, which made a guess look verified.

.mayor <- function() assistant_coding_service("mayor", "local government")

test_that("a response using only authorised codes passes", {
  p <- .mayor()
  txt <- "Occupation is PSOC 1111 and the industry is PSIC 84113 (2022/2026 editions)."
  g <- assistant_guard_response(txt, p)
  expect_true(g$check$ok)
  expect_false(g$used_fallback)
  expect_identical(g$text, txt)
})

test_that("the exact live failure -- an unauthorised 1112 -- is rejected", {
  p <- .mayor()
  g <- assistant_guard_response("The occupation is PSOC 1112, Senior Government Officials.", p)
  expect_false(g$check$ok)
  expect_true(g$used_fallback)
  expect_true("1112" %in% g$check$offending_codes)
  # The fallback states the authorised code instead.
  expect_match(g$text, "1111", fixed = TRUE)
  expect_false(grepl("1112", g$text, fixed = TRUE))
})

test_that("the guard never edits digits in place", {
  # Spec 19: rewriting 1112 -> 1111 would leave the surrounding argument
  # defending the wrong occupation. The whole reply is replaced instead.
  p <- .mayor()
  bad <- "PSOC 1112 fits because senior officials administer the municipality."
  g <- assistant_guard_response(bad, p)
  expect_false(identical(g$text, sub("1112", "1111", bad)))
  expect_true(g$used_fallback)
})

test_that("edition years are not mistaken for codes", {
  p <- .mayor()
  g <- assistant_guard_response(
    "PSOC 1111 from the 2022 edition; PSIC 84113 from the 2026 edition.", p
  )
  expect_true(g$check$ok)
})

test_that("a clarification-required system authorises no code at all", {
  p <- assistant_coding_service("carpenter")
  expect_length(p$allowed_codes$psic, 0L)
  g <- assistant_guard_response(
    "PSOC 7115. For industry, use PSIC 41001 for residential construction.", p
  )
  expect_false(g$check$ok)
  expect_true("41001" %in% g$check$offending_codes)
})

test_that("listing candidate PSIC codes during clarification is rejected", {
  p <- assistant_coding_service("carpenter")
  g <- assistant_guard_response(
    "It could be 41001, 41002, or 42100 depending on the employer.", p
  )
  expect_false(g$check$ok)
  expect_true(all(c("41001", "41002", "42100") %in% g$check$offending_codes))
})

test_that("a supported aggregate may be stated while detail is pending", {
  p <- assistant_coding_service("palay farmer", "growing of rice")
  expect_setequal(p$allowed_codes$psic, "0112")
  expect_true(assistant_guard_response("Rice growing is PSIC 0112.", p)$check$ok)
  # But not a detailed child.
  expect_false(assistant_guard_response("Use PSIC 01121.", p)$check$ok)
})

test_that("a no-verified-match packet authorises nothing", {
  p <- assistant_coding_service("professional AI prompt engineer",
                                requested_systems = "psoc")
  expect_length(assistant_allowed_codes(p), 0L)
  g <- assistant_guard_response("The closest PSOC is 2519.", p)
  expect_false(g$check$ok)
  expect_true(g$used_fallback)
})

test_that("prose with no codes at all is safe", {
  p <- assistant_coding_service("carpenter")
  expect_true(assistant_guard_response(
    "I need to know what the establishment mainly does before I can classify it.", p
  )$check$ok)
})

# --- deterministic rendering ------------------------------------------------

test_that("rendering states code, label, level, role, edition and status from R", {
  out <- assistant_render_coding_result(.mayor())
  for (needle in c("1111", "LEGISLATORS", "Unit Group", "detailed", "2022",
                   "current", "84113", "Philippine Statistics Authority")) {
    expect_true(grepl(needle, out, fixed = TRUE), info = needle)
  }
})

test_that("rendering surfaces the question when clarification is required", {
  out <- assistant_render_coding_result(assistant_coding_service("carpenter"))
  expect_match(out, "7115", fixed = TRUE)
  expect_match(out, "main activity", ignore.case = TRUE)
  # No PSIC code may appear.
  expect_false(grepl("41001|41002|4100", out))
})

test_that("rendering says plainly when nothing verified", {
  out <- assistant_render_coding_result(
    assistant_coding_service("professional AI prompt engineer", requested_systems = "psoc")
  )
  expect_match(out, "No code .* could be verified", ignore.case = TRUE)
})

test_that("the fallback rendering itself always passes the guard", {
  # Otherwise a rejected response would be replaced by another rejectable one.
  for (args in list(list("mayor", "local government"), list("carpenter"),
                    list("palay farmer", "growing of rice"),
                    list("corn farmer", "growing of corn"))) {
    p <- do.call(assistant_coding_service, args)
    rendered <- assistant_render_coding_result(p)
    expect_true(assistant_guard_check(rendered, p)$ok,
                info = paste(unlist(args), collapse = " / "))
  }
})
