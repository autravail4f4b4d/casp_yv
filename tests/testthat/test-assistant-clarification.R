# W1 -- the bounded clarification resolver, unit level.
#
# These tests pin the RESOLUTION RULES themselves. The lifecycle tests in
# test-assistant-clarification-lifecycle.R drive the same rules through the
# real server entry point.

teacher_options <- function() {
  list(
    list(index = 1L, code = "85312",
         label = "Private general secondary education for children without special needs"),
    list(index = 2L, code = "85314",
         label = "Private general secondary education for children with special needs")
  )
}

rice_options <- function() {
  list(
    list(index = 1L, code = "01121", label = "Growing of rice in irrigated lowland"),
    list(index = 2L, code = "01122", label = "Growing of rice in rainfed lowland"),
    list(index = 3L, code = "01123", label = "Growing of rice in upland")
  )
}

# --- ordinal / positional references (spec 10) -----------------------------

test_that("every required ordinal and positional form resolves to its index", {
  cases <- list(
    "1" = 1L, "2" = 2L, "3" = 3L, "4" = 4L,
    "first" = 1L, "second" = 2L, "third" = 3L, "fourth" = 4L,
    "option 1" = 1L, "option 2" = 2L, "option 3" = 3L, "option 4" = 4L,
    "the first" = 1L, "the second" = 2L, "the third" = 3L, "the fourth" = 4L,
    "first one" = 1L, "second one" = 2L, "third one" = 3L, "fourth one" = 4L
  )
  for (nm in names(cases)) {
    expect_identical(
      assistant_option_reference_index(nm, 4L), cases[[nm]], info = nm
    )
  }
})

test_that("references tolerate case, punctuation and surrounding whitespace", {
  for (txt in c("  SECOND  ", "Option 2.", "the SECOND one!", "#2", "no. 2", "2nd")) {
    expect_identical(assistant_option_reference_index(txt, 4L), 2L, info = txt)
  }
})

test_that("former and latter resolve ONLY for a two-choice question", {
  for (txt in c("former", "the former")) {
    expect_identical(assistant_option_reference_index(txt, 2L), 1L, info = txt)
    expect_true(is.na(assistant_option_reference_index(txt, 3L)), info = txt)
  }
  for (txt in c("latter", "the latter")) {
    expect_identical(assistant_option_reference_index(txt, 2L), 2L, info = txt)
    expect_true(is.na(assistant_option_reference_index(txt, 3L)), info = txt)
  }
})

test_that("an index beyond the option count is refused, never clamped", {
  expect_true(is.na(assistant_option_reference_index("3", 2L)))
  expect_true(is.na(assistant_option_reference_index("option 4", 3L)))
})

test_that("ordinary words are not references", {
  for (txt in c("upland", "residential", "hospital", "", NA_character_)) {
    expect_true(is.na(assistant_option_reference_index(txt, 3L)),
                info = as.character(txt))
  }
})

# --- bounded option matching (spec 11/12) ----------------------------------

test_that("latter selects the SECOND pending option, with its canonical code", {
  m <- assistant_match_pending_option("latter", teacher_options())
  expect_true(m$matched)
  expect_identical(m$index, 2L)
  expect_identical(m$option$code, "85314")
  expect_identical(m$kind, "reference")
})

test_that("a full option label selects that option exactly", {
  m <- assistant_match_pending_option(
    "Private general secondary education for children with special needs",
    teacher_options()
  )
  expect_true(m$matched)
  expect_identical(m$option$code, "85314")
  expect_identical(m$kind, "exact_label")
})

test_that("a normalised label (case and punctuation differences) still selects", {
  m <- assistant_match_pending_option(
    "  private general secondary education, for children with special needs.  ",
    teacher_options()
  )
  expect_true(m$matched)
  expect_identical(m$option$code, "85314")
})

test_that("a token subset that fits exactly one option selects it", {
  m <- assistant_match_pending_option("upland", rice_options())
  expect_true(m$matched)
  expect_identical(m$option$code, "01123")
  expect_identical(m$kind, "label_subset")

  m2 <- assistant_match_pending_option("rainfed", rice_options())
  expect_identical(m2$option$code, "01122")
})

test_that("a token subset that fits more than one option is NOT a match", {
  # "special needs" is in both teacher labels; "growing of rice" is in all
  # three rice labels. Neither may silently pick a winner.
  expect_false(assistant_match_pending_option("special needs", teacher_options())$matched)
  expect_false(assistant_match_pending_option("growing of rice", rice_options())$matched)
})

test_that("with/without are distinguished by the token, not by substring", {
  a <- assistant_match_pending_option("without special needs", teacher_options())
  b <- assistant_match_pending_option("with special needs", teacher_options())
  expect_identical(a$option$code, "85312")
  expect_identical(b$option$code, "85314")
})

test_that("an unrelated reply matches nothing inside the bounded set", {
  for (txt in c("manufacture of prepared pigments", "carpenter", "psgc")) {
    expect_false(assistant_match_pending_option(txt, teacher_options())$matched,
                 info = txt)
  }
})

test_that("matching against no options is always a miss", {
  expect_false(assistant_match_pending_option("latter", list())$matched)
  expect_false(assistant_match_pending_option("latter", NULL)$matched)
})

# --- short ambiguous replies (spec 13) -------------------------------------

test_that("bare qualifiers are refused as activity answers", {
  for (txt in c("residential", "Residential", "private", "public", "government",
                "hospital", "school", "farm", "commercial", "the residential",
                "residential po")) {
    expect_true(assistant_reply_too_ambiguous(txt), info = txt)
  }
})

test_that("a reply that names an activity is NOT treated as ambiguous", {
  for (txt in c("residential construction", "residential building construction",
                "private general hospital", "growing of rice in upland",
                "the manpower agency pays me")) {
    expect_false(assistant_reply_too_ambiguous(txt), info = txt)
  }
})

test_that("the narrower question asks what the establishment does and names no code", {
  q <- assistant_narrow_activity_question("residential", "carpenter")
  expect_true(grepl("residential", q, fixed = TRUE))
  expect_true(grepl("carpenter", q, fixed = TRUE))
  expect_false(grepl("[0-9]{4,5}", q))
})

# --- explicit new coding requests (spec 14) --------------------------------

test_that("a substantive request naming a system supersedes a pending question", {
  for (txt in c("statistician at PSA psoc psic", "mayor psoc psic",
                "corn farmer psoc psic", "teacher in a private high school psoc psic",
                "what is the PSIC code of a bakery")) {
    expect_true(assistant_explicit_new_coding_request(txt), info = txt)
  }
})

test_that("a bare system token or bare coding wording does NOT supersede", {
  for (txt in c("psic", "psoc", "code", "what is the code", "classification",
                "please give me the code")) {
    expect_false(assistant_explicit_new_coding_request(txt), info = txt)
  }
})

test_that("an ordinary clarification reply never looks like a new request", {
  for (txt in c("latter", "second", "upland", "rainfed", "residential",
                "the manpower agency pays me", "the hospital pays me",
                "Private general secondary education for children with special needs")) {
    expect_false(assistant_explicit_new_coding_request(txt), info = txt)
  }
})

# --- explanation requests (spec 21) ----------------------------------------

test_that("explicit explanation asks are recognised", {
  for (txt in c("why?", "Why?", "explain this", "please explain",
                "what does this mean?", "what is the difference?",
                "bakit?", "pakipaliwanag")) {
    expect_true(assistant_explanation_requested(txt), info = txt)
  }
})

test_that("a description of work is never an explanation request", {
  for (txt in c("carpenter psoc psic", "mayor psoc psic", "latter",
                "I am a janitor deployed at a hospital through a manpower agency",
                "explain the duties of a barangay health worker in a rural health unit and code it")) {
    expect_false(assistant_explanation_requested(txt), info = txt)
  }
})

# --- canonical verification of a selected option ---------------------------

test_that("a selected option is re-verified against the canonical repository", {
  half <- assistant_verified_option_half("psic", "85314")
  expect_false(is.null(half))
  expect_identical(half$selected_code, "85314")
  expect_identical(tolower(half$status_current), "current")
  expect_true(nzchar(half$selected_label))
})

test_that("an unknown code cannot become an answer", {
  expect_null(assistant_verified_option_half("psic", "99999"))
  expect_null(assistant_verified_option_half("psic", NULL))
})

test_that("completing a packet preserves every fact except the answered slot", {
  base <- assistant_coding_service("teacher", "private high school")
  skip_if_not(identical(base$status, "clarification_required"))
  opt <- base$clarification$options[[2L]]

  done <- assistant_packet_with_selected_option(base, opt, system = "psic")
  expect_identical(done$status, "resolved")
  expect_identical(done$occupation$selected_code, base$occupation$selected_code)
  expect_identical(done$industry$selected_code, opt$code)
  expect_true(is.na(done$clarification$missing_slot))
  expect_length(done$clarification$options, 0L)
  expect_identical(done$allowed_codes$psic, opt$code)
  expect_identical(done$allowed_codes$psoc, base$allowed_codes$psoc)
})
