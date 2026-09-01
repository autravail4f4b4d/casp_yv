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


# --- 6. Typography rules from handoff section 4 ---------------------------

test_that("the display serif has a local fallback and is import-only", {
  tokens <- .read("www", "ui-tokens.css")
  expect_true(.has(tokens, "Instrument+Serif"))
  expect_true(.has(tokens, "'Instrument Serif', Georgia, 'Times New Roman', serif"))
  # The app must remain usable if Google Fonts is blocked, so the UI face is
  # never the imported one.
  expect_true(.has(tokens, "--font-ui:"))
  expect_true(.has(tokens, "--font-sans: var(--font-ui);"))
})

test_that("classification data surfaces are not set in the display serif", {
  # Handoff section 4 forbids the serif for codes, result tables, filters,
  # forms, buttons, RM transcript copy and metadata. app.css routes its
  # --type-heading-* tokens through --font-display, which now resolves to
  # the serif, so those data surfaces are pinned back explicitly.
  tokens <- .read("www", "ui-tokens.css")
  pinned <- sub(".*PINNED BACK TO THE UI FACE\\.", "", tokens)
  pinned <- sub("font-family: var\\(--font-ui\\);.*", "", pinned)

  for (sel in c(".psa-detail-title", ".psa-hier-code", ".psa-hier-label",
                "table.dataTable", ".form-control", ".btn", "label",
                ".psa-verified-card")) {
    expect_true(.has(pinned, sel), info = sel)
  }
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
  # The ambient layer is fixed and inert: it can neither be hit-tested nor
  # extend the document box.
  expect_true(.has(tokens, "position: fixed"))
  expect_true(.has(tokens, "pointer-events: none"))
})
