# Contract tests for the RM Assistant sidecar / drawer / sheet
# (imported Claude Design surface 1l).
#
# WHAT THESE PIN
#
#   1. RM is no longer a navigation destination, and the app mounts exactly
#      ONE chat -- two mounts would mean a duplicate shinychat id and two
#      transcripts of one conversation;
#   2. the docked desktop panel is genuinely NON-MODAL: no backdrop, no
#      focus trap, no aria-modal, and the page reflows beside it;
#   3. the two narrow breakpoints ARE modal, and the semantics are switched
#      at the breakpoint rather than guessed once at render time;
#   4. closing preserves the conversation and only New chat clears it;
#   5. attached context is visible, removable, per-session, and built only
#      from verified application objects.

.render <- function(tag) paste(as.character(htmltools::renderTags(tag)$html),
                               collapse = "")

.repo <- normalizePath(file.path(getwd(), "..", ".."), mustWork = TRUE)

.read_file <- function(...) {
  path <- file.path(.repo, ...)
  expect_true(file.exists(path), info = paste("missing file:", path))
  paste(readLines(path, warn = FALSE), collapse = "\n")
}

# Strips R comments so a prose mention of a symbol cannot pass or fail a
# structural assertion about the CODE.
.r_code_only <- function(src) {
  paste(sub("#.*$", "", strsplit(src, "\n", fixed = TRUE)[[1]]), collapse = "\n")
}

.up <- list(enabled = FALSE, available = FALSE, reason = "Assistant is turned off.")
.ok <- list(enabled = TRUE, available = TRUE, reason = NULL)


# ---------------------------------------------------------------------------
# 1. RM is a panel, not a destination
# ---------------------------------------------------------------------------

test_that("RM is not an ordinary nav panel any more", {
  app <- .read_file("app.R")
  expect_false(grepl('value = "rm_assistant"', app, fixed = TRUE))
  expect_false(grepl('nav_label("sparkles", "RM Assistant")', app, fixed = TRUE))

  # The four workspace destinations remain, with their identities intact.
  for (v in c("search", "dual_search", "correspondence", "about")) {
    expect_true(grepl(sprintf('value = "%s"', v), app, fixed = TRUE), info = v)
  }
})

test_that("the panel is mounted once, outside the navigation", {
  app <- .read_file("app.R")
  # `footer` renders once per page, outside the navset, on every
  # destination -- which is exactly the mount a global panel needs.
  expect_true(grepl("footer = shiny::tagList(", app, fixed = TRUE))
  expect_true(grepl("rm_sidecar_ui(rm_assistant_status())", app, fixed = TRUE))

  # Exactly one mount of the chat itself.
  hits <- gregexpr("rm_sidecar_ui(", app, fixed = TRUE)[[1]]
  expect_identical(length(hits[hits > 0]), 1L)
  expect_false(grepl("rm_assistant_ui()", .r_code_only(app), fixed = TRUE))
})

test_that("a global Ask RM launcher sits in the header on every page", {
  app <- .read_file("app.R")
  expect_true(grepl('rm_ask_button_ui("rm_open_global"', app, fixed = TRUE))
  expect_true(grepl("bslib::nav_item(", app, fixed = TRUE))

  html <- .render(rm_ask_button_ui("rm_open_global", "Ask RM"))
  expect_match(html, "^<button")
  # Client-side disclosure of a panel already in the DOM: no server
  # round-trip stands between the click and the panel.
  expect_true(grepl("data-psa-rm-open", html, fixed = TRUE))
  expect_true(grepl("Ask RM", html, fixed = TRUE))
})


# ---------------------------------------------------------------------------
# 2. Docked desktop panel is non-modal
# ---------------------------------------------------------------------------

test_that("the panel's static semantics are the NON-modal ones", {
  html <- .render(rm_sidecar_ui(.up))
  expect_true(grepl('role="complementary"', html, fixed = TRUE))
  # Checked on the panel's own opening tag: the inline behaviour script
  # inside it necessarily NAMES the attribute it switches at the
  # breakpoint, and a whole-subtree scan would match that instead.
  aside <- regmatches(html, regexpr("<aside[^>]*>", html))
  expect_gt(length(aside), 0L)
  expect_false(grepl("aria-modal", aside, fixed = TRUE))
  expect_true(grepl('aria-labelledby="rm-sidecar-title"', html, fixed = TRUE))
  # Closed to begin with, and hidden rather than absent.
  expect_true(grepl('data-open="false"', html, fixed = TRUE))
  expect_true(grepl("hidden", html, fixed = TRUE))
})

test_that("ARIA is switched at the docked breakpoint, not guessed once", {
  src <- .read_file("R", "ui", "ui_sidecar.R")
  expect_true(grepl('matchMedia("(min-width: 1280px)")', src, fixed = TRUE))
  expect_true(grepl('p.setAttribute("role", "complementary")', src, fixed = TRUE))
  expect_true(grepl('p.removeAttribute("aria-modal")', src, fixed = TRUE))
  expect_true(grepl('p.setAttribute("aria-modal", "true")', src, fixed = TRUE))
  # And it re-runs when the viewport crosses the breakpoint -- from the
  # media-query event AND from a plain resize listener. Browser UAT found
  # the media-query event not firing under viewport emulation, which left a
  # 1100px window still announcing a non-modal docked panel and still
  # reserving 440px of page for it.
  expect_true(grepl('DOCKED.addEventListener("change", syncSemantics)',
                    src, fixed = TRUE))
  expect_true(grepl('window.addEventListener("resize", syncSemantics)',
                    src, fixed = TRUE))
  expect_true(grepl("new ResizeObserver(syncSemantics).observe(document.documentElement)",
                    src, fixed = TRUE))

  # The backdrop follows the breakpoint too, not only the open action: an
  # overlay with no backdrop over live content is a modal that lies about
  # being modal.
  expect_true(grepl("s.hidden = DOCKED.matches || !isOpen();", src, fixed = TRUE))
})

test_that("focus is contained ONLY in the two modal breakpoints", {
  src <- .read_file("R", "ui", "ui_sidecar.R")
  # Trapping focus in a docked, non-modal side panel would be the
  # accessibility bug, not the fix.
  expect_true(grepl('if (e.key !== "Tab" || DOCKED.matches || !isOpen())',
                    src, fixed = TRUE))
})

test_that("the docked panel reflows the page and never dims it", {
  css <- .read_file("www", "ui-design.css")
  expect_true(grepl("@media (min-width: 1280px)", css, fixed = TRUE))
  # On <body>, not on the page container: the container's own padding is
  # zeroed by the fill-page rules, so a per-container override loses and
  # the results table runs on underneath the panel. Measured in the
  # browser, which is why the selector is asserted and not just the value.
  # `!important` is required, not sloppy: bslib's fill page writes
  # `style="padding:0px"` straight onto <body>, and an inline declaration
  # outranks every stylesheet rule. Without it the panel covers the content
  # it claims to sit beside.
  expect_true(grepl("body.psa-rm-docked { padding-inline-end: 440px !important; }",
                    css, fixed = TRUE))
  # The scrim is suppressed in the docked mode: dimming the page would say
  # the rest of the document is unavailable when it is not.
  expect_true(grepl(".psa-rm-scrim { display: none !important; }", css, fixed = TRUE))
  # And page scroll is locked only in the modal modes.
  expect_true(grepl("body.psa-rm-overlay { overflow: hidden; }", css, fixed = TRUE))
})

test_that("all three breakpoints are implemented on one element", {
  css <- .read_file("www", "ui-design.css")
  expect_true(grepl("@media (min-width: 1280px)", css, fixed = TRUE))
  expect_true(grepl("@media (min-width: 1024px) and (max-width: 1279.98px)",
                    css, fixed = TRUE))
  expect_true(grepl("@media (max-width: 1023.98px)", css, fixed = TRUE))
  expect_true(grepl("width: 440px;", css, fixed = TRUE))   # docked
  expect_true(grepl("width: 420px;", css, fixed = TRUE))   # overlay drawer
  expect_true(grepl("height: 94%;", css, fixed = TRUE))    # bottom sheet

  # ONE panel element, so there is only ever one chat.
  html <- .render(rm_sidecar_ui(.up))
  hits <- gregexpr('id="rm-sidecar"', html, fixed = TRUE)[[1]]
  expect_identical(length(hits[hits > 0]), 1L)
})

test_that("the CSS breakpoint and the script breakpoint agree", {
  # These two have to be the same number or the panel announces itself as
  # modal in the width where it is docked, or vice versa.
  expect_identical(RM_SIDECAR_DOCKED_MIN_PX, 1280)
  src <- .read_file("R", "ui", "ui_sidecar.R")
  css <- .read_file("www", "ui-design.css")
  expect_true(grepl("(min-width: 1280px)", src, fixed = TRUE))
  expect_true(grepl("(min-width: 1280px)", css, fixed = TRUE))
})


# ---------------------------------------------------------------------------
# 3. Persistence and New chat
# ---------------------------------------------------------------------------

test_that("closing hides the panel; only New chat clears the conversation", {
  src <- .read_file("R", "ui", "ui_sidecar.R")
  # Close sets `hidden` on an element that is never removed or re-rendered,
  # so the transcript and the ellmer turn history survive it.
  expect_true(grepl("p.hidden = true;", src, fixed = TRUE))
  expect_false(grepl("remove()", src, fixed = TRUE))

  # New chat is the EXISTING control and the EXISTING observer.
  html <- .render(rm_sidecar_ui(.ok))
  expect_true(grepl("rm_assistant-new_chat", html, fixed = TRUE))

  app <- .read_file("app.R")
  expect_true(grepl('input[["rm_assistant-new_chat"]]', app, fixed = TRUE))
  expect_true(grepl("rm_chat$clear()", app, fixed = TRUE))
})

test_that("closing restores focus to whatever opened the panel", {
  src <- .read_file("R", "ui", "ui_sidecar.R")
  expect_true(grepl("if (trigger) { opener = trigger; }", src, fixed = TRUE))
  expect_true(grepl("opener.focus()", src, fixed = TRUE))
  # Escape closes in every mode.
  expect_true(grepl('if (e.key !== "Escape" && e.key !== "Esc") { return; }',
                    src, fixed = TRUE))
})

test_that("the panel header carries a close control with a real name", {
  html <- .render(rm_sidecar_ui(.ok))
  expect_true(grepl('aria-label="Close the RM Assistant panel"', html, fixed = TRUE))
  expect_true(grepl("data-psa-rm-close", html, fixed = TRUE))
})


# ---------------------------------------------------------------------------
# 4. Attached context
# ---------------------------------------------------------------------------

test_that("attached context renders as visible, removable chips", {
  items <- list(
    `entry:psgc:Q2_2026:1001300000` = list(
      label = "1001300000 · Bukidnon · PSGC Q2 2026", detail = list()
    )
  )
  html <- .render(rm_context_chip_ui(items))

  expect_true(grepl("Attached context", html, fixed = TRUE))
  expect_true(grepl("1001300000 · Bukidnon", html, fixed = TRUE))
  # Removable, with an accessible name that says what is being removed.
  expect_true(grepl("Remove attached context: 1001300000", html, fixed = TRUE))
  expect_true(grepl("rm_context_remove", html, fixed = TRUE))
  # The dot that marks the chip as retrieved data is decorative only.
  expect_true(grepl('class="psa-rm-context-dot" aria-hidden="true"', html,
                    fixed = TRUE))
})

test_that("no chips means no context region at all", {
  expect_null(rm_context_chip_ui(NULL))
  expect_null(rm_context_chip_ui(list()))
})

test_that("context is built from verified application objects only", {
  src <- .read_file("R", "ui", "ui_sidecar.R")
  # The correspondence launcher reuses the EXISTING whitelist rather than a
  # second, parallel extraction.
  expect_true(grepl("correspondence_ask_rm_context(row)", src, fixed = TRUE))

  # What crosses into the assistant layer is an IDENTIFIER-ONLY descriptor
  # built by the bridge's own constructors, never a row and never a label.
  # A row carried across turns is a snapshot, and this application must not
  # present classification facts that were true earlier -- the descriptor
  # forces a fresh canonical read on the turn that uses it.
  expect_true(grepl("assistant_context_descriptor_entry(", src, fixed = TRUE))
  expect_true(grepl("assistant_context_descriptor_correspondence(", src, fixed = TRUE))
})

test_that("the chip's label never becomes the descriptor", {
  # The label is what the user reads; the descriptor is what RM reaches.
  # They must not be the same object, or a display string would end up
  # being treated as verified classification data.
  d <- assistant_context_descriptor_entry("psoc", "2022", "1112")
  expect_identical(sort(names(d)), sort(c("kind", "system", "version", "code")))
  expect_false("label" %in% names(d))
})

test_that("chips and descriptors are kept in step by ONE writer", {
  src <- .read_file("R", "ui", "ui_sidecar.R")
  # Attach, remove and New chat all route through sync_turn_state(), so the
  # visible chips and what RM can reach cannot diverge.
  expect_true(grepl("sync_turn_state <- function(items)", src, fixed = TRUE))
  # Three call sites: attach, remove, New chat.
  hits <- gregexpr("sync_turn_state(", src, fixed = TRUE)[[1]]
  expect_gte(length(hits[hits > 0]), 3L)

  # Removing a chip removes the context, and New chat clears both.
  expect_true(grepl('input[["rm_assistant-new_chat"]]', src, fixed = TRUE))
})

test_that("context is per-session and never global", {
  src <- .read_file("R", "ui", "ui_sidecar.R")
  # A reactiveVal declared INSIDE the server function: one visitor's
  # attached record can never appear in another's panel.
  expect_true(grepl("rm_sidecar_server <- function", src, fixed = TRUE))
  expect_true(grepl("attached <- shiny::reactiveVal(list())", src, fixed = TRUE))
  expect_false(grepl("<<-", src, fixed = TRUE))
})

test_that("attaching context does not touch the assistant pipeline", {
  # The panel records WHICH verified object the user pressed the button
  # from. It composes no prompt, calls no classification service and does
  # not bypass assistant_handle_turn().
  src <- .read_file("R", "ui", "ui_sidecar.R")
  code <- .r_code_only(src)
  for (forbidden in c("assistant_handle_turn", "create_rm_chat_client",
                      "search_classification", "set_turns", "chat_append",
                      "rm_assistant_tools")) {
    expect_false(grepl(forbidden, code, fixed = TRUE), info = forbidden)
  }
})


# ---------------------------------------------------------------------------
# 5. Degradation
# ---------------------------------------------------------------------------

test_that("an unconfigured deployment gets the degraded panel, not a broken one", {
  html <- .render(rm_sidecar_ui(.up))
  expect_true(grepl("temporarily unavailable", html, fixed = TRUE))
  expect_true(grepl("still search and browse", html, fixed = TRUE))
  # No chat, no New chat, no attached-context region to attach to.
  expect_false(grepl("rm_assistant-new_chat", html, fixed = TRUE))
  expect_false(grepl("rm_attached_context", html, fixed = TRUE))
  # And never a technical error surface.
  expect_false(grepl("Traceback", html, fixed = TRUE))
})

test_that("the server installs nothing when the assistant is unavailable", {
  src <- .read_file("R", "ui", "ui_sidecar.R")
  expect_true(grepl("if (!isTRUE(available)) {\n    return(invisible(NULL))",
                    src, fixed = TRUE))
})

test_that("contextual actions are not offered where they cannot be delivered", {
  app <- .read_file("app.R")
  expect_true(grepl("st <- rm_assistant_status()", app, fixed = TRUE))
  expect_true(grepl("if (!isTRUE(st$enabled) || !isTRUE(st$available)) return(NULL)",
                    app, fixed = TRUE))
})

test_that("no new .js asset was added for any of this", {
  # Behaviour ships as inline script from the module that owns it, exactly
  # as the dialog shell already does. A new www/*.js would be a new
  # dependency boundary.
  expect_false(any(grepl("[.]js$", list.files(file.path(.repo, "www")))))
})
