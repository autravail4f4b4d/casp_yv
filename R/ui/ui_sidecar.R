# RM Assistant sidecar / drawer / sheet (design surface 1l).
#
# PRESENTATION AND DISCLOSURE ONLY. No LLM client, no tools, no prompt, no
# classification logic, and no second conversation path: the chat mounted
# inside this shell is the SAME `shinychat` module, with the same
# "rm_assistant" id, the same static greeting and the same
# `assistant_handle_turn()` server pipeline it has always had. This file
# changes WHERE that panel lives and HOW it is opened, and nothing else.
#
# ---------------------------------------------------------------------------
# WHAT MOVED
#
# RM used to be an ordinary `nav_panel` — a fifth destination you navigated
# TO, which meant leaving whatever record you were asking about. The design
# removes it from the navigation entirely (four workspace destinations
# remain: Search, PSOC + PSIC, Compare Editions, Sources) and makes the
# assistant a contextual surface that opens OVER or BESIDE the page you are
# already on.
#
# Three breakpoints, one DOM node:
#
#   >= 1464px   docked sidecar, 440px. NON-MODAL: no backdrop, no focus
#               trap, no `aria-modal`, page content reflows to make room and
#               stays fully interactive while the panel is open. The
#               threshold is CONTENT-AWARE -- see RM_SIDECAR_DOCKED_MIN_PX.
#   1024-1463   overlay drawer, 420px, over a dimmed backdrop. Modal
#               semantics; page content does not reflow.
#   <= 1023     near-full-height bottom sheet. Modal semantics.
#
# There is ONE panel element and ONE chat instance across all three. That is
# deliberate: a second copy would mean a duplicate `rm_assistant-chat` id,
# two transcripts, and a conversation that changed depending on the window
# width.
#
# ---------------------------------------------------------------------------
# WHY THE SHARED DIALOG SHELL IS NOT USED FOR THE DOCKED STATE
#
# `psa_dialog_ui(variant = "drawer")` is a Bootstrap modal: it always emits
# `role="dialog"`, `aria-modal="true"` and a backdrop, and Bootstrap locks
# page scroll behind it. That is correct for the two narrow breakpoints and
# WRONG for the docked one, where the page beside the panel must remain a
# live, reachable, scrollable part of the same document. Announcing a
# non-modal side panel as `aria-modal` tells a screen-reader user the rest
# of the page is inert when it is not.
#
# So the docked state gets the minimum additional shell it needs, and the
# ARIA is switched at the breakpoint by `matchMedia` rather than being
# guessed once at render time (CSS cannot set ARIA, and a media query cannot
# reach the accessibility tree).
#
# ---------------------------------------------------------------------------
# CONVERSATION PERSISTENCE
#
# Closing the panel sets `hidden` on an element that is never removed and
# never re-rendered, so the transcript, the scroll position and the ellmer
# client's turn history all survive close/reopen and page navigation
# untouched. Only "New chat" clears the conversation, and it does so
# through the existing `rm_assistant-new_chat` observer in app.R.
#
# ---------------------------------------------------------------------------
# PUBLIC CONTRACT (this file)
#
#   rm_sidecar_deps()                         behaviour, idempotent
#   rm_sidecar_ui(status)                     the panel + scrim
#   rm_ask_button_ui(id, label, ...)          client-side launcher
#   rm_context_button_ui(input_id, label, ..) contextual launcher (Shiny)
#   rm_context_chip_ui(items)                 attached-context chips
#   rm_context_starter_actions(descriptor)    the prompts one context offers
#   rm_context_starter_ui(items)              deterministic contextual starter
#   rm_sidecar_open(session)                  open it from the server
#   rm_sidecar_server(input, output, session, ...)
#
# Stable DOM ids:
#   rm-sidecar          the panel
#   rm-sidecar-title    its accessible name
#
# Stable Shiny ids added here:
#   rm_context_remove       JS input — key of a chip the user dismissed
#   rm_attached_context     uiOutput — the chip row
#   rm_context_starter      uiOutput — the deterministic starter block
#   rm_context_starter_1..4 actionButton — one starter action each


# THE CONTEXTUAL TURNS (UAT-RM-01, revised by UAT2-RM-01).
#
# One per contextual action, and referential by construction: each opens
# with "Explain"/"Why", which is what `assistant_explanation_requested()`
# recognises, so `assistant_handle_turn()` resolves it against the record
# just attached instead of trying to code the sentence itself.
#
# They are written as the user's own question because that is exactly what
# they become: the text is submitted through the ordinary composer and
# appears in the transcript as the user's turn.
# Each string is checked against that detector by test, because a wording
# it does not recognise would silently route the turn into the CODING
# path -- classifying the sentence instead of answering about the record.
# "Review this coding pair." is not recognised and is therefore not used;
# the coding-pair intent opens with "Explain" and carries the review
# instruction after it, rather than widening the detector for one button.
#
# WHAT CHANGED IN UAT2. These strings are NO LONGER SUBMITTED
# AUTOMATICALLY when the panel opens. They are the first action of the
# deterministic starter below, and reach the provider only when the reader
# presses one. See `rm_context_starter_actions()` for why, and for why
# every other starter wording is explanation-shaped too.
RM_INTENT_ENTRY <- "Explain this classification entry."
RM_INTENT_CORRESPONDENCE <- "Explain this relationship."
RM_INTENT_CODING_PAIR <-
  "Explain this coding pair: review the PSOC and PSIC selections."

# The shinychat element the module mounts: NS("rm_assistant")("chat"). The
# same namespaced id the New chat contract in R/ui/ui_assistant.R uses.
RM_CHAT_ELEMENT_ID <- "rm_assistant-chat"

RM_SIDECAR_ID <- "rm-sidecar"
RM_SIDECAR_TITLE_ID <- "rm-sidecar-title"
RM_CONTEXT_OUTPUT <- "rm_attached_context"
RM_CONTEXT_REMOVE <- "rm_context_remove"

# The deterministic contextual starter (UAT2-RM-01). A FIXED number of
# stable input ids, so pressing "Ask RM" on a hundred records still creates
# exactly four observers for the life of the session -- no observer is ever
# built per attached record.
RM_STARTER_OUTPUT <- "rm_context_starter"
RM_STARTER_INPUTS <- paste0("rm_context_starter_", 1:4)

# The docked breakpoint. Kept in one place because BOTH the stylesheet and
# the ARIA switch below have to agree on it; they are asserted against each
# other in tests/testthat/test-ui-sidecar.R.
RM_SIDECAR_WIDTH_PX <- 440
# The width at which the Search workspace itself is still usable: the
# 312px filter rail, a results table wide enough to keep four readable
# columns, and its gutters. Below this the labels start truncating, which
# is the defect UAT-UI-02 reported.
RM_SIDECAR_MIN_WORKSPACE_PX <- 1024
# CONTENT-AWARE DOCKING (UAT-UI-02).
#
# Docking used to begin at 1280, which left 840px of page beside the
# panel -- filters, results AND selected entry squeezed into less room
# than the workspace needs on its own, so result labels and the selected
# entry clipped. The threshold is now DERIVED: dock only where the
# workspace keeps its minimum after the panel takes its width. Anything
# narrower gets the overlay drawer, which covers the page instead of
# compressing it.
RM_SIDECAR_DOCKED_MIN_PX <- RM_SIDECAR_MIN_WORKSPACE_PX + RM_SIDECAR_WIDTH_PX


.RM_SIDECAR_JS <- '
(function () {
  if (window.__psaRmSidecarInstalled) { return; }
  window.__psaRmSidecarInstalled = true;

  var DOCKED = window.matchMedia("(min-width: 1464px)");
  var opener = null;

  function panel() { return document.getElementById("rm-sidecar"); }
  function scrim() { return document.getElementById("rm-sidecar-scrim"); }

  function isOpen() {
    var p = panel();
    return !!p && p.getAttribute("data-open") === "true";
  }

  // The ARIA a side panel gets depends entirely on whether the rest of the
  // page is still usable while it is open, and that is a BREAKPOINT fact.
  // Docked: a complementary landmark beside the content. Overlay/sheet: a
  // modal dialog over inert content.
  function syncSemantics() {
    var p = panel();
    if (!p) { return; }
    if (DOCKED.matches) {
      p.setAttribute("role", "complementary");
      p.removeAttribute("aria-modal");
    } else {
      p.setAttribute("role", "dialog");
      p.setAttribute("aria-modal", "true");
    }
    document.body.classList.toggle(
      "psa-rm-docked", DOCKED.matches && isOpen()
    );
    document.body.classList.toggle(
      "psa-rm-overlay", !DOCKED.matches && isOpen()
    );
    // The backdrop belongs to the two MODAL modes only, and it has to
    // follow the breakpoint rather than only the open/close action: a
    // window narrowed while the panel is open crosses from docked to
    // overlay, and an overlay with no backdrop over live content is
    // exactly the "modal that lies about being modal" case.
    var s = scrim();
    if (s) { s.hidden = DOCKED.matches || !isOpen(); }
  }

  function focusables(root) {
    var nodes = root.querySelectorAll(
      "a[href], button:not([disabled]), input:not([disabled]):not([type=hidden]), " +
      "select:not([disabled]), textarea:not([disabled]), [tabindex]:not([tabindex=\'-1\'])"
    );
    return Array.prototype.filter.call(nodes, function (el) {
      return el.offsetWidth > 0 || el.offsetHeight > 0;
    });
  }

  function open(trigger) {
    var p = panel();
    if (!p) { return; }
    if (trigger) { opener = trigger; }
    p.hidden = false;
    p.setAttribute("data-open", "true");
    syncSemantics();
    var target = p.querySelector("textarea, input, button");
    if (target) { try { target.focus(); } catch (e) { /* non-fatal */ } }
  }

  function close() {
    var p = panel();
    if (!p) { return; }
    p.setAttribute("data-open", "false");
    p.hidden = true;
    var s = scrim();
    if (s) { s.hidden = true; }
    document.body.classList.remove("psa-rm-docked", "psa-rm-overlay");
    if (opener && document.contains(opener)) {
      try { opener.focus(); } catch (e) { /* non-fatal */ }
    }
    opener = null;
  }

  document.addEventListener("click", function (e) {
    // Re-derive the breakpoint state before acting on anything. A viewport
    // that changed without delivering a resize event (see the listener
    // block at the bottom) is corrected here, so the panel can never be
    // ACTED on while its ARIA still describes the previous breakpoint.
    if (isOpen()) { syncSemantics(); }
    var t = e.target.closest ? e.target.closest("[data-psa-rm-open]") : null;
    if (t) { e.preventDefault(); open(t); return; }
    var c = e.target.closest ? e.target.closest("[data-psa-rm-close]") : null;
    if (c) { e.preventDefault(); close(); return; }
  });

  // Escape closes in every mode. In the docked, non-modal mode this is a
  // convenience rather than a modal contract, and it is safe because the
  // panel is only ever opened deliberately.
  document.addEventListener("keydown", function (e) {
    if (isOpen()) { syncSemantics(); }
    if (e.key !== "Escape" && e.key !== "Esc") { return; }
    if (isOpen()) { close(); }
  });

  // Focus containment applies ONLY to the two modal breakpoints. Docked,
  // Tab must be free to leave the panel and reach the page beside it --
  // trapping focus there would be the accessibility bug, not the fix.
  document.addEventListener("keydown", function (e) {
    if (e.key !== "Tab" || DOCKED.matches || !isOpen()) { return; }
    var p = panel();
    var items = focusables(p);
    if (!items.length) { return; }
    var first = items[0], last = items[items.length - 1];
    if (e.shiftKey && document.activeElement === first) {
      e.preventDefault(); last.focus();
    } else if (!e.shiftKey && document.activeElement === last) {
      e.preventDefault(); first.focus();
    } else if (!p.contains(document.activeElement)) {
      e.preventDefault(); first.focus();
    }
  });

  if (DOCKED.addEventListener) { DOCKED.addEventListener("change", syncSemantics); }
  else if (DOCKED.addListener) { DOCKED.addListener(syncSemantics); }
  // FOUR signals for one fact, deliberately.
  //
  // The media-query change event is the correct signal and the one that
  // fires in an ordinary browser. Under the viewport emulation used for
  // UAT none of the three passive signals fired, while the CSS breakpoint
  // itself switched -- which left the panel drawn at its 420px overlay
  // width while still announcing itself as a non-modal docked sidecar. A
  // panel whose ARIA and whose layout disagree about whether the rest of
  // the page is reachable is the exact failure this file exists to avoid.
  // The fourth signal is the interaction handlers above, which re-derive
  // the state before acting; between them the panel cannot be USED in a
  // stale mode even where no passive signal ever arrives.
  window.addEventListener("resize", syncSemantics);
  if (typeof ResizeObserver !== "undefined") {
    try {
      new ResizeObserver(syncSemantics).observe(document.documentElement);
    } catch (e) { /* non-fatal: the two listeners above still apply */ }
  }

  // Contextual "Ask RM" actions are Shiny inputs (the server has to build
  // the verified context first), so the server opens the panel.
  if (window.Shiny && Shiny.addCustomMessageHandler) {
    Shiny.addCustomMessageHandler("psa-rm-open", function (_msg) { open(null); });
  }

  // ---- Decorative-SVG hardening (UAT2-RM-03) ---------------------------
  //
  // THE DEFECT, read off the live DOM rather than inferred. This
  // application\'s own icons are already correct: lucide_icon() emits
  // aria-hidden="true" focusable="false" on every glyph, and each one sits
  // inside a control that carries its own aria-label. The icons that leak
  // are SHINYCHAT\'S, shipped inside the chat element we mount:
  //
  //   bi-arrow-up-circle-fill   Send message      no aria-hidden
  //   bi-stop-circle-fill       Cancel/stop       no aria-hidden
  //   bi-robot                  assistant message no aria-hidden
  //   bi-x-lg                   close             no aria-hidden
  //   <svg viewBox="0 0 100 100">  loading dots   no aria-hidden
  //
  // An <svg> with no role and no accessible name is still a node in the
  // accessibility tree, and it is serialised by its element name -- which
  // is the literal "svg" that reached copied/accessibility output. Every
  // one of them is decorative: the button around it already has a name.
  //
  // shinychat exposes no option for this and we do not fork it, so the
  // panel hardens its own subtree. It is deliberately CONSERVATIVE: an
  // <svg> that carries its own accessible name (aria-label,
  // aria-labelledby, role="img" plus a <title>) is left completely alone,
  // so a meaningful graphic can never be hidden by this pass. Nothing
  // visual changes -- aria-hidden and focusable have no rendering effect.
  function named(svg) {
    return svg.hasAttribute("aria-label") ||
           svg.hasAttribute("aria-labelledby") ||
           !!svg.querySelector("title");
  }

  function hideDecorativeIcons(root) {
    if (!root || !root.querySelectorAll) { return; }
    var svgs = root.querySelectorAll("svg");
    Array.prototype.forEach.call(svgs, function (s) {
      if (named(s)) { return; }
      if (s.getAttribute("aria-hidden") !== "true") {
        s.setAttribute("aria-hidden", "true");
      }
      if (s.getAttribute("focusable") !== "false") {
        s.setAttribute("focusable", "false");
      }
    });
  }

  // The chat re-renders as it streams -- the stop button replaces the send
  // button, assistant messages arrive with their own icon -- so one pass at
  // load would harden only what exists at load.
  function watchIcons() {
    var p = panel();
    if (!p) { return; }
    hideDecorativeIcons(p);
    if (!window.MutationObserver) { return; }
    new MutationObserver(function (records) {
      for (var i = 0; i < records.length; i++) {
        var added = records[i].addedNodes;
        for (var j = 0; j < added.length; j++) {
          var n = added[j];
          if (n.nodeType !== 1) { continue; }
          if (n.tagName && n.tagName.toLowerCase() === "svg") {
            hideDecorativeIcons(n.parentNode || p);
          } else {
            hideDecorativeIcons(n);
          }
        }
      }
    }).observe(p, {childList: true, subtree: true});
  }

  function init() { syncSemantics(); watchIcons(); }

  if (document.readyState !== "loading") { init(); }
  else { document.addEventListener("DOMContentLoaded", init); }
})();
'

#' Install the sidecar behaviour. Idempotent.
rm_sidecar_deps <- function() {
  shiny::tags$script(shiny::HTML(.RM_SIDECAR_JS))
}


# ---- Launchers -------------------------------------------------------------

#' The global "Ask RM" launcher.
#'
#' Deliberately NOT a Shiny input: opening a panel that is already in the
#' DOM needs no server round-trip, and making it one would put a network
#' hop between the click and the panel on every page.
#'
#' @param id character(1). DOM id (not a Shiny input id).
#' @param label character(1). Visible text. Never omit it.
#' @param class character(1) or NULL. Extra classes.
rm_ask_button_ui <- function(id, label = "Ask RM", class = NULL) {
  shiny::tags$button(
    id = id,
    type = "button",
    class = paste(c("psa-askrm", class), collapse = " "),
    `data-psa-rm-open` = "",
    lucide_icon("sparkles", 14),
    shiny::tags$span(class = "psa-askrm__text", label)
  )
}

#' A CONTEXTUAL "Ask RM" launcher.
#'
#' A real Shiny `actionButton`, because the server has to derive the
#' verified context for the current record before the panel opens. It opens
#' the same single assistant; it never navigates.
#'
#' @param input_id character(1). Shiny input id.
#' @param label character(1). Visible text.
#' @param class character(1) or NULL. Extra classes.
#' @param aria_label character(1) or NULL.
rm_context_button_ui <- function(input_id, label, class = NULL, aria_label = NULL) {
  btn <- shiny::actionButton(
    input_id,
    label = shiny::tagList(
      lucide_icon("sparkles", 14),
      shiny::tags$span(class = "psa-askrm__text", label)
    ),
    class = paste(c("psa-askrm psa-askrm--context", class), collapse = " ")
  )
  if (!is.null(aria_label)) {
    btn$attribs[["aria-label"]] <- aria_label
  }
  btn
}


# ---- Attached context ------------------------------------------------------

#' Render the attached-context chips.
#'
#' WHAT AN ATTACHED CONTEXT IS, AND IS NOT.
#'
#' It is a VISIBLE, REMOVABLE marker of the verified application record the
#' user pressed "Ask RM" from. It is built only from fields a deterministic
#' service already returned (`correspondence_ask_rm_context()` for a
#' relationship; the canonical row itself for an entry), so nothing here can
#' introduce a code the application did not retrieve.
#'
#' It is NOT part of the conversation, and it is deliberately not injected
#' into the model's prompt in this pass: the assistant's grounding, routing
#' and execution path (`assistant_handle_turn()`) is unchanged, and silently
#' prepending text to a user's turn would change RM's behaviour on the very
#' turns the acceptance matrix pins down. See docs/ASSISTANT_CONTRACT.md.
#'
#' @param items A named list of contexts: key -> list(label=, detail=).
rm_context_chip_ui <- function(items) {
  if (is.null(items) || length(items) == 0L) {
    return(NULL)
  }
  shiny::tagList(
    shiny::tags$span(class = "psa-rm-context-label", "Attached context"),
    shiny::tags$div(
      class = "psa-rm-context-chips",
      lapply(names(items), function(key) {
        it <- items[[key]]
        shiny::tags$span(
          class = "psa-rm-context-chip",
          # The dot marks the chip as retrieved data rather than user text.
          shiny::tags$span(class = "psa-rm-context-dot", `aria-hidden` = "true"),
          shiny::tags$span(class = "psa-rm-context-text", it$label),
          shiny::tags$button(
            type = "button",
            class = "psa-rm-context-remove",
            `aria-label` = paste("Remove attached context:", it$label),
            onclick = sprintf(
              "Shiny.setInputValue('%s', {key: '%s', nonce: Math.random()}, {priority: 'event'});",
              RM_CONTEXT_REMOVE, key
            ),
            lucide_icon("x", 11)
          )
        )
      })
    )
  )
}


# ---- The deterministic contextual starter (UAT2-RM-01) ---------------------
#
# WHAT THIS REPLACES.
#
# "Ask RM about this entry" used to attach the record, open the panel and
# then SUBMIT "Explain this classification entry." on the reader's behalf.
# Browser UAT saw the loading indicator appear and no reply arrive, and the
# lifecycle behind that is reproducible with no provider at all:
#
#   assistant_handle_turn("Explain this classification entry.", state)
#     -> handled = FALSE, route = "contextual_coding", render = NA
#   the ContentText override (assistant_render.R) suppresses EVERY streamed
#     chunk on that route, so nothing renders while the turn runs
#   app.R's rm_chat$last_turn() observer then guards the assembled text --
#     and `assistant_render_coding_result()` for an attached-context packet
#     is the EMPTY STRING, so a reply naming any code outside allowed_codes
#     (a parent group, a related PSIC) was replaced by nothing at all.
#
# So the automatic first turn could spend a provider call and produce no
# visible output whatsoever. The product answer is not to make that turn
# louder: **View details** already shows the verified definition, tasks and
# examples, so opening RM to be told the same thing is a provider call the
# reader did not ask for. Opening RM now costs ZERO provider calls, and the
# reader chooses what to ask.
#
# WHY EVERY ACTION IS PHRASED THE WAY IT IS.
#
# Each prompt is submitted verbatim through the ordinary composer, so its
# wording decides its ROUTE. Measured against `assistant_handle_turn()`
# with a record attached:
#
#   "Why might an occupation fit here?"       explanation -> answers ABOUT
#   "Explain how this compares with ..."      explanation    the record
#   "Help me classify a similar occupation."  non_classification -> RM asks
#                                             for a description, streams
#                                             normally
#   "Review with a PSIC code"                 CODING (handled = TRUE) --
#                                             REJECTED, because it makes RM
#                                             classify the button's own
#                                             sentence
#
# That last line is why the actions are not the mock's shorthand labels:
# a starter that reads well but routes into the coding path would answer a
# question nobody asked. The wording is asserted against the detector by
# test rather than trusted.

#' The four actions offered for one attached context.
#'
#' Built from the DESCRIPTOR's kind (and, for an entry, its system), never
#' from a hard-coded code and never from the chip's display text.
#'
#' @param descriptor One `assistant_context_descriptor_*()` list.
#' @return character vector of prompts, submitted verbatim.
rm_context_starter_actions <- function(descriptor) {
  kind <- descriptor$kind %||% "entry"
  if (identical(kind, "correspondence")) {
    return(c(
      RM_INTENT_CORRESPONDENCE,
      "Why did this category change between editions?",
      "Explain what this means for a time series.",
      "Explain how confident this correspondence is."
    ))
  }
  if (identical(kind, "coding_pair")) {
    return(c(
      RM_INTENT_CODING_PAIR,
      "Why are the occupation and the industry coded separately?",
      "Explain whether these two belong together.",
      "Help me code a similar case."
    ))
  }
  system <- tolower(descriptor$system %||% "")
  if (identical(system, "psoc")) {
    return(c(
      "Why might an occupation fit here?",
      "Explain how this compares with another PSOC code.",
      "Help me classify a similar occupation.",
      "Explain how a PSIC code would apply here."
    ))
  }
  if (identical(system, "psic")) {
    return(c(
      "Why might an establishment fit here?",
      "Explain how this compares with another PSIC code.",
      "Help me classify a similar business activity.",
      "Explain how a PSOC code would apply here."
    ))
  }
  # Every other registry system (PSGC, PSCED, PCOICOP, PCPC, PSCCS, ...).
  # Deliberately says nothing about occupations or establishments.
  c(
    RM_INTENT_ENTRY,
    "Why would a record be coded here?",
    "Explain where this sits in the hierarchy.",
    "Explain what this level covers."
  )
}

#' The starter block itself. Deterministic; no provider call to render it.
#'
#' Rendered from the NEWEST attachment, which is the record the reader last
#' pressed "Ask RM" from. Returns NULL when nothing is attached, so removing
#' the last chip removes the starter with it.
#'
#' The buttons are ordinary `actionButton`s on four fixed ids. Pressing one
#' submits its prompt through `shinychat::update_chat_user_input()` -- the
#' same composer, the same `rm_assistant-chat_user_input` input and the same
#' `assistant_handle_turn()` as anything typed by hand. There is no second
#' execution path here and no message is written into the transcript by this
#' file.
#'
#' @param items The attached-context list, key -> list(label=, descriptor=).
rm_context_starter_ui <- function(items) {
  if (is.null(items) || length(items) == 0L) {
    return(NULL)
  }
  it <- items[[length(items)]]
  actions <- rm_context_starter_actions(it$descriptor)

  shiny::tags$div(
    class = "psa-rm-starter",
    role = "group",
    `aria-label` = "Suggested questions about the attached record",
    shiny::tags$p(
      class = "psa-rm-starter-lead",
      # The chip's own text, so the starter can never name a record the
      # chip does not show.
      shiny::tags$span(class = "psa-rm-starter-record", it$label),
      " is attached."
    ),
    shiny::tags$p(class = "psa-rm-starter-ask", "What would you like help with?"),
    shiny::tags$div(
      class = "psa-rm-starter-actions",
      lapply(seq_along(actions), function(i) {
        shiny::actionButton(
          RM_STARTER_INPUTS[[i]],
          label = actions[[i]],
          class = "psa-rm-starter-action",
          `aria-label` = paste("Ask RM:", actions[[i]])
        )
      })
    )
  )
}


# ---- The panel -------------------------------------------------------------

#' The assistant panel itself.
#'
#' Mounted ONCE per page, outside the navigation, so it is reachable from
#' every destination and survives navigating between them.
#'
#' @param status The `rm_assistant_status()` list. Decided once at
#'   UI-build time, exactly as the previous nav-panel mount did.
rm_sidecar_ui <- function(status = NULL) {
  available <- isTRUE(status$enabled) && isTRUE(status$available)

  shiny::tagList(
    rm_sidecar_deps(),
    # The backdrop for the two modal breakpoints. Hidden at >= 1280 by CSS
    # AND by the script, so the docked panel can never dim the page it is
    # meant to sit beside.
    shiny::tags$div(
      id = "rm-sidecar-scrim",
      class = "psa-rm-scrim",
      `data-psa-rm-close` = "",
      hidden = NA,
      `aria-hidden` = "true"
    ),
    shiny::tags$aside(
      id = RM_SIDECAR_ID,
      class = "psa-rm-sidecar",
      # role / aria-modal are set by the script at the current breakpoint;
      # the static value is the non-modal one, which is the safe default if
      # scripting is unavailable.
      role = "complementary",
      `aria-labelledby` = RM_SIDECAR_TITLE_ID,
      `data-open` = "false",
      hidden = NA,

      shiny::tags$div(
        class = "psa-rm-sidecar-head",
        shiny::tags$div(
          class = "psa-rm-sidecar-heading",
          shiny::tags$h2(id = RM_SIDECAR_TITLE_ID, class = "psa-rm-sidecar-title",
                         "RM Assistant"),
          shiny::tags$span(class = "psa-rm-sidecar-standing",
                           "Reads verified data only")
        ),
        shiny::tags$div(
          class = "psa-rm-sidecar-actions",
          if (available) rm_assistant_new_chat_ui(),
          shiny::tags$button(
            type = "button",
            class = "psa-rm-sidecar-close",
            `data-psa-rm-close` = "",
            `aria-label` = "Close the RM Assistant panel",
            lucide_icon("x", 14)
          )
        )
      ),

      if (available) {
        shiny::tags$div(
          class = "psa-rm-context",
          shiny::uiOutput(RM_CONTEXT_OUTPUT),
          # The deterministic starter sits with the chip it describes, not
          # in the transcript: it is not something RM said, and nothing in
          # it has cost a provider call.
          shiny::uiOutput(RM_STARTER_OUTPUT)
        )
      },

      shiny::tags$div(
        class = "psa-rm-sidecar-body",
        # `heading = FALSE`: the panel header above already carries the
        # "RM Assistant" heading, and the degraded card announcing it again
        # gives the panel two identical H2s in a row.
        if (available) {
          rm_assistant_panel_ui()
        } else {
          rm_assistant_unavailable_ui(status$reason, heading = FALSE)
        }
      )
    )
  )
}

#' Open the panel from the server.
#'
#' Used by the contextual launchers, which must attach their verified
#' context before the panel appears.
rm_sidecar_open <- function(session = shiny::getDefaultReactiveDomain()) {
  session$sendCustomMessage("psa-rm-open", list())
  invisible(NULL)
}


# ---- Server ----------------------------------------------------------------

#' Wire the attached-context state and every contextual launcher.
#'
#' All state is local to this function, so it is per-session by
#' construction -- one visitor's attached record can never appear in
#' another's panel.
#'
#' Contexts are keyed, so pressing "Ask RM" twice on the SAME record does
#' not stack duplicates, while a different record adds a second chip rather
#' than silently replacing the first. Navigation never touches them: only an
#' explicit attach or an explicit remove changes this list.
#'
#' @param entry_selection Reactive returning the Search screen's selected
#'   canonical row (zero or one row).
#' @param correspondence_selection Reactive returning the Compare Editions
#'   selected relationship row (zero or one row).
#' @param turn_state The session's assistant turn state
#'   (`assistant_new_turn_state()`). When supplied, every change to the
#'   chips is mirrored into it as IDENTIFIER-ONLY descriptors, which is what
#'   makes an attached record actually reachable by RM. See
#'   R/assistant/assistant_attached_context.R for what the bridge may and
#'   may not do with them.
#' @param available logical(1). Whether the assistant is configured. When
#'   FALSE this installs nothing: there is no panel body to attach to.
rm_sidecar_server <- function(input, output, session,
                              entry_selection = NULL,
                              correspondence_selection = NULL,
                              coding_pair_selection = NULL,
                              turn_state = NULL,
                              available = TRUE) {
  if (!isTRUE(available)) {
    return(invisible(NULL))
  }

  attached <- shiny::reactiveVal(list())

  # ONE writer, so the chips the user can see and the descriptors RM can
  # reach cannot diverge. Every mutation below goes through this.
  sync_turn_state <- function(items) {
    if (is.null(turn_state)) return(invisible(NULL))
    assistant_turn_set_attached_context(
      turn_state,
      lapply(unname(items), function(it) it$descriptor)
    )
    invisible(NULL)
  }

  attach <- function(key, label, descriptor) {
    if (is.null(descriptor)) return(invisible(NULL))
    cur <- attached()
    # Re-attaching the same record moves it to the END of the list rather
    # than duplicating it: newest-last is what the bridge reads as "the
    # thing the user is pointing at".
    cur[[key]] <- NULL
    cur[[key]] <- list(label = label, descriptor = descriptor)
    attached(cur)
    sync_turn_state(cur)
  }

  # --- Opening RM, and asking it something (UAT-RM-01 / UAT2-RM-01) -------
  #
  # THE TWO ARE NOW SEPARATE ACTIONS.
  #
  # `present()` is what a contextual launcher does: attach the verified
  # record, show the panel, and render the deterministic starter. It makes
  # NO provider call. `ask()` is what a starter button does: submit one
  # prompt, once.
  #
  # THE TURN GOES THROUGH THE ORDINARY COMPOSER, deliberately.
  # `shinychat::update_chat_user_input(submit = TRUE)` fills and submits the
  # real composer, so the message arrives on the same
  # `rm_assistant-chat_user_input` input as anything the user types. That
  # means one entry point, one `assistant_handle_turn()`, one route
  # decision, one response guard -- and the user's own turn visible in the
  # transcript. Appending a synthesised exchange instead would have been a
  # second assistant path, which is the thing this design most needs not to
  # have.
  present <- function() {
    rm_sidecar_open(session)
    invisible(NULL)
  }

  ask <- function(prompt) {
    shiny::req(is.character(prompt), nzchar(prompt))
    rm_sidecar_open(session)
    # THE CHAT ELEMENT ID, not the module id. `chat_mod_ui("rm_assistant")`
    # mounts its chat as `NS(id)("chat")`, and this call is made from the
    # app's own session rather than the module's, so the un-namespaced
    # "rm_assistant" addresses nothing and the turn is silently never sent
    # -- which is exactly what browser UAT saw: panel opened, chip
    # attached, no question asked. Same namespaced form the New chat
    # contract in R/ui/ui_assistant.R already documents.
    shinychat::update_chat_user_input(
      RM_CHAT_ELEMENT_ID, value = prompt, submit = TRUE, focus = FALSE,
      session = session
    )
    invisible(NULL)
  }

  output[[RM_CONTEXT_OUTPUT]] <- shiny::renderUI({
    rm_context_chip_ui(attached())
  })
  shiny::outputOptions(output, RM_CONTEXT_OUTPUT, suspendWhenHidden = FALSE)

  # The deterministic starter. Same single source of truth as the chips, so
  # it appears, changes and disappears exactly with them -- removing the
  # last chip removes the starter, and New chat clears both.
  output[[RM_STARTER_OUTPUT]] <- shiny::renderUI({
    rm_context_starter_ui(attached())
  })
  shiny::outputOptions(output, RM_STARTER_OUTPUT, suspendWhenHidden = FALSE)

  # FOUR observers, created once. Each resolves its prompt at CLICK time
  # from whatever is attached then, so the buttons follow the newest record
  # without any observer being rebuilt. `ask()` is the only thing they do:
  # one composer submission, one provider call, no local branch that could
  # answer instead.
  lapply(seq_along(RM_STARTER_INPUTS), function(i) {
    shiny::observeEvent(input[[RM_STARTER_INPUTS[[i]]]], {
      items <- attached()
      shiny::req(length(items) > 0L)
      actions <- rm_context_starter_actions(items[[length(items)]]$descriptor)
      shiny::req(length(actions) >= i)
      ask(actions[[i]])
    })
  })

  shiny::observeEvent(input[[RM_CONTEXT_REMOVE]], {
    key <- input[[RM_CONTEXT_REMOVE]]$key
    shiny::req(is.character(key), nzchar(key))
    cur <- attached()
    cur[[key]] <- NULL
    attached(cur)
    # Removing the chip removes the context from every SUBSEQUENT turn,
    # not just from the display.
    sync_turn_state(cur)
  })

  # New chat discards the conversation, and the records attached to it go
  # with it -- leaving a chip pointing into a conversation the user just
  # threw away would make "this" refer to something no longer on screen.
  shiny::observeEvent(input[["rm_assistant-new_chat"]], {
    attached(list())
    sync_turn_state(list())
  })

  # --- Search: "Ask RM about this entry" ---------------------------------
  if (!is.null(entry_selection)) {
    shiny::observeEvent(input$search_ask_rm_entry, {
      entry <- entry_selection()
      shiny::req(!is.null(entry), nrow(entry) > 0L)
      entry <- entry[1, , drop = FALSE]
      attach(
        key = paste0("entry:", entry$system, ":", entry$version, ":", entry$code),
        label = paste(entry$code, "·", entry$label, "·",
                      toupper(entry$system), release_display_label(entry$version)),
        # IDENTIFIERS ONLY. The label above is for the chip the user reads;
        # what RM is allowed to see is re-read from the repository on the
        # turn that uses it, so a record cannot be described from a stale
        # snapshot taken when the button was pressed.
        descriptor = assistant_context_descriptor_entry(
          system = entry$system, version = entry$version, code = entry$code
        )
      )
      present()
    })
  }

  # --- Compare Editions: "Ask RM to explain this relationship" -----------
  #
  # Uses the EXISTING `correspondence_ask_rm_context()` whitelist rather
  # than a second, parallel extraction.
  if (!is.null(correspondence_selection)) {
    shiny::observeEvent(input$correspondence_ask_rm, {
      row <- correspondence_selection()
      shiny::req(!is.null(row), nrow(row) > 0L)
      ctx <- correspondence_ask_rm_context(row)
      shiny::req(!is.null(ctx))
      attach(
        key = paste0("corr:", ctx$from_version, ":", ctx$from_code,
                     ":", ctx$to_version, ":", ctx$to_code),
        label = paste0(ctx$from_code, " → ", ctx$to_code, " · ",
                       tools::toTitleCase(ctx$relation_type)),
        # Identifiers only, for the same reason as the entry above: the
        # relationship's facts are re-read from the correspondence artifact
        # on the turn that uses them.
        descriptor = assistant_context_descriptor_correspondence(
          from_version = ctx$from_version, from_code = ctx$from_code,
          to_version = ctx$to_version, to_code = ctx$to_code
        )
      )
      present()
    })
  }

  # --- PSOC + PSIC: "Ask RM to review this coding pair" -------------------
  #
  # The processor-facing action from the Review coding pair dialog. Both
  # halves are attached as ONE coding-pair descriptor rather than two
  # separate records, so the review turn can state the PSOC/PSIC separation
  # as a property of the pair instead of describing two unrelated codes.
  if (!is.null(coding_pair_selection)) {
    shiny::observeEvent(input[[DUAL_SEARCH_ASK_RM_INPUT]], {
      pair <- coding_pair_selection()
      shiny::req(!is.null(pair))
      shiny::req(!is.null(pair$psoc), nrow(pair$psoc) > 0L)
      shiny::req(!is.null(pair$psic), nrow(pair$psic) > 0L)
      occ <- pair$psoc[1, , drop = FALSE]
      ind <- pair$psic[1, , drop = FALSE]
      attach(
        key = paste0("pair:", occ$version, ":", occ$code, ":",
                     ind$version, ":", ind$code),
        label = paste0("PSOC ", occ$code, " + PSIC ", ind$code),
        descriptor = assistant_context_descriptor_coding_pair(
          psoc_version = occ$version, psoc_code = occ$code,
          psic_version = ind$version, psic_code = ind$code
        )
      )
      present()
    })
  }

  invisible(NULL)
}
