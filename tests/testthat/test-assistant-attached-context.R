# Attached-context bridge — the verified UI selection reaching RM.
#
# WHAT THESE PIN
#
#   1. the bridge reads the REPOSITORY, not the chip: every user-visible
#      field is a fresh canonical read, and an unreadable descriptor yields
#      nothing rather than a degraded answer;
#   2. the precedence order, which is the whole safety argument — a pending
#      clarification and a fresh coding request both outrank an attached
#      record;
#   3. removal actually removes;
#   4. the response guard authorises exactly the codes that read returned,
#      and nothing else.
#
# The five lettered cases are the acceptance matrix from the milestone
# brief, kept in that order and named so.

.psoc_code <- "1112"

# The phrasing the clarification-lifecycle suite already pins as raising
# the teacher's bounded establishment-detail question. Reused verbatim so
# case C exercises the same clarification the acceptance matrix names,
# rather than a differently-worded one that may route elsewhere.
TEACHER_REQUEST <- "teacher in a private high school psoc psic"

.entry_descriptor <- function(system = "psoc", version = "2022", code = .psoc_code) {
  assistant_context_descriptor_entry(system, version, code)
}

.corr_row <- function() {
  d <- search_psic_correspondence(query = "", from_version = "2019",
                                  to_version = "2026", limit = 50)
  if (is.null(d) || nrow(d) == 0L) return(NULL)
  paired <- d[!is.na(d$from_code) & !is.na(d$to_code), , drop = FALSE]
  if (nrow(paired) == 0L) return(NULL)
  paired[1, , drop = FALSE]
}

.corr_descriptor <- function(row) {
  assistant_context_descriptor_correspondence(
    from_version = row$from_version[[1]], from_code = row$from_code[[1]],
    to_version = row$to_version[[1]], to_code = row$to_code[[1]]
  )
}


# ---------------------------------------------------------------------------
# Descriptors carry identifiers and nothing else
# ---------------------------------------------------------------------------

test_that("a descriptor is identifiers only", {
  d <- .entry_descriptor()
  expect_identical(sort(names(d)), sort(c("kind", "system", "version", "code")))
  # No label, level, status or any other renderable fact: those would be a
  # snapshot, and a snapshot is what this design refuses to present.
  expect_false(any(c("label", "level", "status") %in% names(d)))
})

test_that("an incomplete descriptor is refused rather than half-built", {
  expect_null(assistant_context_descriptor_entry(NULL, "2022", "1112"))
  expect_null(assistant_context_descriptor_entry("psoc", NULL, "1112"))
  expect_null(assistant_context_descriptor_entry("psoc", "2022", NULL))
  # A relationship with neither side is not a relationship.
  expect_null(assistant_context_descriptor_correspondence("2019", NULL, "2026", NULL))
})


# ---------------------------------------------------------------------------
# Verification is a canonical read
# ---------------------------------------------------------------------------

test_that("verification returns the repository's fields, not the caller's", {
  v <- assistant_verify_attached_context(.entry_descriptor())
  expect_false(is.null(v))
  expect_identical(v$system, "psoc")
  expect_identical(v$code, .psoc_code)

  # The label, level and status are whatever the repository holds right
  # now. Compared against a direct read of the same record.
  row <- get_classification_entry("psoc", "2022", .psoc_code)
  expect_identical(v$label, as.character(row$label[[1]]))
  expect_identical(v$level, as.character(row$level[[1]]))
  expect_identical(v$status, as.character(row$status[[1]]))
})

test_that("an unreadable descriptor verifies to nothing", {
  # A fabricated code, a system that does not exist, and an edition that
  # does not carry the code all fail CLOSED.
  expect_null(assistant_verify_attached_context(
    assistant_context_descriptor_entry("psoc", "2022", "999999")))
  expect_null(assistant_verify_attached_context(
    assistant_context_descriptor_entry("not_a_system", "2022", "1112")))
  expect_null(assistant_verify_attached_context(list(kind = "nonsense")))
  expect_null(assistant_verify_attached_context(NULL))
})

test_that("a verified relationship comes from the correspondence artifact", {
  row <- .corr_row()
  skip_if(is.null(row), "no two-sided correspondence rows in the artifact")

  v <- assistant_verify_attached_context(.corr_descriptor(row))
  expect_false(is.null(v))
  expect_identical(v$from_code, as.character(row$from_code[[1]]))
  expect_identical(v$to_code, as.character(row$to_code[[1]]))
  expect_identical(v$relation_type, as.character(row$relation_type[[1]]))
})


# ---------------------------------------------------------------------------
# The packet, and what it authorises
# ---------------------------------------------------------------------------

test_that("the context packet authorises exactly the verified code", {
  v <- assistant_verify_attached_context(.entry_descriptor())
  pkt <- assistant_attached_context_packet(v)

  expect_identical(pkt$request_type, "attached_context")
  expect_identical(assistant_allowed_codes(pkt), .psoc_code)

  # The guard is doing its ordinary job against it: a code the read did not
  # return is refused exactly as it would be on a coding turn.
  chk <- assistant_guard_check("The answer is 9999 and also 1112.", pkt)
  expect_false(chk$ok)
  expect_true("9999" %in% chk$offending_codes)

  ok <- assistant_guard_check("This record is PSOC 1112.", pkt)
  expect_true(ok$ok)
})

test_that("a non-PSOC/PSIC record is authorised without being misfiled", {
  # A PSGC province attached from Search must authorise its own code. The
  # `context` slot exists so it does not have to be filed under `psoc` or
  # `psic` to get there, which would be a false statement in the packet.
  d <- assistant_context_descriptor_entry("psgc", "Q2_2026", "1001300000")
  v <- assistant_verify_attached_context(d)
  skip_if(is.null(v), "PSGC Q2_2026 1001300000 not present in this build")

  pkt <- assistant_attached_context_packet(v)
  expect_identical(assistant_allowed_codes(pkt), "1001300000")
  expect_identical(pkt$allowed_codes$psoc, character(0))
  expect_identical(pkt$allowed_codes$psic, character(0))
})

test_that("a coding-service packet is unaffected by the context slot", {
  pkt <- assistant_coding_service(occupation = "mayor",
                                  requested_systems = c("psoc"))
  expect_null(pkt$allowed_codes$context)
  expect_true(length(assistant_allowed_codes(pkt)) >= 0L)
})


# ===========================================================================
# ACCEPTANCE MATRIX
# ===========================================================================

# --- A. Attached PSOC 1112 + "Why is this classified here?" ----------------

test_that("A: a referential question resolves against the attached record", {
  st <- assistant_new_turn_state()
  assistant_turn_set_attached_context(st, list(.entry_descriptor()))

  res <- assistant_handle_turn("Why is this classified here?", st)

  expect_true(res$explanation_requested)
  expect_identical(res$route, "contextual_coding")
  # "this" is PSOC 1112, and that is the only code RM may utter.
  expect_identical(res$allowed_codes, .psoc_code)
  expect_false(is.na(res$context_note))
  expect_true(grepl(.psoc_code, res$context_note, fixed = TRUE))
  expect_true(grepl("PSOC", res$context_note, fixed = TRUE))

  # No coding was performed: the turn was not handled deterministically,
  # it was grounded. The model answers, guarded.
  expect_false(isTRUE(res$handled))

  # And the record is retained as the referent for a follow-up "why?".
  expect_identical(assistant_allowed_codes(assistant_turn_latest_packet(st)),
                   .psoc_code)
})

test_that("A: the grounding block carries only repository fields", {
  st <- assistant_new_turn_state()
  assistant_turn_set_attached_context(st, list(.entry_descriptor()))
  note <- assistant_handle_turn("Why is this classified here?", st)$context_note

  row <- get_classification_entry("psoc", "2022", .psoc_code)
  expect_true(grepl(as.character(row$label[[1]]), note, fixed = TRUE))
  expect_true(grepl("Philippine Statistics Authority", note, fixed = TRUE))
  # It says what "this" means, so the model cannot invent a referent.
  expect_true(grepl("they mean this record", note, fixed = TRUE))
})


# --- B. Fresh coding request supersedes stale attached context -------------

test_that("B: an explicit new coding request ignores the attached record", {
  st <- assistant_new_turn_state()
  assistant_turn_set_attached_context(st, list(.entry_descriptor()))

  res <- assistant_handle_turn("What is the PSOC for a statistician at PSA?", st)

  # Not a referential turn: the bridge never fires, and no context note is
  # produced for the model to be grounded with.
  expect_true(is.na(res$context_note))
  expect_false(isTRUE(res$explanation_requested))

  # It went down the ordinary coding path instead, and the attached 1112 is
  # NOT what came back.
  expect_true(isTRUE(res$handled))
  expect_false(identical(res$packet$occupation$selected_code, .psoc_code))

  # The context is still attached -- superseded for this turn, not deleted.
  expect_length(assistant_turn_attached_context(st), 1L)
})


# --- C. Pending clarification outranks unrelated attached context ----------

test_that("C: a bounded clarification reply resolves with context attached", {
  st <- assistant_new_turn_state()

  # Raise the teacher clarification the ordinary way.
  first <- assistant_handle_turn(TEACHER_REQUEST, st)
  skip_if(is.null(assistant_turn_pending(st)),
          "teacher did not raise a clarification in this build")
  question <- first$packet$clarification$question
  expect_true(is.character(question) && nzchar(question))

  # Now attach an unrelated record, mid-question.
  assistant_turn_set_attached_context(st, list(.entry_descriptor()))

  res <- assistant_handle_turn("latter", st)

  # The clarification resolved normally. The attached record neither
  # consumed the reply nor widened it into a fresh search.
  expect_true(isTRUE(res$handled))
  expect_true(is.na(res$context_note))
  expect_identical(res$status, "resolved")
  expect_false(identical(res$packet$occupation$selected_code, .psoc_code))
  # Answered means no pending state survives.
  expect_null(assistant_turn_pending(st))
})

test_that("C: the bridge refuses to fire while any question is pending", {
  st <- assistant_new_turn_state()
  assistant_handle_turn(TEACHER_REQUEST, st)
  skip_if(is.null(assistant_turn_pending(st)),
          "teacher did not raise a clarification in this build")
  assistant_turn_set_attached_context(st, list(.entry_descriptor()))

  # Even an explicitly referential turn defers to the outstanding question.
  expect_null(assistant_attached_context_for_turn(
    "Why is this classified here?",
    pending = assistant_turn_pending(st),
    latest_packet = NULL,
    descriptors = assistant_turn_attached_context(st)
  ))
})


# --- D. Removal removes ----------------------------------------------------

test_that("D: a removed record reaches no subsequent turn", {
  st <- assistant_new_turn_state()
  assistant_turn_set_attached_context(st, list(.entry_descriptor()))
  expect_length(assistant_turn_attached_context(st), 1L)

  # The chip is removed: the UI writes the remaining set, which is empty.
  assistant_turn_set_attached_context(st, list())
  expect_length(assistant_turn_attached_context(st), 0L)

  res <- assistant_handle_turn("Why is this classified here?", st)

  # No context is supplied to the model...
  expect_true(is.na(res$context_note))
  # ...and NO code is authorised by anything. Not merely "not 1112": the
  # turn must authorise nothing at all, which is the state a removed
  # referent has to leave behind.
  expect_identical(res$allowed_codes, character(0))
  expect_identical(
    assistant_allowed_codes(assistant_turn_latest_packet(st)),
    character(0)
  )

  # A packet object DOES exist, carrying no codes. That is the pre-existing
  # behaviour of a referential turn with no referent of any kind: it falls
  # through to ordinary routing, which produces an empty clarification
  # packet. Verified byte-identical at baseline HEAD 379b2b5, so the
  # assertion pins the baseline rather than the bridge.
  expect_false(is.null(assistant_turn_latest_packet(st)))
  expect_identical(res$status, "clarification_required")
})

test_that("D: New chat clears the attached records too", {
  st <- assistant_new_turn_state()
  assistant_turn_set_attached_context(st, list(.entry_descriptor()))
  assistant_turn_clear_attached_context(st)
  expect_length(assistant_turn_attached_context(st), 0L)
})


# --- E. Compare Editions relationship --------------------------------------

test_that("E: a referential question resolves against the attached relationship", {
  row <- .corr_row()
  skip_if(is.null(row), "no two-sided correspondence rows in the artifact")

  st <- assistant_new_turn_state()
  assistant_turn_set_attached_context(st, list(.corr_descriptor(row)))

  res <- assistant_handle_turn("Explain this relationship.", st)

  expect_true(res$explanation_requested)
  expect_false(is.na(res$context_note))

  # Both sides of the verified pair are authorised, and nothing else.
  expect_setequal(res$allowed_codes,
                  unique(c(as.character(row$from_code[[1]]),
                           as.character(row$to_code[[1]]))))

  # The block states the relationship and carries the statistical-use
  # safeguard, which is not optional on a correspondence.
  expect_true(grepl(as.character(row$relation_type[[1]]), res$context_note,
                    fixed = TRUE))
  expect_true(grepl("redistributing historical statistical values",
                    res$context_note, fixed = TRUE))
})


# ---------------------------------------------------------------------------
# Precedence, stated directly
# ---------------------------------------------------------------------------

test_that("an answer RM just produced outranks a record attached earlier", {
  st <- assistant_new_turn_state()
  assistant_turn_set_attached_context(st, list(.entry_descriptor()))
  coded <- assistant_handle_turn("What is the PSOC for a mayor?", st)
  skip_if(!isTRUE(coded$handled), "mayor did not resolve in this build")

  res <- assistant_handle_turn("Why?", st)
  # The existing explanation path took it: no context note, and the
  # retained packet is still the coding result, not the attached record.
  expect_true(res$explanation_requested)
  expect_true(is.na(res$context_note))
  expect_false(identical(assistant_allowed_codes(assistant_turn_latest_packet(st)),
                         .psoc_code))
})

test_that("the newest attachment is the one a referential turn resolves to", {
  row <- .corr_row()
  skip_if(is.null(row), "no two-sided correspondence rows in the artifact")

  st <- assistant_new_turn_state()
  # Entry first, relationship second: the relationship is what "this" means.
  assistant_turn_set_attached_context(
    st, list(.entry_descriptor(), .corr_descriptor(row))
  )
  v <- assistant_attached_context_for_turn(
    "Explain this relationship.", pending = NULL, latest_packet = NULL,
    descriptors = assistant_turn_attached_context(st)
  )
  expect_identical(v$kind, "correspondence")
})

test_that("a malformed descriptor is never counted as context", {
  st <- assistant_new_turn_state()
  assistant_turn_set_attached_context(st, list(list(kind = "nonsense"), "junk"))
  expect_length(assistant_turn_attached_context(st), 0L)

  res <- assistant_handle_turn("Why is this classified here?", st)
  expect_true(is.na(res$context_note))
})

test_that("the named regression matrix is unchanged with a record attached", {
  # THE NON-REGRESSION ARGUMENT, stated as a test rather than as prose.
  # Every one of these is a coding turn, so the bridge must be invisible to
  # it -- same codes, same clarification behaviour, and no context note
  # offered to the model on any of them.
  attach_and_run <- function(...) {
    st <- assistant_new_turn_state()
    assistant_turn_set_attached_context(st, list(.entry_descriptor()))
    msgs <- c(...)
    out <- NULL
    for (m in msgs) out <- assistant_handle_turn(m, st)
    out
  }
  psoc_of <- function(r) {
    c <- r$packet$occupation$selected_code
    if (is.null(c)) NA_character_ else as.character(c)
  }
  psic_of <- function(r) {
    c <- r$packet$industry$selected_code
    if (is.null(c)) NA_character_ else as.character(c)
  }

  expected <- list(
    list(msgs = "mayor psoc psic", psoc = "1111", psic = "84113"),
    list(msgs = c(TEACHER_REQUEST, "latter"), psoc = "2330", psic = "85314"),
    list(msgs = c("palay farmer psoc psic", "upland"), psoc = "6111", psic = "01123"),
    list(msgs = "corn farmer psoc psic", psoc = "6112", psic = "01130"),
    list(msgs = "statistician at PSA psoc psic", psoc = "2122", psic = "8411"),
    # The full activity phrase. This is the "narrowing is not a wall" case
    # from test-assistant-clarification-lifecycle.R, NOT the bare-qualifier
    # case below -- the two must never be confused for one another, which
    # is exactly the mistake a report of this matrix once made.
    list(msgs = c("carpenter psoc psic", "residential construction"),
         psoc = "7115", psic = "41001")
  )

  for (case in expected) {
    r <- do.call(attach_and_run, as.list(case$msgs))
    label <- paste(case$msgs, collapse = " -> ")
    expect_identical(r$status, "resolved", info = label)
    expect_identical(psoc_of(r), case$psoc, info = label)
    expect_identical(psic_of(r), case$psic, info = label)
    # The attached record contributed nothing to any of them.
    expect_true(is.na(r$context_note), info = label)
    expect_false(.psoc_code %in% r$allowed_codes, info = label)
  }

  # THE BARE QUALIFIER, with a record attached. "residential" alone is a
  # weak activity fragment: it must leave PSIC unresolved and keep asking,
  # and an attached record must not be able to convert it into an
  # authoritative classification. The oracle for this flow is
  # test-assistant-clarification-lifecycle.R:66, which this branch does not
  # modify; asserted again HERE because the attached-context condition is
  # the new variable.
  bare <- attach_and_run("carpenter psoc psic", "residential")
  expect_identical(bare$status, "clarification_required")
  expect_identical(psoc_of(bare), "7115")
  expect_true(is.na(psic_of(bare)))
  expect_false(grepl("41001", bare$render %||% "", fixed = TRUE))
  expect_false(grepl("87100", bare$render %||% "", fixed = TRUE))
  expect_true(is.na(bare$context_note))
})

test_that("the outsourced janitor still asks its wage-payer question", {
  st <- assistant_new_turn_state()
  assistant_turn_set_attached_context(st, list(.entry_descriptor()))
  first <- assistant_handle_turn(
    paste("I am a janitor deployed at a hospital through a manpower agency.",
          "What is my PSIC?"), st)
  expect_identical(first$status, "clarification_required")

  second <- assistant_handle_turn("the agency pays my wages", st)
  expect_identical(second$status, "resolved")
  expect_identical(as.character(second$packet$industry$selected_code), "78200")
  expect_true(is.na(second$context_note))
})

test_that("the bridge opens no retrieval path of its own", {
  src <- paste(readLines(
    file.path(normalizePath(file.path(getwd(), "..", ".."), mustWork = TRUE),
              "R", "assistant", "assistant_attached_context.R"),
    warn = FALSE
  ), collapse = "\n")
  code <- paste(sub("#.*$", "", strsplit(src, "\n", fixed = TRUE)[[1]]),
                collapse = "\n")

  # The ONLY services it may call are the two canonical readers.
  expect_true(grepl("get_classification_entry(", code, fixed = TRUE))
  expect_true(grepl("get_psic_correspondence(", code, fixed = TRUE))

  for (forbidden in c("search_classification", "assistant_coding_service",
                      "retrieval_", "semantic", "embedding",
                      "assistant_extract_slots")) {
    expect_false(grepl(forbidden, code, fixed = TRUE), info = forbidden)
  }
})
