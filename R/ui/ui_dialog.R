# Shared dialog / drawer shell (UI-02, UI-03, UI-04, UI-05).
#
# PRESENTATION ONLY. Nothing in this file reads, ranks, verifies or
# transforms classification data. It builds an accessible overlay shell and
# manages focus; the content it wraps is produced by the owning screen
# module.
#
# WHY THIS EXISTS
# ---------------
# UI-02 (hierarchy browser), UI-03 (PSOC/PSIC detail + comparison), UI-04
# (correspondence relationship inspector) and UI-05 (terminology help) all
# need the same overlay contract (handoff section 3): one header/close
# pattern, Escape-to-close, focus moved in on open, focus trapped while
# open, focus restored to the originating control on close, and a
# full-screen treatment at 375/320. Implementing that four times would
# guarantee four different accessibility bugs.
#
# WHY IT BUILDS ON SHINY'S MODAL RATHER THAN A NEW WIDGET
# -------------------------------------------------------
# `shiny::showModal()` + Bootstrap 5's Modal component already provide the
# backdrop, the scroll lock, Escape handling, the show/hide lifecycle and
# the removal of the wrapper on `hidden.bs.modal`. What they do NOT provide
# is `role="dialog"`/`aria-modal`, an accessible title association, an
# accessible close label, or focus RESTORATION to the control that opened
# the dialog. So this file emits Bootstrap-compatible markup (same
# `id="shiny-modal"` contract `shiny::modalDialog()` uses, so
# `showModal()`/`removeModal()` work unchanged) and adds exactly the
# missing accessibility behaviour in one small, idempotent inline script.
#
# No new dependency, no new .js asset, no app.R change: the script installs
# itself once per page from `psa_dialog_deps()`, which every screen that can
# open a dialog includes in its own UI.
#
# PUBLIC CONTRACT (frozen -- other UI workstreams depend on these):
#   psa_dialog_deps()
#   psa_dialog_ui(id, title, body, footer, variant, size, eyebrow,
#                 close_label, description)
#   psa_dialog_show(dialog, session)
#   psa_dialog_close(session)
#   psa_dialog_open_button(input_id, label, ..., icon, class, disabled,
#                          aria_label)
#   psa_dialog_close_button(label)
#   psa_dialog_action_button(input_id, label, ..., class, icon)
#   psa_dialog_empty_ui(message)
#   view_in_search_apply(entry, session, results, table_id)

PSA_DIALOG_VARIANTS <- c("modal", "drawer")
PSA_DIALOG_SIZES <- c("md", "lg", "xl", "full")

# Bootstrap size class per logical size. "md" is Bootstrap's default width,
# which is why it maps to no extra class.
.PSA_DIALOG_SIZE_CLASS <- c(
  md = "",
  lg = "modal-lg",
  xl = "modal-xl",
  full = "modal-fullscreen"
)

# The one behavioural script. Guarded on a window flag so including
# psa_dialog_deps() from several screens (and again inside a dialog body)
# installs the listeners exactly once.
.PSA_DIALOG_JS <- '
(function () {
  if (window.__psaDialogInstalled) { return; }
  window.__psaDialogInstalled = true;

  var lastControl = null;

  function rememberControl(node) {
    if (!node || !node.closest) { return; }
    var control = node.closest(
      "button, a[href], input, select, textarea, [tabindex]:not([tabindex=\'-1\'])"
    );
    if (control && !control.closest(".psa-dialog")) { lastControl = control; }
  }

  document.addEventListener("mousedown", function (e) { rememberControl(e.target); }, true);
  document.addEventListener("keydown", function (e) {
    if (e.key === "Enter" || e.key === " " || e.key === "Spacebar") { rememberControl(e.target); }
  }, true);

  function focusable(root) {
    var nodes = root.querySelectorAll(
      "a[href], button:not([disabled]), input:not([disabled]):not([type=hidden]), " +
      "select:not([disabled]), textarea:not([disabled]), [tabindex]:not([tabindex=\'-1\'])"
    );
    return Array.prototype.filter.call(nodes, function (el) {
      return el.offsetWidth > 0 || el.offsetHeight > 0 || el === document.activeElement;
    });
  }

  // Focus moves INTO the dialog on open, and the originating control is
  // snapshotted before anything inside the dialog can be clicked.
  document.addEventListener("shown.bs.modal", function (e) {
    var dialog = e.target;
    if (!dialog || !dialog.classList || !dialog.classList.contains("psa-dialog")) { return; }
    dialog.__psaOrigin = lastControl;
    var target = dialog.querySelector("[data-psa-autofocus]") || focusable(dialog)[0] || dialog;
    try { target.focus(); } catch (err) { /* non-fatal */ }
  });

  // Focus RETURNS to the originating control on close.
  document.addEventListener("hidden.bs.modal", function (e) {
    var dialog = e.target;
    if (!dialog || !dialog.classList || !dialog.classList.contains("psa-dialog")) { return; }
    var origin = dialog.__psaOrigin;
    if (origin && document.body.contains(origin)) {
      try { origin.focus(); } catch (err) { /* non-fatal */ }
    }
  });

  // Focus TRAP. Bootstrap pushes stray focus back to the dialog element;
  // this makes Tab/Shift+Tab cycle properly within it instead.
  document.addEventListener("keydown", function (e) {
    if (e.key !== "Tab") { return; }
    var dialog = document.querySelector(".psa-dialog.show");
    if (!dialog || !dialog.contains(document.activeElement)) { return; }
    var items = focusable(dialog);
    if (!items.length) { return; }
    var first = items[0];
    var last = items[items.length - 1];
    if (e.shiftKey && document.activeElement === first) {
      e.preventDefault();
      last.focus();
    } else if (!e.shiftKey && document.activeElement === last) {
      e.preventDefault();
      first.focus();
    }
  }, true);
})();
'

# Bootstrap 5 / 4 initialiser, byte-identical in behaviour to the one
# shiny::modalDialog() emits, so a psa dialog shows exactly the way a stock
# Shiny modal does.
.PSA_DIALOG_BOOT_JS <- "if (window.bootstrap && !window.bootstrap.Modal.VERSION.match(/^4\\./)) {
  var modal = new bootstrap.Modal(document.getElementById('shiny-modal'));
  modal.show();
} else {
  $('#shiny-modal').modal().focus();
}"

#' Page-level dependencies for the dialog system.
#'
#' Include once in any screen that can open a dialog. Idempotent: the script
#' guards itself, so including it from several screens is harmless and adds
#' no listeners twice.
#'
#' @return A `tagList` containing a single inline `<script>`.
psa_dialog_deps <- function() {
  shiny::tagList(
    shiny::tags$script(
      `data-psa-dialog-deps` = "1",
      shiny::HTML(.PSA_DIALOG_JS)
    )
  )
}

.psa_dialog_variant <- function(variant) {
  variant <- match.arg(variant, PSA_DIALOG_VARIANTS)
  variant
}

#' Build an accessible dialog (centred modal) or drawer (side sheet).
#'
#' The return value is a plain tag suitable for `psa_dialog_show()` /
#' `shiny::showModal()`. Both variants use the SAME overlay primitive and
#' the same header/close/footer contract -- only the CSS placement differs
#' (`www/ui-dialog.css`), which is why a drawer inherits the modal's focus
#' management for free.
#'
#' Accessibility contract, asserted in tests/testthat/test-ui-dialog.R:
#'   * `role="dialog"` and `aria-modal="true"` on the overlay;
#'   * `aria-labelledby` pointing at the visible title;
#'   * a real `<button>` close control with an accessible label;
#'   * Escape closes (`data-bs-keyboard="true"`);
#'   * focus enters on open and returns to the opener on close
#'     (`psa_dialog_deps()`).
#'
#' @param id character(1). Stable identifier for this dialog KIND (e.g.
#'   "hierarchy-browser"). Used for the title id and as a `data-psa-dialog`
#'   hook; it is NOT the DOM id of the overlay, which must stay
#'   `shiny-modal` for Shiny's own show/remove handlers.
#' @param title character(1) or tag. The dialog's accessible name.
#' @param body Tag/tagList. Dialog content.
#' @param footer Tag/tagList or NULL. Defaults to a single Close button.
#' @param variant "modal" (centred) or "drawer" (right side sheet).
#' @param size "md", "lg", "xl" or "full".
#' @param eyebrow character(1) or NULL. Small overline above the title
#'   (e.g. "PSOC 2022"). Decorative; the title carries the accessible name.
#' @param close_label character(1). Accessible label for the header close
#'   button. Must name the action, never just "x".
#' @param description character(1) or NULL. Short text rendered under the
#'   title and wired as `aria-describedby`.
psa_dialog_ui <- function(id,
                          title,
                          body,
                          footer = NULL,
                          variant = c("modal", "drawer"),
                          size = c("md", "lg", "xl", "full"),
                          eyebrow = NULL,
                          close_label = "Close dialog",
                          description = NULL) {
  variant <- .psa_dialog_variant(variant)
  size <- match.arg(size, PSA_DIALOG_SIZES)

  title_id <- paste0("psa-dialog-title-", id)
  desc_id <- if (!is.null(description)) paste0("psa-dialog-desc-", id)

  if (is.null(footer)) {
    footer <- psa_dialog_close_button()
  }

  shiny::tags$div(
    id = "shiny-modal",
    class = paste(
      "modal fade psa-dialog",
      paste0("psa-dialog--", variant),
      paste0("psa-dialog--", size)
    ),
    tabindex = "-1",
    role = "dialog",
    `aria-modal` = "true",
    `aria-labelledby` = title_id,
    `aria-describedby` = desc_id,
    `data-psa-dialog` = id,
    # Escape closes; clicking the backdrop closes. Both spelled in the bs5
    # and bs4 attribute forms for the same reason shiny::modalDialog() does.
    `data-bs-keyboard` = "true",
    `data-keyboard` = "true",
    `data-bs-backdrop` = "true",
    `data-backdrop` = "true",

    shiny::tags$div(
      class = paste(
        "modal-dialog psa-dialog__dialog",
        .PSA_DIALOG_SIZE_CLASS[[size]]
      ),
      role = "document",

      shiny::tags$div(
        class = "modal-content psa-dialog__content",

        shiny::tags$div(
          class = "modal-header psa-dialog__header",
          shiny::tags$div(
            class = "psa-dialog__heading",
            if (!is.null(eyebrow)) {
              shiny::tags$div(class = "psa-eyebrow psa-dialog__eyebrow", eyebrow)
            },
            shiny::tags$h2(
              id = title_id,
              class = "modal-title psa-dialog__title",
              title
            ),
            if (!is.null(description)) {
              shiny::tags$p(
                id = desc_id,
                class = "psa-dialog__description",
                description
              )
            }
          ),
          # A real button with a real accessible name -- never an icon-only
          # control with no label, and never a <div> with a click handler.
          shiny::tags$button(
            type = "button",
            class = "btn-close psa-dialog__close",
            `data-bs-dismiss` = "modal",
            `data-dismiss` = "modal",
            `aria-label` = close_label
          )
        ),

        shiny::tags$div(class = "modal-body psa-dialog__body", body),

        shiny::tags$div(class = "modal-footer psa-dialog__footer", footer)
      )
    ),

    # Behaviour first (idempotent), then the Bootstrap show call.
    psa_dialog_deps(),
    shiny::tags$script(shiny::HTML(.PSA_DIALOG_BOOT_JS))
  )
}

#' Show a dialog built by `psa_dialog_ui()`.
psa_dialog_show <- function(dialog, session = shiny::getDefaultReactiveDomain()) {
  shiny::showModal(dialog, session = session)
}

#' Close whichever psa dialog is open.
psa_dialog_close <- function(session = shiny::getDefaultReactiveDomain()) {
  shiny::removeModal(session = session)
}

#' The control that OPENS a dialog.
#'
#' A plain Shiny `actionButton` carrying the `.psa-dialog-open` class. The
#' class is a styling and diagnostic hook only -- focus restoration works
#' from ANY control, because the script snapshots the last real control the
#' user activated rather than requiring a marker class.
#'
#' @param input_id character(1). Shiny input id.
#' @param label character(1). Visible label. Never omit it: an icon-only
#'   trigger would have no accessible name.
#' @param icon A `lucide_icon()` result or NULL. Decorative.
#' @param class character(1) or NULL. Extra classes.
#' @param disabled logical(1). Renders a genuinely disabled button.
#' @param aria_label character(1) or NULL. Overrides the accessible name
#'   when the visible label needs more context for screen readers.
psa_dialog_open_button <- function(input_id,
                                   label,
                                   ...,
                                   icon = NULL,
                                   class = NULL,
                                   disabled = FALSE,
                                   aria_label = NULL) {
  btn <- shiny::actionButton(
    input_id,
    label = shiny::tagList(icon, shiny::tags$span(class = "psa-dialog-open__text", label)),
    class = paste(c("psa-dialog-open", class), collapse = " "),
    ...
  )
  if (!is.null(aria_label)) {
    btn$attribs[["aria-label"]] <- aria_label
  }
  if (isTRUE(disabled)) {
    btn$attribs$disabled <- "disabled"
    btn$attribs[["aria-disabled"]] <- "true"
  }
  btn
}

#' The footer Close button.
#'
#' Dismisses through Bootstrap's own `data-bs-dismiss`, so it works even if
#' no server observer is listening. Shiny removes the modal wrapper on
#' `hidden.bs.modal`, exactly as it does for its own modals.
psa_dialog_close_button <- function(label = "Close") {
  shiny::tags$button(
    type = "button",
    class = "btn psa-dialog__btn psa-dialog__btn--ghost",
    `data-bs-dismiss` = "modal",
    `data-dismiss` = "modal",
    label
  )
}

#' A footer action that reports to the server (e.g. "View in Search").
#'
#' Does NOT self-dismiss: the server decides whether the action succeeded
#' and calls `psa_dialog_close()`, so the dialog can never vanish on an
#' action that did not happen.
psa_dialog_action_button <- function(input_id, label, ..., class = NULL, icon = NULL) {
  shiny::actionButton(
    input_id,
    label = shiny::tagList(icon, label),
    class = paste(c("psa-dialog__btn psa-dialog__btn--primary", class), collapse = " "),
    ...
  )
}

#' Neutral empty state for a dialog body.
psa_dialog_empty_ui <- function(message) {
  shiny::tags$p(class = "psa-dialog__empty text-muted", message)
}


# --- View in Search -----------------------------------------------------

#' Send the Search screen to one canonical classification record.
#'
#' Used by UI-02's hierarchy browser and UI-03's detail dialogs. It changes
#' NOTHING about search semantics: it drives the existing public Search
#' inputs (docs/UI_CONTRACT.md section 4) exactly as a user typing the code
#' would, then selects the matching row in the existing results table. The
#' repository is never queried here and no code is fabricated -- `entry` is
#' a canonical row that a service already returned.
#'
#' @param entry A one-row classification tibble (canonical schema).
#' @param session The Shiny session.
#' @param results Optional reactive returning the Search results data frame.
#'   When supplied, the matching row is selected once the table refreshes.
#' @param table_id character(1). The Search results DT output id.
#'
#' @return Invisibly, the code that was applied, or NULL for an empty entry.
view_in_search_apply <- function(entry,
                                 session = shiny::getDefaultReactiveDomain(),
                                 results = NULL,
                                 table_id = "classification_results") {
  if (is.null(entry) || nrow(entry) == 0L) {
    return(invisible(NULL))
  }
  entry <- entry[1, , drop = FALSE]
  code <- entry$code

  # Edition is a radio group on the Search sidebar, system is a select.
  shiny::updateSelectInput(session, "classification_system", selected = entry$system)
  shiny::updateRadioButtons(session, "classification_version", selected = entry$version)
  shiny::updateTextInput(session, "classification_query", value = code)

  if (requireNamespace("bslib", quietly = TRUE)) {
    try(bslib::nav_select("main_nav", "search", session = session), silent = TRUE)
  }

  psa_dialog_close(session)

  # Select the row once the results table has caught up with the new query.
  # Self-destructing, and bounded so a code that never appears (an archived
  # edition the user then switches away from, say) cannot leak an observer.
  if (!is.null(results)) {
    attempts <- 0L
    obs <- shiny::observe({
      attempts <<- attempts + 1L
      d <- try(results(), silent = TRUE)
      done <- FALSE
      if (!inherits(d, "try-error") && is.data.frame(d) && nrow(d) > 0L) {
        idx <- which(d$code == code)
        if (length(idx) > 0L) {
          DT::selectRows(DT::dataTableProxy(table_id, session = session), idx[[1]])
          done <- TRUE
        }
      }
      if (done || attempts >= 10L) {
        obs$destroy()
      }
    })
  }

  invisible(code)
}
