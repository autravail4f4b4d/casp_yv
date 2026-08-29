# Lucide icon set, inlined as local SVG.
#
# HANDOFF-CLAUDE-CODE.md v2.0 §21 specifies Lucide and names the exact
# glyphs the design uses. The reference design file loads them from a CDN;
# this application must not, so each glyph's path data is inlined here.
#
# Why inline SVG rather than a font or a package:
#   * no third-party runtime request -- a public deployment discloses no
#     visitor IP to a CDN and works on restricted networks;
#   * no new dependency, so renv.lock and the Connect manifest are
#     untouched (the previous Phosphor implementation shipped a vendored
#     .woff2, which is heavier than eleven inline paths and fails closed to
#     a blank square rather than degrading);
#   * the glyph inherits `currentColor`, so a single CSS colour rule themes
#     every icon.
#
# Icons here are DECORATIVE. Every one is paired with a visible text label
# at its call site, so each carries aria-hidden="true" and no title. An
# icon that ever becomes the sole content of a control needs an aria-label
# on the control itself, not a title here (handoff §16).
#
# Path data is Lucide's, which is ISC-licensed.

# Glyph name -> inner SVG markup. Lucide's canonical 24x24 viewBox with a
# 2px stroke; the wrapper below scales it.
LUCIDE_PATHS <- list(
  # Nav
  search = '<circle cx="11" cy="11" r="8"/><path d="m21 21-4.3-4.3"/>',
  `arrow-left-right` = '<path d="M8 3 4 7l4 4"/><path d="M4 7h16"/><path d="m16 21 4-4-4-4"/><path d="M20 17H4"/>',
  split = '<path d="M16 3h5v5"/><path d="M8 3H3v5"/><path d="M12 22v-8.3a4 4 0 0 0-1.172-2.872L3 3"/><path d="m15 9 6-6"/>',
  sparkles = '<path d="M9.937 15.5A2 2 0 0 0 8.5 14.063l-6.135-1.582a.5.5 0 0 1 0-.962L8.5 9.936A2 2 0 0 0 9.937 8.5l1.582-6.135a.5.5 0 0 1 .963 0L14.063 8.5A2 2 0 0 0 15.5 9.937l6.135 1.581a.5.5 0 0 1 0 .964L15.5 14.063a2 2 0 0 0-1.437 1.437l-1.582 6.135a.5.5 0 0 1-.963 0z"/><path d="M20 3v4"/><path d="M22 5h-4"/><path d="M4 17v2"/><path d="M5 18H3"/>',
  info = '<circle cx="12" cy="12" r="10"/><path d="M12 16v-4"/><path d="M12 8h.01"/>',

  # Inline / status
  merge = '<path d="m8 6 4-4 4 4"/><path d="M12 2v10.3a4 4 0 0 1-1.172 2.872L4 22"/><path d="m20 22-5-5"/>',
  `circle-check` = '<circle cx="12" cy="12" r="10"/><path d="m9 12 2 2 4-4"/>',
  `triangle-alert` = '<path d="m21.73 18-8-14a2 2 0 0 0-3.48 0l-8 14A2 2 0 0 0 4 21h16a2 2 0 0 0 1.73-3"/><path d="M12 9v4"/><path d="M12 17h.01"/>',
  `circle-help` = '<circle cx="12" cy="12" r="10"/><path d="M9.09 9a3 3 0 0 1 5.83 1c0 2-3 3-3 3"/><path d="M12 17h.01"/>',

  # Controls
  `rotate-cw` = '<path d="M21 12a9 9 0 1 1-9-9c2.52 0 4.93 1 6.74 2.74L21 8"/><path d="M21 3v5h-5"/>',
  square = '<rect width="18" height="18" x="3" y="3" rx="2"/>',
  `arrow-up` = '<path d="m5 12 7-7 7 7"/><path d="M12 19V5"/>'
)

#' Inline a Lucide glyph as local SVG.
#'
#' @param name character(1). One of `names(LUCIDE_PATHS)`.
#' @param size numeric(1). Rendered edge length in px. 18 for nav, 20 for
#'   inline/status, 14-17 inside buttons and notices (handoff §21).
#' @param class character(1) or NULL. Extra CSS class(es).
#'
#' @return An HTML `<svg>` tag, `aria-hidden`, inheriting `currentColor`.
#'   An unknown name is a hard error rather than a silently blank icon --
#'   a missing glyph is a build mistake, not a runtime state.
lucide_icon <- function(name, size = 18, class = NULL) {
  path <- LUCIDE_PATHS[[name]]
  if (is.null(path)) {
    stop(sprintf(
      "Unknown Lucide glyph '%s'. Available: %s",
      name, paste(names(LUCIDE_PATHS), collapse = ", ")
    ), call. = FALSE)
  }

  shiny::HTML(sprintf(
    paste0(
      '<svg class="%s" width="%s" height="%s" viewBox="0 0 24 24" fill="none" ',
      'stroke="currentColor" stroke-width="2" stroke-linecap="round" ',
      'stroke-linejoin="round" aria-hidden="true" focusable="false">%s</svg>'
    ),
    paste(c("lucide", class), collapse = " "),
    size, size, path
  ))
}
