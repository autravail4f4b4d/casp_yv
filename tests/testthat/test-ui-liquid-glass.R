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
              "ui-filters.css", "ui-glass.css", "ui-design.css",
              "ui-motion.css")) {
    expect_true(file.exists(file.path(.repo, "www", f)), info = f)
  }
})

test_that("app.R loads all seven stylesheets", {
  app <- .read("app.R")
  for (f in c("app.css", "ui-tokens.css", "ui-dialog.css",
              "ui-filters.css", "ui-glass.css", "ui-design.css",
              "ui-motion.css")) {
    expect_true(.has(app, sprintf('href = "%s"', f)), info = f)
  }
})

test_that("stylesheet load order is the documented cascade", {
  # ORDER IS THE ARCHITECTURE HERE. ui-tokens.css retargets tokens app.css
  # defined; ui-glass.css must outrank the flat plates ui-dialog/ui-filters
  # set; ui-motion.css carries the reduced-motion escape and must be last so
  # no later sheet can re-enable animation. A reordering would not error --
  # it would quietly restore superseded surfaces, put the imported design's
  # layout underneath the rules it replaces, or drop the motion opt-out.
  app <- .read("app.R")
  order <- c("app.css", "ui-tokens.css", "ui-dialog.css",
             "ui-filters.css", "ui-glass.css", "ui-design.css",
             "ui-motion.css")
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
  # The FOUR workspace destinations. Every `req(input$main_nav == ...)` gate
  # in the server reads one of these, so a rename here silently detaches an
  # output rather than erroring.
  for (v in c("search", "dual_search", "correspondence", "about")) {
    expect_true(.has(app, sprintf('value = "%s"', v)), info = v)
  }

  # RM is deliberately NOT one of them any more (imported design, surface
  # 1l): it is a contextual panel mounted once per page, not a place you
  # navigate to. Asserted rather than merely dropped, because re-adding the
  # tab would silently give the app two mounts of the same shinychat id.
  expect_false(.has(app, 'value = "rm_assistant"'))
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

  # The imported design REMOVES the hero band: no eyebrow, no wash, no
  # centred display treatment -- just the page title, one line of help and
  # the search field. The heading and the label above are what had to
  # survive that; the decorative eyebrow did not.
  expect_false(.has(html, "psa-hero-eyebrow"))
  expect_true(.has(html, "psa-hero--page"))
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
# 8. Imported Claude Design appearance ("PSA Classifications Redesign")
# =========================================================================
#
# The appearance was replaced wholesale, so these assert the NEW contract in
# the same spirit as the rest of this file: semantic facts that fail
# silently in a browser, never a screenshot or a bare hex spot-check.
#
# The design artifact is a single dark appearance. What these tests pin is
# that it is expressed as TOKENS in one place, that the alias layer every
# other stylesheet reads resolves to those tokens, and that no theme
# SWITCHING was introduced -- that was explicitly deferred.

test_that("the design palette is declared once, as semantic tokens", {
  tokens <- .read("www", "ui-tokens.css")
  for (tok in c("--ui-canvas: #0c0c0c", "--ui-surface: #111111",
                "--ui-surface-muted: #0d0d0d", "--ui-surface-elevated: #0a0a0a",
                "--ui-text: #fafafa", "--ui-accent: #78d0cd",
                "--ui-primary-bg: #ffffff", "--ui-primary-text: #0c0c0c",
                "--ui-border: rgba(255, 255, 255, 0.065)",
                "--ui-border-strong: rgba(255, 255, 255, 0.18)",
                "--lumora-radius-card: 2rem", "--lumora-radius-control: .875rem",
                "--lumora-radius-pill: 9999px")) {
    expect_true(.has(tokens, tok), info = tok)
  }

  # Declared in ONE place: a second :root palette in a surface or layout
  # sheet is how an appearance starts drifting from itself.
  for (f in c("ui-glass.css", "ui-filters.css", "ui-dialog.css",
              "ui-motion.css", "ui-design.css")) {
    expect_false(.has(.read("www", f), "--ui-canvas:"), info = f)
    expect_false(.has(.read("www", f), "--lumora-accent:"), info = f)
  }
})

test_that("the older token names are an alias layer over the design tokens", {
  # This is what let a whole-appearance replacement stay a token edit: ~150
  # rules across four stylesheets read the --lumora-* / --psa-* names, and
  # those names are REPOINTED rather than renamed.
  tokens <- .read("www", "ui-tokens.css")
  for (alias in c("--lumora-background: var(--ui-canvas);",
                  "--lumora-foreground: var(--ui-text);",
                  "--lumora-surface: var(--ui-surface);",
                  "--lumora-line: var(--ui-border);",
                  "--lumora-accent: var(--ui-accent);",
                  "--psa-bg: var(--ui-canvas);",
                  "--psa-panel: var(--ui-surface);",
                  "--psa-focus: var(--ui-focus);")) {
    expect_true(.has(tokens, alias), info = alias)
  }
})

test_that("no theme switching was implemented", {
  # Explicitly deferred: semantic tokens now, the second appearance later.
  # A stray prefers-color-scheme block or [data-theme] selector would mean
  # the app silently has two half-built appearances, which is worse than
  # one finished one. Scanned over RULES, not comments -- this file and the
  # sheets themselves document the deferral in prose.
  strip <- function(f) gsub("(?s)[/][*].*?[*][/]", "", .read("www", f), perl = TRUE)
  for (f in c("app.css", "ui-tokens.css", "ui-glass.css", "ui-filters.css",
              "ui-dialog.css", "ui-design.css", "ui-motion.css")) {
    css <- strip(f)
    expect_false(.has(css, "prefers-color-scheme"), info = f)
    expect_false(.has(css, "[data-theme"), info = f)
  }
  # And no toggle control anywhere in the UI layer.
  for (f in list.files(file.path(.repo, "R", "ui"), full.names = TRUE)) {
    src <- paste(readLines(f, warn = FALSE), collapse = "\n")
    expect_false(grepl("theme_toggle|toggle_theme|input_dark_mode", src), info = basename(f))
  }
})

test_that("the application canvas is the design's dark ground", {
  tokens <- .read("www", "ui-tokens.css")
  expect_true(.has(tokens, "background: var(--ui-canvas);"))
  expect_true(.has(tokens, "color: var(--lumora-foreground);"))
  expect_true(.has(tokens, "color-scheme: dark;"))

  # bs_theme compiles Bootstrap against the same values. Without this the
  # navbar, DT and selectize keep rendering the previous chrome under the
  # new content -- and the .btn-close / hamburger data-URI glyphs, which
  # are compiled from `fg`, come out invisible.
  app <- .read("app.R")
  expect_true(.has(app, 'bg = "#0c0c0c"'))
  expect_true(.has(app, 'fg = "#fafafa"'))
  expect_true(.has(app, 'primary = "#78d0cd"'))
  expect_true(.has(app, '"card-bg" = "#111111"'))
})

test_that("no superseded light-appearance value survives underneath", {
  # Do not leave conflicting rules from the previous appearance active
  # beneath this one. Its signature values were the white/cream grounds and
  # the burnt-orange accent.
  strip <- function(f) gsub("(?s)[/][*].*?[*][/]", "", .read("www", f), perl = TRUE)
  for (f in c("ui-tokens.css", "ui-glass.css", "ui-motion.css", "ui-design.css")) {
    css <- strip(f)
    for (dead in c("#f1f0ee", "#e6e5e2", "#b15f2c", "#97501f", "#cf8047",
                   "#5f5f5f", "rgba(177, 95, 44")) {
      expect_false(.has(css, dead), info = paste(f, dead))
    }
  }
})

test_that("the accent is a state colour and the primary action is the pill", {
  # The artifact's own legend: the gradient/teal accent marks STATE
  # (selection rails, eyebrows, focus) and the primary action is a white
  # pill with near-black text. Those are two different jobs and must not
  # collapse into one.
  tokens <- .read("www", "ui-tokens.css")
  expect_true(.has(tokens, "--psa-focus: var(--ui-focus);"))
  expect_true(.has(tokens, "outline: 2px solid var(--lumora-accent);"))

  glass <- .read("www", "ui-glass.css")
  expect_true(.has(glass, "background: var(--ui-primary-bg);\n  border-color: var(--ui-primary-bg);"))
  expect_true(.has(glass, "color: var(--ui-primary-text);"))
})

test_that("the verified classification card stays the most emphatic surface", {
  # It is no longer an INVERTED plate -- on this ground the inverted plate
  # is the primary button, and the two must not read as the same object.
  # It earns its standing from an elevated ground, a brighter border and a
  # shadow instead.
  glass <- .read("www", "ui-glass.css")
  block <- function(sel) {
    esc <- sub("^[.]", "[.]", sel)
    m <- regmatches(glass, regexpr(paste0(esc, "[ ][{][^}]*[}]"), glass, perl = TRUE))
    if (length(m)) m else ""
  }
  card <- block(".psa-verified-card")
  expect_true(.has(card, "border: 1px solid var(--ui-border-strong);"))
  expect_true(.has(card, "background: var(--ui-surface);"))
  expect_true(.has(card, "box-shadow: var(--elev-2);"))

  # The ordinary panels must NOT borrow that treatment, or nothing on the
  # page reads as the answer.
  for (sel in c(".psa-sidebar", ".psa-dual-panel", ".rm-assistant-card",
                ".psa-source-card")) {
    expect_false(.has(block(sel), "--ui-border-strong"), info = sel)
  }
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

test_that("primary actions are pills and hover transforms are gated off touch", {
  glass <- .read("www", "ui-glass.css")
  expect_true(.has(glass, "border-radius: var(--lumora-radius-pill);"))
  # A moving tap target is a defect.
  expect_true(.has(glass, "@media (hover: hover) and (pointer: fine)"))
})

test_that("classification codes are full-strength text, never the accent", {
  # The accent is a state colour; a headline code is not a state marker,
  # and the accent is the least legible treatment in the system.
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

test_that("functional secondary text clears AA on the dark ground", {
  # The artifact's own #6b6b6d micro-label grey measures 3.6:1 on #111111.
  # It is deliberately NOT adopted as a text token: --ui-text-subtle is
  # #8b8b8d (5.5:1 on surface) and --ui-text-muted is #9e9e9e (7.1:1).
  tokens <- .read("www", "ui-tokens.css")
  expect_true(.has(tokens, ".rm-assistant-disclaimer"))
  expect_true(.has(tokens, "color: var(--lumora-muted-text);"))
  expect_true(.has(tokens, "--ui-text-muted: #9e9e9e;"))
  expect_true(.has(tokens, "--ui-text-subtle: #8b8b8d;"))

  strip <- function(f) gsub("(?s)[/][*].*?[*][/]", "", .read("www", f), perl = TRUE)
  for (f in c("ui-tokens.css", "ui-glass.css", "ui-design.css")) {
    expect_false(.has(strip(f), "#6b6b6d"), info = f)
  }
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
