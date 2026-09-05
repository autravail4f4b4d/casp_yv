# UAT Pass 2 — the two MEDIUM polish defects.
#
#   UAT2-UI-02  the System control and its dropdown rows were cramped
#   UAT2-RM-03  decorative SVGs leaked the literal "svg" into accessibility
#               output
#
# Both are pinned by the facts that were measured on the live DOM, not by
# eyeballed numbers.

.repo3 <- normalizePath(file.path(getwd(), "..", ".."), mustWork = TRUE)

.read3 <- function(...) {
  path <- file.path(.repo3, ...)
  expect_true(file.exists(path), info = paste("missing file:", path))
  paste(readLines(path, warn = FALSE), collapse = "\n")
}

# CSS with block comments stripped — (?s) so `.` crosses newlines, otherwise
# the prose explaining a defect stays in the string and can satisfy an
# assertion about the rules.
.css3 <- function(file) {
  gsub("(?s)/\\*.*?\\*/", "", .read3("www", file), perl = TRUE)
}

.rule3 <- function(css, selector) {
  m <- regmatches(css, regexpr(paste0(selector, "\\s*\\{[^}]*\\}"), css, perl = TRUE))
  if (length(m) == 0L) "" else m
}

# A selector can appear both on its own and as one line of a GROUPED rule,
# so "the first block whose selector matches" is not necessarily the block
# being asserted about. `must_contain` picks the intended one by a property
# only that block declares.
.own_rule3 <- function(css, selector, must_contain) {
  blocks <- regmatches(
    css, gregexpr(paste0(selector, "\\s*\\{[^}]*\\}"), css, perl = TRUE)
  )[[1]]
  hit <- blocks[grepl(must_contain, blocks, fixed = TRUE)]
  if (length(hit) == 0L) "" else hit[[1]]
}


# ===========================================================================
# UAT2-UI-02 — the System control breathes
# ===========================================================================

test_that("the selected System control is a flex row, not a stack", {
  # MEASURED ROOT CAUSE. `.selectize-input` is an inline-block holding the
  # rendered `.item` AND selectize's own 4px typing <input>. In block flow
  # that input took a whole line of its own directly under the item:
  #
  #   PSGC  item 8 -> 40.7,  input 40.7 -> 59.5,  clientH 47, scrollH 58
  #   PSOC  item 8 -> 55.7,  input 55.7 -> 74.4,  clientH 62, scrollH 73
  #
  # so the box was sized by an invisible input rather than by its text and
  # the title had only the 7px padding before the border. A flex row puts
  # the item and the sliver on one line.
  css <- .css3("ui-filters.css")
  rule <- .rule3(css, "\\.psa-system-field \\.selectize-input")
  expect_true(grepl("display: flex", rule, fixed = TRUE))
  expect_true(grepl("align-items: center", rule, fixed = TRUE))
  # The sliver must be told not to claim a line.
  expect_true(grepl(".psa-system-field .selectize-input > input", css, fixed = TRUE))
})

test_that("the System trigger has comfortable padding and a real subtitle gap", {
  css <- .css3("ui-filters.css")
  trigger <- .rule3(css, "\\.psa-system-field \\.selectize-input")

  # Padding: 7px was the cramped value the defect reported.
  pad <- regmatches(trigger, regexpr("padding-block:\\s*([0-9.]+)px", trigger, perl = TRUE))
  expect_gt(length(pad), 0L)
  pad_px <- as.numeric(sub("[^0-9.]*([0-9.]+)px", "\\1", pad))
  expect_gte(pad_px, 9)

  # Acronym -> subtitle gap: the handoff asks for 3-5px; it was 1px, which
  # read as one wrapped line rather than as a label and its subtitle.
  line <- .rule3(css, "\\.psa-sys-line")
  gap <- regmatches(line, regexpr("gap:\\s*([0-9.]+)px", line, perl = TRUE))
  expect_gt(length(gap), 0L)
  gap_px <- as.numeric(sub("[^0-9.]*([0-9.]+)px", "\\1", gap))
  expect_gte(gap_px, 3)
  expect_lte(gap_px, 5)

  # Subtitle line-height in the 1.25-1.35 band.
  title <- .rule3(css, "\\.psa-sys-title")
  lh <- regmatches(title, regexpr("line-height:\\s*([0-9.]+)", title, perl = TRUE))
  expect_gt(length(lh), 0L)
  lh_ratio <- as.numeric(sub("[^0-9.]*([0-9.]+)", "\\1", lh))
  expect_gte(lh_ratio, 1.25)
  expect_lte(lh_ratio, 1.35)
})

test_that("a wrapped subtitle is supported rather than truncated", {
  # The long official titles are the whole point of this control. app.css
  # clips selectize text to stop the widest option widening the page; the
  # System field opts out so the control grows downwards instead.
  css <- .css3("ui-filters.css")
  title <- .rule3(css, "\\.psa-sys-title")
  expect_true(grepl("white-space: normal", title, fixed = TRUE))
  expect_true(grepl("overflow-wrap: anywhere", title, fixed = TRUE))
  expect_false(grepl("text-overflow: ellipsis", title, fixed = TRUE))

  # And the control itself wraps rather than clipping.
  expect_true(grepl(".psa-system-field .selectize-input,", css, fixed = TRUE))
  wrap <- .rule3(css, "\\.psa-system-field \\.selectize-input,\\s*\\.psa-system-field \\.selectize-dropdown-content \\.psa-sys-opt")
  expect_true(grepl("white-space: normal", wrap, fixed = TRUE))
  expect_true(grepl("height: auto", wrap, fixed = TRUE))
})

test_that("no rule fixes the System control to a single-line height", {
  # `height: auto` is the contract. A fixed height is what would clip a
  # two-line title, and it must not come back.
  css <- .css3("ui-filters.css")
  for (sel in c("\\.psa-system-field \\.selectize-input",
                "\\.psa-sys-line", "\\.psa-sys-title")) {
    rule <- .rule3(css, sel)
    expect_false(grepl("(^|[^-])height:\\s*[0-9]", rule, perl = TRUE), info = sel)
  }
})

test_that("dropdown rows are styled by the class the renderer actually emits", {
  # MEASURED ROOT CAUSE. The System control uses a custom selectize
  # `render.option`; selectize keeps the renderer's own class list and adds
  # only `selected`/`active`. It never adds `option`. Live measurement of
  # all ten rows before the fix: `padding: 0px`, no `option` class, text 1px
  # from the panel wall, 0px between adjacent rows. Every rule written
  # against `.selectize-dropdown .option` matched nothing for this control.
  css <- .css3("ui-filters.css")
  expect_false(grepl(".psa-system-field .selectize-dropdown-content .option",
                     css, fixed = TRUE))

  row <- .own_rule3(css, "\\.psa-system-field \\.selectize-dropdown-content \\.psa-sys-opt", "padding:")
  pad <- regmatches(row, regexpr("padding:\\s*([0-9.]+)px\\s+([0-9.]+)px", row, perl = TRUE))
  expect_gt(length(pad), 0L)
  nums <- as.numeric(regmatches(pad, gregexpr("[0-9.]+", pad))[[1]])
  expect_gte(nums[[1]], 8)   # vertical
  expect_gte(nums[[2]], 10)  # horizontal

  # The panel gets side walls too, so a padded row is not flush to the edge.
  panel <- .rule3(css, "\\.psa-system-field \\.selectize-dropdown \\.selectize-dropdown-content")
  expect_true(grepl("padding: 5px", panel, fixed = TRUE))
})

test_that("dropdown rows grow for multiline names and never clip", {
  css <- .css3("ui-filters.css")
  row <- .own_rule3(css, "\\.psa-system-field \\.selectize-dropdown-content \\.psa-sys-opt", "padding:")
  # Content-driven: no height, no max-height, no overflow trap on the row.
  expect_false(grepl("height:", row, fixed = TRUE))
  expect_false(grepl("overflow: hidden", row, fixed = TRUE))
  expect_false(grepl("white-space: nowrap", row, fixed = TRUE))

  # Scrolling stays where it belongs -- on the panel, not the row.
  app <- .css3("app.css")
  expect_true(grepl("overflow-y: auto", app, fixed = TRUE))
  expect_true(grepl("max-height: min(200px, 45vh)", app, fixed = TRUE))
})

test_that("the hover and selected states reach the rows they describe", {
  # The dead `.option` selectors left the vendor default painting the
  # keyboard-cursor row -- rgb(17,17,17), all but invisible on this surface.
  css <- .css3("ui-filters.css")
  expect_true(grepl(".psa-sys-opt:hover,", css, fixed = TRUE))
  expect_true(grepl(".psa-sys-opt.active {", css, fixed = TRUE))
  expect_true(grepl(".psa-sys-opt.selected {", css, fixed = TRUE))
  expect_true(grepl(".psa-sys-opt.selected.active {", css, fixed = TRUE))
})

test_that("system ids, order and the mobile sheet are untouched", {
  # The polish pass is presentation only. The registry still decides what
  # the control offers and in what order.
  registry <- classification_registry()
  choices <- system_choice_vector(registry)
  expect_identical(unname(choices), as.character(registry$id))
  expect_identical(names(choices),
                   system_choice_label(registry$short_name, registry$display_name))

  # The mobile sheet is still built from the FULL registry, and the
  # breakpoint that swaps the two surfaces is unchanged.
  html <- paste(as.character(htmltools::renderTags(
    system_picker_list_ui(registry, selected = registry$id[[1]])
  )$html), collapse = "")
  for (id in registry$id) expect_true(grepl(id, html, fixed = TRUE), info = id)

  design <- .css3("ui-design.css")
  expect_true(grepl("@media (max-width: 767.98px)", design, fixed = TRUE))
  expect_true(grepl(".psa-system-select { display: none; }", design, fixed = TRUE))
})


# ===========================================================================
# UAT2-RM-03 — decorative icons say nothing
# ===========================================================================

test_that("this application's own icons are already correct", {
  # lucide_icon() is the only icon factory in this codebase, and every
  # glyph it emits is decorative by contract.
  for (name in names(LUCIDE_PATHS)) {
    svg <- as.character(lucide_icon(name, 16))
    expect_true(grepl('aria-hidden="true"', svg, fixed = TRUE), info = name)
    expect_true(grepl('focusable="false"', svg, fixed = TRUE), info = name)
    # No <title>, no aria-label: a decorative glyph must contribute no name.
    expect_false(grepl("<title", svg, fixed = TRUE), info = name)
    expect_false(grepl("aria-label", svg, fixed = TRUE), info = name)
  }
})

test_that("the sidecar hardens the decorative SVGs it does not own", {
  # THE ACTUAL LEAK. The icons that reach the accessibility tree unnamed are
  # SHINYCHAT'S, shipped inside the chat element this panel mounts --
  # bi-arrow-up-circle-fill (send), bi-stop-circle-fill (cancel), bi-robot
  # (assistant message), bi-x-lg (close) and the loading dots, none of which
  # carry aria-hidden. An <svg> with no role and no accessible name is still
  # a node in the accessibility tree, serialised by its element name, which
  # is the literal "svg" that was reported.
  #
  # shinychat exposes no option for this and is not forked, so the panel
  # hardens its own subtree.
  src <- .read3("R", "ui", "ui_sidecar.R")
  expect_true(grepl("hideDecorativeIcons", src, fixed = TRUE))
  expect_true(grepl('s.setAttribute("aria-hidden", "true")', src, fixed = TRUE))
  expect_true(grepl('s.setAttribute("focusable", "false")', src, fixed = TRUE))

  # It must run again as the chat re-renders: the stop button replaces the
  # send button mid-stream and assistant messages arrive with their own
  # icon, so a single pass at load would harden only what existed at load.
  expect_true(grepl("MutationObserver", src, fixed = TRUE))
  expect_true(grepl("subtree: true", src, fixed = TRUE))
})

test_that("an SVG that carries its own name is never hidden", {
  # The pass is deliberately conservative: hiding a meaningful graphic would
  # be a worse accessibility defect than the one being fixed.
  src <- .read3("R", "ui", "ui_sidecar.R")
  named <- regmatches(
    src, regexpr("function named\\(svg\\)[^}]*\\}", src, perl = TRUE)
  )
  expect_gt(length(named), 0L)
  expect_true(grepl('hasAttribute("aria-label")', named, fixed = TRUE))
  expect_true(grepl('hasAttribute("aria-labelledby")', named, fixed = TRUE))
  expect_true(grepl('querySelector("title")', named, fixed = TRUE))
})

test_that("every icon-only control in the sidecar has an accessible name", {
  # The icon must never be the accessible name. These are the controls the
  # handoff names, asserted on the markup this file produces.
  chip <- paste(as.character(htmltools::renderTags(
    rm_context_chip_ui(list(
      `entry:psoc:2022:1112` = list(
        label = "1112 · SENIOR GOVERNMENT OFFICIALS · PSOC 2022",
        descriptor = assistant_context_descriptor_entry("psoc", "2022", "1112")
      )
    ))
  )$html), collapse = "")
  expect_true(grepl(
    'aria-label="Remove attached context: 1112 · SENIOR GOVERNMENT OFFICIALS · PSOC 2022"',
    chip, fixed = TRUE
  ))

  panel <- paste(as.character(htmltools::renderTags(
    rm_sidecar_ui(list(enabled = TRUE, available = TRUE))
  )$html), collapse = "")
  expect_true(grepl("Close the RM Assistant panel", panel, fixed = TRUE))
})

test_that("no icon in the sidecar contributes literal text", {
  # Nothing this file renders may put a bare <svg> into the panel without
  # aria-hidden, and no icon may carry text content of its own.
  panel <- paste(as.character(htmltools::renderTags(
    rm_sidecar_ui(list(enabled = TRUE, available = TRUE))
  )$html), collapse = "")
  # The panel carries its own behaviour script, whose comments quote the
  # shinychat markup this pass exists to harden. That is prose about SVGs,
  # not rendered SVGs, so it is removed before the markup is scanned.
  markup <- gsub("(?s)<script.*?</script>", "", panel, perl = TRUE)

  svgs <- regmatches(markup, gregexpr("<svg[^>]*>", markup, perl = TRUE))[[1]]
  expect_gt(length(svgs), 0L)
  for (tag in svgs) {
    expect_true(grepl('aria-hidden="true"', tag, fixed = TRUE), info = tag)
    expect_true(grepl('focusable="false"', tag, fixed = TRUE), info = tag)
  }
  # `htmltools` strips nothing here, so a <title> or text node inside an
  # icon would show up in the rendered markup.
  expect_false(grepl("<title", markup, fixed = TRUE))
})
