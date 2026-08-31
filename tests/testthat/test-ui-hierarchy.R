# UI-02 hierarchy browser.
#
# The rule this file exists to protect: the browser may only draw
# relationships PSA actually published. Two ways that could go wrong are
# tested directly -- offering a tree for a system that has none (PTSCS /
# PSCrCS, which group thematically and mint no codes), and drawing an edge
# to a parent code that does not exist in the edition.

.render <- function(tag) as.character(htmltools::renderTags(tag)$html)

.attr_values <- function(html, attr) {
  m <- gregexpr(paste0(attr, '="[^"]*"'), html)[[1]]
  if (identical(as.integer(m)[1], -1L)) return(character(0))
  raw <- regmatches(html, gregexpr(paste0(attr, '="[^"]*"'), html))[[1]]
  sub(paste0("^", attr, '="'), "", sub('"$', "", raw))
}


# ---------------------------------------------------------------------
# Eligibility is derived, never hardcoded
# ---------------------------------------------------------------------

test_that("genuinely hierarchical systems are eligible", {
  expect_true(hierarchy_is_eligible("psic", "2026"))
  expect_true(hierarchy_is_eligible("psoc", "2022"))
  expect_true(hierarchy_is_eligible("psgc"))
  expect_true(hierarchy_is_eligible("pscc", "2022"))
})

test_that("composite/thematic systems are NOT forced into a tree", {
  # PTSCS and PSCrCS select codes out of PSIC/CPC/PSOC and group them by
  # component. Every record is a root; there is no canonical parent-child
  # structure to browse, and inventing one would be fabricated hierarchy.
  expect_false(hierarchy_is_eligible("ptscs"))
  expect_false(hierarchy_is_eligible("pscrcs"))

  eligible <- hierarchy_eligible_systems()
  expect_false("ptscs" %in% eligible)
  expect_false("pscrcs" %in% eligible)
  expect_true(all(c("psic", "psoc", "psgc", "pscc") %in% eligible))
})

.current_version <- function(system) {
  reg <- classification_registry()
  reg$current_version[reg$id == system][[1]]
}

test_that("eligibility reflects the data, not a system-id allowlist", {
  # Every eligible system+version must actually contain roots AND at least
  # one child that resolves to a real parent in the same edition.
  for (sys in hierarchy_eligible_systems()) {
    v <- .current_version(sys)
    roots <- hierarchy_children(sys, v)
    expect_gt(nrow(roots), 0L)
    kids <- hierarchy_children(sys, v, roots$code[[1]])
    expect_gt(nrow(kids), 0L)
  }
})

test_that("unknown or malformed system ids are ineligible rather than erroring", {
  expect_false(hierarchy_is_eligible("not_a_system"))
  expect_false(hierarchy_is_eligible(NULL))
  expect_false(hierarchy_is_eligible(NA_character_))
  expect_false(hierarchy_is_eligible("psic", "1999"))
})


# ---------------------------------------------------------------------
# Navigation reflects published parent_code only
# ---------------------------------------------------------------------

test_that("children of a node all name that node as their parent", {
  roots <- hierarchy_children("psoc", "2022")
  expect_gt(nrow(roots), 0L)
  expect_true(all(is.na(roots$parent_code)))

  kids <- hierarchy_children("psoc", "2022", roots$code[[1]])
  expect_gt(nrow(kids), 0L)
  expect_true(all(kids$parent_code == roots$code[[1]]))
})

test_that("ancestors are the published chain, root first", {
  roots <- hierarchy_children("psic", "2026")
  lvl2 <- hierarchy_children("psic", "2026", roots$code[[1]])
  skip_if(nrow(lvl2) == 0L, "no second level in this edition")
  lvl3 <- hierarchy_children("psic", "2026", lvl2$code[[1]])
  skip_if(nrow(lvl3) == 0L, "no third level in this edition")

  anc <- hierarchy_ancestors("psic", "2026", lvl3$code[[1]])
  expect_equal(anc, c(roots$code[[1]], lvl2$code[[1]]))
  # The node itself is never in its own ancestor list.
  expect_false(lvl3$code[[1]] %in% anc)
})

test_that("a root has no ancestors", {
  roots <- hierarchy_children("psoc", "2022")
  expect_length(hierarchy_ancestors("psoc", "2022", roots$code[[1]]), 0L)
})


# ---------------------------------------------------------------------
# Lazy expansion
# ---------------------------------------------------------------------

test_that("only top-level nodes are rendered before anything is expanded", {
  roots <- hierarchy_children("psoc", "2022")
  html <- .render(hierarchy_tree_ui("psoc", "2022"))

  n_nodes <- length(gregexpr("psa-hier-node", html, fixed = TRUE)[[1]])
  expect_equal(n_nodes, nrow(roots))
  for (cd in roots$code) {
    expect_true(grepl(paste0('data-code="', cd, '"'), html, fixed = TRUE))
  }
})

test_that("expanding a node renders exactly that node's children", {
  roots <- hierarchy_children("psoc", "2022")
  root <- roots$code[[1]]
  kids <- hierarchy_children("psoc", "2022", root)

  html <- .render(hierarchy_tree_ui("psoc", "2022", expanded = root))
  for (cd in kids$code) {
    expect_true(grepl(paste0('data-code="', cd, '"'), html, fixed = TRUE))
  }
  # A sibling root stays collapsed -- expansion is per node, not global.
  sibling_kids <- hierarchy_children("psoc", "2022", roots$code[[2]])
  expect_false(grepl(paste0('data-code="', sibling_kids$code[[1]], '"'),
                     html, fixed = TRUE))
})


# ---------------------------------------------------------------------
# Accessible expand/collapse state
# ---------------------------------------------------------------------

test_that("every expandable node exposes aria-expanded", {
  roots <- hierarchy_children("psoc", "2022")
  html <- .render(hierarchy_tree_ui("psoc", "2022"))

  states <- .attr_values(html, "aria-expanded")
  expect_gt(length(states), 0L)
  expect_true(all(states == "false"))

  # Each toggle also points at the list it controls and names the node.
  expect_true(grepl("aria-controls=", html, fixed = TRUE))
  labels <- .attr_values(html, "aria-label")
  expect_true(any(grepl("^Expand ", labels)))
})

test_that("aria-expanded flips to true for the expanded node only", {
  roots <- hierarchy_children("psoc", "2022")
  html <- .render(hierarchy_tree_ui("psoc", "2022", expanded = roots$code[[1]]))
  states <- .attr_values(html, "aria-expanded")
  expect_equal(sum(states == "true"), 1L)
  expect_true(any(grepl("^Collapse ", .attr_values(html, "aria-label"))))
})

test_that("the tree is built from real buttons, not clickable divs", {
  html <- .render(hierarchy_tree_ui("psoc", "2022"))
  toggles <- regmatches(
    html, gregexpr("<[a-z]+[^>]*psa-hier-toggle[^>]*>", html)
  )[[1]]
  labels <- regmatches(
    html, gregexpr("<[a-z]+[^>]*psa-hier-label[^>]*>", html)
  )[[1]]
  expect_gt(length(toggles), 0L)
  expect_gt(length(labels), 0L)
  expect_true(all(grepl("^<button", toggles)))
  expect_true(all(grepl("^<button", labels)))
})

test_that("selection is exposed as aria-current, not colour alone", {
  roots <- hierarchy_children("psoc", "2022")
  html <- .render(hierarchy_tree_ui("psoc", "2022", selected = roots$code[[2]]))
  expect_true(grepl('aria-current="true"', html, fixed = TRUE))
  expect_true(grepl("psa-hier-node--selected", html, fixed = TRUE))
})


# ---------------------------------------------------------------------
# Local search reveals matches WITH their ancestors
# ---------------------------------------------------------------------

test_that("local search returns every match's ancestors in the reveal set", {
  res <- hierarchy_local_search("psic", "2026", "manufacture")
  skip_if(length(res$matches) == 0L, "no 'manufacture' match in this edition")

  for (cd in res$matches) {
    anc <- hierarchy_ancestors("psic", "2026", cd)
    expect_true(all(anc %in% res$reveal))
    expect_true(cd %in% res$reveal)
  }
})

test_that("the revealed tree actually renders the ancestors of a deep match", {
  # Pick a genuinely deep node and search for its exact code, so the match
  # set is small and the ancestor chain is known.
  roots <- hierarchy_children("psic", "2026")
  lvl2 <- hierarchy_children("psic", "2026", roots$code[[1]])
  skip_if(nrow(lvl2) == 0L, "no second level")
  lvl3 <- hierarchy_children("psic", "2026", lvl2$code[[1]])
  skip_if(nrow(lvl3) == 0L, "no third level")
  target <- lvl3$code[[1]]

  res <- hierarchy_local_search("psic", "2026", target)
  expect_true(target %in% res$matches)

  html <- .render(hierarchy_tree_ui(
    "psic", "2026",
    expanded = hierarchy_ancestors("psic", "2026", target),
    matches = res$matches,
    reveal = res$reveal
  ))

  # The match is visible, and so is every branch above it.
  expect_true(grepl(paste0('data-code="', target, '"'), html, fixed = TRUE))
  for (cd in hierarchy_ancestors("psic", "2026", target)) {
    expect_true(grepl(paste0('data-code="', cd, '"'), html, fixed = TRUE))
  }
  # A hit is labelled in text, not only tinted.
  expect_true(grepl("psa-hier-badge", html, fixed = TRUE))
  expect_true(grepl(">Match<", html, fixed = TRUE))
})

test_that("an empty query is not a search", {
  res <- hierarchy_local_search("psoc", "2022", "")
  expect_length(res$matches, 0L)
  expect_length(res$reveal, 0L)
  expect_false(res$truncated)
})

test_that("a no-match search says so instead of rendering an empty box", {
  res <- hierarchy_local_search("psoc", "2022", "zzzzz-no-such-occupation")
  expect_length(res$matches, 0L)
  html <- .render(hierarchy_tree_ui(
    "psoc", "2022", matches = res$matches, reveal = c("__none__")
  ))
  expect_true(grepl("No entries match", html, fixed = TRUE))
})

test_that("a very broad search is capped and the cap is announced upstream", {
  res <- hierarchy_local_search("psgc", .current_version("psgc"), "a")
  expect_lte(length(res$matches), HIERARCHY_SEARCH_CAP)
  expect_true(res$truncated)
  expect_gt(res$total, length(res$matches))
})


# ---------------------------------------------------------------------
# Trigger, dialog and selected-entry pane
# ---------------------------------------------------------------------

test_that("Browse hierarchy is offered only where a hierarchy exists", {
  expect_null(hierarchy_browse_button_ui("ptscs"))
  expect_null(hierarchy_browse_button_ui("pscrcs"))

  html <- .render(hierarchy_browse_button_ui("psic", "2026"))
  expect_true(grepl("Browse hierarchy", html, fixed = TRUE))
  expect_true(grepl('id="hierarchy_open"', html, fixed = TRUE))
})

test_that("the hierarchy dialog is an accessible dialog", {
  html <- .render(hierarchy_dialog_ui("psic", "2026"))
  expect_true(grepl('aria-modal="true"', html, fixed = TRUE))
  expect_true(grepl('role="dialog"', html, fixed = TRUE))
  expect_true(grepl('aria-label="Close the hierarchy browser"', html, fixed = TRUE))
  # Both live regions, and the local search field with a real label.
  expect_true(grepl('id="hierarchy_tree"', html, fixed = TRUE))
  expect_true(grepl('id="hierarchy_entry"', html, fixed = TRUE))
  expect_true(grepl("Find within this hierarchy", html, fixed = TRUE))
})

test_that("the selected-entry pane carries every fact the handoff requires", {
  entry <- get_classification_entry("psoc", "2022", hierarchy_children("psoc", "2022")$code[[1]])
  html <- .render(hierarchy_entry_pane_ui(entry, "psoc", "2022"))

  expect_true(grepl(entry$code, html, fixed = TRUE))       # code
  expect_true(grepl(entry$label, html, fixed = TRUE))      # label
  expect_true(grepl("Level", html, fixed = TRUE))          # level
  expect_true(grepl("2022", html, fixed = TRUE))           # edition
  expect_true(grepl("psa-tag-", html))                     # status, with text
  expect_true(grepl("psa-source-line", html, fixed = TRUE)) # source
  expect_true(grepl("View in Search", html, fixed = TRUE))
  expect_true(grepl('id="hierarchy_view_in_search"', html, fixed = TRUE))
})

test_that("the entry pane prompts rather than erroring when nothing is selected", {
  html <- .render(hierarchy_entry_pane_ui(NULL))
  expect_true(grepl("Select an entry in the tree", html, fixed = TRUE))
  expect_false(grepl("hierarchy_view_in_search", html, fixed = TRUE))
})

test_that("an ineligible system renders an explanation, never a fabricated tree", {
  html <- .render(hierarchy_tree_ui("ptscs", "2025-v2.1"))
  expect_true(grepl("not published with parent-child relationships", html, fixed = TRUE))
  expect_false(grepl("psa-hier-node", html, fixed = TRUE))
})
