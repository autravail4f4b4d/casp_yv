# Structural contract for the dark editorial "liquid glass" pass
# (UI_REFINEMENT_LIQUID_GLASS_HANDOFF.md).
#
# WHAT THESE TESTS ARE FOR, AND WHAT THEY DELIBERATELY ARE NOT.
#
# The handoff (section 25) asks for structural tests and explicitly warns
# against brittle assertions on exact visual values. So nothing here asserts
# a pixel, a radius or a hex code -- those are expected to be retuned by the
# next design pass and a test that froze them would be a tax, not a guard.
#
# What IS asserted is the set of facts that would fail SILENTLY in a browser
# and that a restyle is uniquely likely to break:
#
#   1. a stylesheet that is never loaded, or loaded in the wrong order
#      (this system is built entirely on later-sheet-wins cascade order);
#   2. a glass surface that lost its class in a merge, so it renders as a
#      bare rectangle on black;
#   3. an input, output, tab or dialog id renamed in passing -- every one of
#      which silently detaches a server observer;
#   4. an accessibility hook (label, aria state, focus ring, reduced-motion
#      escape, no-backdrop-filter fallback) dropped for a visual effect.

.render <- function(tag) as.character(htmltools::renderTags(tag)$html)

.repo <- normalizePath(file.path(getwd(), "..", ".."), mustWork = TRUE)

.read <- function(...) {
  path <- file.path(.repo, ...)
  expect_true(file.exists(path), info = paste("missing file:", path))
  paste(readLines(path, warn = FALSE), collapse = "\n")
}

.has <- function(haystack, needle) grepl(needle, haystack, fixed = TRUE)


# --- 1. Stylesheet dependency loading -------------------------------------

test_that("every refinement stylesheet exists in www/", {
  for (f in c("app.css", "ui-tokens.css", "ui-dialog.css",
              "ui-filters.css", "ui-glass.css", "ui-motion.css")) {
    expect_true(file.exists(file.path(.repo, "www", f)), info = f)
  }
})

test_that("app.R loads all six stylesheets", {
  app <- .read("app.R")
  for (f in c("app.css", "ui-tokens.css", "ui-dialog.css",
              "ui-filters.css", "ui-glass.css", "ui-motion.css")) {
    expect_true(.has(app, sprintf('href = "%s"', f)), info = f)
  }
})

test_that("stylesheet load order is the documented cascade", {
  # ORDER IS THE ARCHITECTURE HERE. ui-tokens.css retargets tokens app.css
  # defined; ui-glass.css must outrank the flat plates ui-dialog/ui-filters
  # set; ui-motion.css carries the reduced-motion escape and must be last so
  # no later sheet can re-enable animation. A reordering would not error --
  # it would quietly restore light surfaces or drop the motion opt-out.
  app <- .read("app.R")
  order <- c("app.css", "ui-tokens.css", "ui-dialog.css",
             "ui-filters.css", "ui-glass.css", "ui-motion.css")
  positions <- vapply(
    order,
    function(f) regexpr(sprintf('href = "%s"', f), app, fixed = TRUE)[[1]],
    numeric(1)
  )
  expect_true(all(positions > 0))
  expect_identical(order(positions), seq_along(order))
})


# --- 2. Liquid glass present on the intended major surfaces ---------------

test_that("the glass primitive and its fallbacks are defined once", {
  glass <- .read("www", "ui-glass.css")

  expect_true(.has(glass, ".psa-liquid-glass {"))
  expect_true(.has(glass, ".psa-liquid-glass::before"))
  expect_true(.has(glass, "backdrop-filter: blur("))
  expect_true(.has(glass, "-webkit-backdrop-filter: blur("))

  # NO INFORMATION THROUGH BLUR (handoff section 19). An engine without
  # backdrop-filter, and Windows high-contrast mode, must both still get an
  # opaque, edged surface rather than transparent text on transparent glass.
  expect_true(.has(glass, "@supports not ((backdrop-filter: blur(4px))"))
  expect_true(.has(glass, "@media (forced-colors: active)"))
})

test_that("the Search hero and the UI-01 sidebar are glass surfaces", {
  html <- .render(search_ui())

  expect_true(.has(html, "psa-hero-field psa-liquid-glass"))
  expect_true(.has(html, "psa-sidebar"))
  expect_true(.has(html, "psa-liquid-glass--flow"))
})

test_that("the shared dialog shell is a glass surface", {
  html <- .render(psa_dialog_ui(id = "t", title = "T", body = "B"))
  expect_true(.has(html, "psa-dialog__content psa-liquid-glass"))
})

test_that("the UI-03 dual panels are glass surfaces", {
  for (sys in c("psoc", "psic")) {
    html <- .render(dual_search_panel_ui(sys))
    expect_true(.has(html, "psa-liquid-glass"), info = sys)
  }
})

test_that("the UI-04 correspondence inspector is a glass surface", {
  html <- .render(correspondence_inspector_shell("body"))
  expect_true(.has(html, "psa-corr-inspector psa-liquid-glass"))
})

test_that("the RM Assistant card is a glass surface", {
  html <- .render(rm_assistant_unavailable_ui("not configured"))
  expect_true(.has(html, "psa-liquid-glass"))
})

test_that("Sources cards and the UI-05 disclosure carry the glass class", {
  # These two render from live registry/correspondence data, so their class
  # attachment is asserted at the source rather than by building a fixture
  # that would only re-test the data layer.
  expect_true(.has(.read("R", "ui", "ui_sources.R"),
                   'class = "psa-source-card psa-liquid-glass"'))
  expect_true(.has(.read("R", "ui", "ui_correspondence.R"),
                   "psa-term-help psa-liquid-glass"))
})

test_that("glass surfaces that host an overlay do not clip it", {
  # REGRESSION GUARD FOR UI-POST-04. The primitive sets `overflow: hidden`
  # (handoff section 6). Any surface that opens a selectize menu or a
  # bslib popover from INSIDE itself therefore has to take the --flow
  # variant, or the overlay is cut off at the surface's edge -- which is
  # exactly the "fields are overwritten / hidden" defect UI-POST-04 was
  # raised for, in a new costume.
  expect_true(.has(.read("www", "ui-glass.css"),
                   ".psa-liquid-glass--flow { overflow: visible; }"))

  expect_true(.has(.read("R", "ui", "ui_search.R"),
                   "psa-liquid-glass psa-liquid-glass--flow"))   # selectize
  expect_true(.has(.read("R", "ui", "ui_dual_search.R"),
                   "psa-liquid-glass psa-liquid-glass--flow"))   # popover
  expect_true(.has(.read("R", "ui", "ui_correspondence.R"),
                   "psa-liquid-glass psa-liquid-glass--flow"))   # popover
})


# --- 3. Identity contracts: nothing was renamed in the restyle ------------

test_that("navbar tab identities and the nav id are preserved", {
  app <- .read("app.R")
  expect_true(.has(app, 'id = "main_nav"'))
  for (v in c("search", "dual_search", "correspondence",
              "rm_assistant", "about")) {
    expect_true(.has(app, sprintf('value = "%s"', v)), info = v)
  }
})

test_that("Search input, filter and output ids are preserved", {
  html <- .render(search_ui())
  for (id in c("classification_query", "classification_system",
               "classification_version", "classification_level",
               "classification_component", "classification_results",
               "selected_entry")) {
    expect_true(.has(html, id), info = id)
  }
})

test_that("the hierarchy browser ids are preserved", {
  expect_identical(HIERARCHY_INPUT_OPEN, "hierarchy_open")
  expect_identical(HIERARCHY_INPUT_TOGGLE, "hierarchy_toggle")
  expect_identical(HIERARCHY_INPUT_SELECT, "hierarchy_select")
  expect_identical(HIERARCHY_INPUT_QUERY, "hierarchy_query")
  expect_identical(HIERARCHY_INPUT_VIEW, "hierarchy_view_in_search")
  expect_identical(HIERARCHY_OUTPUT_SLOT, "hierarchy_browse_slot")
  expect_identical(HIERARCHY_OUTPUT_TREE, "hierarchy_tree")
  expect_identical(HIERARCHY_OUTPUT_ENTRY, "hierarchy_entry")

  expect_true(.has(.render(hierarchy_browse_slot_ui()),
                   "hierarchy_browse_slot"))
})

test_that("the UI-03 details/comparison action ids are preserved", {
  expect_identical(DUAL_SEARCH_VIEW_SUFFIX, "view_details")
  expect_identical(DUAL_SEARCH_COMPARE_INPUT, "dual_search_compare_open")
  expect_identical(DUAL_SEARCH_COMPARE_OUTPUT, "dual_search_compare")

  html <- .render(dual_search_panel_ui("psoc"))
  for (suffix in c("version", "query", "count", "state", "results", "detail")) {
    expect_true(.has(html, dual_search_id("psoc", suffix)), info = suffix)
  }
})

test_that("the UI-04 inspector ids are preserved", {
  html <- .render(correspondence_inspector_shell("body"))
  expect_true(.has(html, 'id="correspondence-inspector"'))
  expect_true(.has(html, "correspondence-inspector-title"))
})

test_that("the RM Assistant module id is preserved", {
  app <- .read("app.R")
  expect_true(.has(app, '"rm_assistant"'))
  expect_true(.has(app, 'input[["rm_assistant-chat_user_input"]]'))
})


# --- 4. Accessibility survived the restyle --------------------------------

test_that("the hero keeps a real label and a real heading", {
  html <- .render(search_ui())

  # NEVER PLACEHOLDER-ONLY LABELLING (docs/UI_CONTRACT.md section 10). The
  # <label> stays in the DOM; the restyle only changes how it looks.
  expect_true(.has(html, "<label"))
  expect_true(.has(html, "Search a classification code or keyword"))

  # The panel's first heading rung is still present. It moved from
  # visually-hidden to visible; it did not disappear.
  expect_true(.has(html, "<h2"))
  expect_true(.has(html, "psa-hero-title"))
  expect_true(.has(html, "psa-hero-eyebrow"))
})

test_that("the filter sidebar keeps its accessible region label", {
  expect_true(.has(.render(search_ui()), 'aria-label="Classification filters"'))
})

test_that("the dialog shell keeps its modal semantics", {
  html <- .render(psa_dialog_ui(id = "t", title = "T", body = "B"))
  expect_true(.has(html, 'role="dialog"'))
  expect_true(.has(html, 'aria-modal="true"'))
  expect_true(.has(html, "aria-labelledby"))
})

test_that("the inspector keeps its labelled region semantics", {
  html <- .render(correspondence_inspector_shell("body"))
  expect_true(.has(html, 'role="region"'))
  expect_true(.has(html, "aria-labelledby"))
})

test_that("a visible focus ring is defined and is not colour-only", {
  tokens <- .read("www", "ui-tokens.css")
  expect_true(.has(tokens, ":focus-visible"))
  expect_true(.has(tokens, "outline:"))
  expect_true(.has(tokens, "--psa-focus"))
})

test_that("the active navigation state is not carried by colour alone", {
  # Handoff sections 8 and 19: the current tab must be distinguishable by
  # more than colour. The pill fill and the weight change are both shape
  # signals and both must survive a retune.
  glass <- .read("www", "ui-glass.css")
  # The active rule is a selector GROUP (it has to out-specify Bootstrap's
  # own `.nav-underline .nav-link:not(:empty).active`), so the block is
  # located by its closing selector rather than by the first one.
  active <- sub(".*:not\\(:empty\\)\\.active \\{", "", glass)
  active <- sub("\\}.*", "", active)
  expect_true(.has(active, "background"))
  expect_true(.has(active, "font-weight"))
})


# --- 5. Motion ------------------------------------------------------------

test_that("reduced motion is honoured globally and last in the cascade", {
  motion <- .read("www", "ui-motion.css")
  expect_true(.has(motion, "@media (prefers-reduced-motion: reduce)"))
  expect_true(.has(motion, "animation-duration: 0.01ms !important;"))
  expect_true(.has(motion, "transition-duration: 0.01ms !important;"))

  # The escape must be the LAST rule block in the file, because the file is
  # the last stylesheet loaded -- that is what makes it unconditional.
  expect_true(
    regexpr("@media (prefers-reduced-motion: reduce)", motion, fixed = TRUE) >
      regexpr("@keyframes", motion, fixed = TRUE)
  )
})

test_that("no animation framework or remote visual asset was introduced", {
  # Handoff section 20: the display font is the ONLY permitted external
  # visual dependency, and section 0 forbids the reference stack outright.
  for (f in c("ui-tokens.css", "ui-glass.css", "ui-motion.css")) {
    css <- .read("www", f)
    expect_false(.has(css, "url(http://"), info = f)
    expect_false(.has(css, ".mp4"), info = f)
    expect_false(.has(css, ".webm"), info = f)
  }

  tokens <- .read("www", "ui-tokens.css")
  remote <- regmatches(tokens, gregexpr("https://[^')]+", tokens))[[1]]
  expect_true(all(grepl("^https://fonts\\.googleapis\\.com/", remote)))
})


# --- 6. Typography: Onest only (Lumora handoff section 1) -----------------

test_that("Onest is imported and is the only face in the stack", {
  tokens <- .read("www", "ui-tokens.css")
  expect_true(.has(tokens, "family=Onest"))
  expect_true(.has(tokens, "--font-ui: 'Onest'"))

  # Display and body resolve to the SAME face: the Lumora system has no
  # separate display family, so there is no serif/sans tension to manage.
  expect_true(.has(tokens, "--font-display: var(--font-ui);"))
  expect_true(.has(tokens, "--font-sans: var(--font-ui);"))

  # The app must remain usable if Google Fonts is blocked, so the stack
  # falls through to the system sans rather than to a webfont-only face.
  expect_true(.has(tokens, "ui-sans-serif, system-ui"))
})

# CSS declarations only. The words "Instrument" and "serif" legitimately
# survive in PROSE that documents the removal ("the previous pass's display
# serif is removed outright"), and a scan that cannot tell a comment from a
# rule would either fail on its own documentation or force the documentation
# to be deleted. Comments are stripped first so the assertion is about what
# the browser actually reads.
.css_rules_only <- function(css) {
  # (?s) so `.` spans newlines -- a CSS comment block is multi-line.
  gsub("(?s)[/][*].*?[*][/]", "", css, perl = TRUE)
}

.r_code_only <- function(src) {
  paste(sub("#.*$", "", strsplit(src, "\n", fixed = TRUE)[[1]]), collapse = "\n")
}

test_that("Instrument Serif is gone from the application", {
  # The previous pass's display face is REMOVED, not demoted (section 1).
  # Checked across every stylesheet and the app shell, not just the token
  # file, so a stray leftover rule anywhere fails this.
  for (f in c("app.css", "ui-tokens.css", "ui-dialog.css",
              "ui-filters.css", "ui-glass.css", "ui-motion.css")) {
    expect_false(.has(.css_rules_only(.read("www", f)), "Instrument"), info = f)
  }
  expect_false(.has(.r_code_only(.read("app.R")), "Instrument"))

  # And no serif family is named as a display face. `sans-serif` is the
  # generic fallback keyword and is expected, so it is removed before the
  # check rather than special-cased inside it.
  for (f in c("ui-tokens.css", "ui-glass.css")) {
    css <- gsub("sans-serif", "", .css_rules_only(.read("www", f)), fixed = TRUE)
    expect_false(.has(css, "serif"), info = f)
    expect_false(.has(css, "Georgia"), info = f)
  }
})

test_that("the app shell asks bslib for Onest and no serif", {
  app <- .r_code_only(.read("app.R"))
  expect_true(.has(app, '"Onest"'))
  expect_false(.has(app, '"serif"'))
})


# --- 7. Responsive contract ------------------------------------------------

test_that("the restyle restates every breakpoint it overrides", {
  # CASCADE HAZARD, and the reason this test exists. ui-glass.css loads
  # after app.css and ui-filters.css, and a @media block adds NO
  # specificity. So a plain rule here beats an app.css mobile rule at every
  # width. Each surface whose desktop plate is restyled must therefore carry
  # its own responsive steps, or the phone layout silently reverts to
  # desktop padding.
  glass <- .read("www", "ui-glass.css")
  for (bp in c("@media (max-width: 991.98px)",
               "@media (max-width: 767.98px)",
               "@media (max-width: 575.98px)",
               "@media (min-width: 992px)")) {
    expect_true(.has(glass, bp), info = bp)
  }
})

test_that("the correspondence inspector's desktop plate is desktop-scoped", {
  # ui-filters.css turns the inspector into a fixed sheet below 992px using
  # media rules that carry no extra specificity. An unscoped plate here
  # would beat them and leave the mobile sheet mispositioned.
  glass <- .read("www", "ui-glass.css")
  desktop <- regmatches(
    glass,
    regexpr("@media \\(min-width: 992px\\) \\{[^}]*\\.psa-corr-inspector", glass)
  )
  expect_gt(length(desktop), 0)
})

test_that("no page-level horizontal overflow is introduced by the canvas", {
  tokens <- .read("www", "ui-tokens.css")
  expect_true(.has(tokens, "overflow-x: hidden"))

  # The dark pass painted a fixed ambient radial glow behind the page. The
  # light system has no ambient layer at all -- the canvas is simply white
  # and depth comes from surfaces and hairlines -- so the layer is
  # explicitly neutralised rather than left to fight the new ground. A
  # dangling `body::before` with a dark gradient would be exactly the kind
  # of leftover the handoff's section 25 warns about.
  expect_true(.has(tokens, "body::before { content: none; display: none; }"))
})


# =========================================================================
# 8. Lumora light system (UI_LUMORA_LIGHT_DESIGN_INTEGRATION_HANDOFF §28)
# =========================================================================
#
# The theme was replaced wholesale, so these assert the NEW contract in the
# same spirit as the rest of this file: semantic facts that fail silently in
# a browser, never a screenshot or a bare hex spot-check.

test_that("the Lumora palette is declared once, in the token layer", {
  tokens <- .read("www", "ui-tokens.css")
  for (tok in c("--lumora-background: #ffffff", "--lumora-foreground: #111111",
                "--lumora-ink: #0a0a0a", "--lumora-line: #e6e5e2",
                "--lumora-surface: #f1f0ee", "--lumora-accent: #b15f2c",
                "--lumora-radius-card: 2rem", "--lumora-radius-control: .875rem",
                "--lumora-radius-pill: 9999px")) {
    expect_true(.has(tokens, tok), info = tok)
  }

  # Declared in ONE place: a second :root palette in a surface sheet is how
  # a theme starts drifting from itself.
  for (f in c("ui-glass.css", "ui-filters.css", "ui-dialog.css", "ui-motion.css")) {
    expect_false(.has(.read("www", f), "--lumora-accent:"), info = f)
  }
})

test_that("the application canvas is light and its text is dark ink", {
  tokens <- .read("www", "ui-tokens.css")
  expect_true(.has(tokens, "background: var(--lumora-background);"))
  expect_true(.has(tokens, "color: var(--lumora-foreground);"))
  expect_true(.has(tokens, "color-scheme: light;"))

  # bs_theme compiles Bootstrap against the same palette. Without this the
  # navbar, DT and selectize keep rendering dark chrome under light content.
  app <- .read("app.R")
  expect_true(.has(app, 'bg = "#ffffff"'))
  expect_true(.has(app, 'fg = "#111111"'))
  expect_true(.has(app, 'primary = "#b15f2c"'))
  expect_true(.has(app, '"border-color" = "#e6e5e2"'))
})

test_that("no dark-theme surface value survives underneath the light theme", {
  # Handoff §25: do not leave conflicting dark-theme rules active beneath
  # the light one. The dark pass's signature values are the near-black
  # plates and the plum accent.
  strip <- function(f) gsub("(?s)[/][*].*?[*][/]", "", .read("www", f), perl = TRUE)
  for (f in c("ui-tokens.css", "ui-glass.css", "ui-motion.css")) {
    css <- strip(f)
    for (dead in c("#050505", "#0b0b0b", "#0d0d0d", "#8f668f", "#c9a9c9",
                   "rgba(143, 102, 143")) {
      expect_false(.has(css, dead), info = paste(f, dead))
    }
  }
})

test_that("burnt orange is the focus and accent token", {
  tokens <- .read("www", "ui-tokens.css")
  expect_true(.has(tokens, "--psa-focus: var(--lumora-accent);"))
  expect_true(.has(tokens, "outline: 2px solid var(--lumora-accent);"))
})

test_that("ink is used selectively, not as the page ground", {
  # §9: black cards are EMPHASIS against a light page. The verified
  # classification card is the one surface that earns it; the canvas, the
  # sidebar, the panels and the dialog plate must all stay light.
  glass <- .read("www", "ui-glass.css")
  expect_true(.has(glass, "background: var(--lumora-ink);"))

  block <- function(sel) {
    # Selectors here are all `.name` with hyphens only, so escaping the
    # leading dot is enough -- no general regex escaper needed.
    esc <- sub("^[.]", "[.]", sel)
    m <- regmatches(glass, regexpr(paste0(esc, "[ ][{][^}]*[}]"), glass, perl = TRUE))
    if (length(m)) m else ""
  }
  for (sel in c(".psa-sidebar", ".psa-dual-panel", ".rm-assistant-card",
                ".psa-source-card")) {
    expect_false(.has(block(sel), "--lumora-ink"), info = sel)
  }

  # Text on the ink card inverts explicitly rather than relying on
  # inheritance, and its secondary step is the measured one rather than the
  # reference's .55 alpha, which lands under AA.
  expect_true(.has(glass, ".psa-verified-card .psa-tag"))
  expect_true(.has(glass, "--lumora-muted-on-dark"))
})

test_that("the surface primitive keeps its structural contracts", {
  # The class was RENAMED IN RESPONSIBILITY, not in name: it is still the
  # thing 14 markup sites and the tests above depend on.
  glass <- .read("www", "ui-glass.css")
  expect_true(.has(glass, ".psa-liquid-glass--flow { overflow: visible; }"))
  expect_true(.has(glass, ".psa-liquid-glass--quiet"))
  expect_true(.has(glass, "position: relative;"))
  expect_true(.has(glass, ".psa-liquid-glass > * { position: relative; z-index: 1; }"))
})

test_that("primary actions are ink pills and secondary are lined white", {
  glass <- .read("www", "ui-glass.css")
  expect_true(.has(glass, "border-radius: var(--lumora-radius-pill);"))
  expect_true(.has(glass, "background: var(--lumora-ink);\n  border-color: var(--lumora-ink);"))

  # Hover transforms are gated off touch: a moving tap target is a defect.
  expect_true(.has(glass, "@media (hover: hover) and (pointer: fine)"))
})

test_that("classification codes are ink, never the low-contrast accent", {
  # Measured at 4.06:1 in accent on the warm surface -- compliant for large
  # text, and the worst treatment in the app applied to its most important
  # datum. Ink takes it to 16.58:1.
  glass <- .read("www", "ui-glass.css")
  expect_true(.has(glass, ".psa-detail-code,\n.psa-verified-code {\n  color: var(--lumora-foreground);\n}"))
})

test_that("codes and table headers never break mid-word", {
  # A code split across two lines reads as a different code. Attached at
  # the DT column definition so it follows the column, not its index.
  app <- .read("app.R")
  expect_true(.has(app, 'className = "psa-nowrap", targets = c(0, 3)'))
  expect_true(.has(app, 'className = "psa-nowrap", targets = c(0, 2, 4, 5)'))

  tokens <- .read("www", "ui-tokens.css")
  expect_true(.has(tokens, "table.dataTable thead th {\n  white-space: nowrap;\n}"))
})

test_that("secondary text mixed by alpha was raised for the light ground", {
  # app.css expresses secondary copy as color-mix at 50/55% of --color-text.
  # Those steps were AA on black and measure 3.54:1 and 4.17:1 on white.
  tokens <- .read("www", "ui-tokens.css")
  expect_true(.has(tokens, ".rm-assistant-disclaimer"))
  expect_true(.has(tokens, "color: var(--lumora-muted-text);"))
  expect_true(.has(tokens, "--lumora-muted-text: #5f5f5f;"))
})

test_that("the reference's marketing machinery was NOT imported", {
  # Handoff §0 and §20-21 rule each of these out by name. Scanned over CSS
  # RULES, not comments: this file's own prose records what was declined
  # ("no Lenis smooth-scroll hijack, no cursor-reveal canvas, no
  # 000-100 loader"), and a naive substring scan would fail on that
  # documentation -- or, worse, pressure someone into deleting it.
  strip <- function(f) gsub("(?s)[/][*].*?[*][/]", "", .read("www", f), perl = TRUE)
  rules <- paste(vapply(
    c("ui-tokens.css", "ui-glass.css", "ui-motion.css",
      "ui-filters.css", "ui-dialog.css"),
    strip, character(1)
  ), collapse = "\n")

  for (banned in c("lenis", "Lenis", "cursor-reveal")) {
    expect_false(.has(rules, banned), info = banned)
  }

  # The display font is the ONLY permitted external visual dependency, and
  # the reference's remote hero imagery is explicitly excluded.
  remote <- regmatches(rules, gregexpr("https://[^')]+", rules))[[1]]
  expect_true(all(grepl("^https://fonts[.]googleapis[.]com/", remote)))
  for (ext in c(".mp4", ".webm", ".jpg", ".png")) {
    expect_false(.has(rules, ext), info = ext)
  }

  # No front-end framework was introduced. Asserted at the DEPENDENCY
  # boundary rather than by substring: "react" is a substring of Shiny's
  # own `reactive()`, which appears throughout app.R, so a text scan there
  # is a false-positive generator. What actually matters is that no new
  # package and no new script were added.
  expect_false(any(grepl("[.]js$", list.files(file.path(.repo, "www")))))
  expect_false(.has(.r_code_only(.read("app.R")), "htmlDependency"))
})
