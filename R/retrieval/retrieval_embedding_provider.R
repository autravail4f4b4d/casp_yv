# Provider abstraction for the OPTIONAL multilingual semantic retrieval tier.
#
# WHY THIS IS AN HTTP CLIENT AND NOT AN IN-PROCESS MODEL
# -----------------------------------------------------------------
# This application has no Python runtime and no `reticulate`, and the
# dependency surface is deliberately frozen (see CLAUDE.md, "Scope
# Restrictions"). A sentence-transformer therefore cannot be executed
# inside the R process. The only way to obtain multilingual embeddings
# without widening the dependency set is to call an embedding endpoint
# over HTTP with `httr2`, which is already locked.
#
# The consequence is deliberate and must be understood by whoever deploys
# this: the semantic tier is INERT unless an operator stands up an
# embedding endpoint and points the environment variables below at it.
# With no endpoint configured -- the default, and the state of the current
# environment -- every function here degrades to "unavailable" and the
# hybrid retriever runs on its lexical + fuzzy + n-gram tiers alone.
#
# ENVIRONMENT CONTRACT
# -----------------------------------------------------------------
#   RETRIEVAL_EMBEDDING_ENABLED  "true"/"false"   (default "false")
#   RETRIEVAL_EMBEDDING_URL      full endpoint URL, e.g.
#                                https://host/v1/embeddings
#   RETRIEVAL_EMBEDDING_MODEL    model identifier
#   RETRIEVAL_EMBEDDING_API_KEY  bearer token (optional: a self-hosted
#                                endpoint on a private network may need
#                                none)
#   RETRIEVAL_EMBEDDING_TIMEOUT  seconds, default 5
#
# One further variable, in the same family and read with the same
# helper, decides not whether a vector CAN be obtained but whether the
# result may carry any weight:
#
#   RETRIEVAL_SEMANTIC_MODE      "off" | "shadow" | "active"
#                                (default "off"; `active` is clamped to
#                                `shadow` in this release)
#
# It is defined in R/retrieval/retrieval_shadow.R. The two settings are
# deliberately orthogonal -- transport versus authority -- so a
# configured endpoint can sit at `off`, and `shadow` can be measured in
# a test with an injected encoder and no endpoint at all.
#
# Configuration lives entirely in the environment so that no endpoint and
# no credential is ever committed. `retrieval_embedding_config()` returns
# only `has_key`, never the key itself, precisely so that a config object
# can be printed, logged, `str()`-ed or embedded in a diagnostic without
# leaking the token.
#
# RECOMMENDED MODEL FAMILY (a deployment decision, NOT hardcoded)
# -----------------------------------------------------------------
# Queries arrive in English, Filipino/Tagalog, Cebuano/Bisaya, Taglish and
# mixed forms. A monolingual English encoder would place "tsuper ng
# trak" nowhere near "heavy truck driver", which is the entire reason a
# semantic tier would be worth having here. Suitable multilingual
# families:
#
#   * sentence-transformers/paraphrase-multilingual-MiniLM-L12-v2
#       384-dim, small and cheap to self-host, trained on paraphrase data
#       across 50+ languages. Good default for short occupation/industry
#       phrases.
#   * intfloat/multilingual-e5-{small,base,large}
#       Stronger retrieval quality; note the E5 family expects "query: "
#       and "passage: " prefixes, which is exactly the kind of
#       model-specific detail that must stay a deployment concern.
#   * BAAI/bge-m3
#       Best multilingual quality of the three, largest to host.
#
# Cebuano is only thinly represented in all of them, so the semantic tier
# is expected to SUPPLEMENT the curated synonym evidence, never to replace
# it. Model choice is set by RETRIEVAL_EMBEDDING_MODEL at deploy time.

# Default request timeout, in seconds. Short on purpose: this tier is
# optional, and a slow embedding endpoint must never make classification
# search feel broken. Exceeding it is a normal, non-fatal outcome.
RETRIEVAL_EMBEDDING_DEFAULT_TIMEOUT <- 5

.retrieval_env_chr <- function(name, default = "") {
  v <- Sys.getenv(name, unset = NA_character_)
  if (is.na(v)) return(default)
  v <- trimws(v)
  if (!nzchar(v)) return(default)
  v
}

.retrieval_env_flag <- function(name, default = FALSE) {
  v <- tolower(.retrieval_env_chr(name, ""))
  if (!nzchar(v)) return(default)
  v %in% c("true", "t", "yes", "y", "1", "on")
}

# Read the bearer token. Intentionally NOT part of the public config, and
# intentionally the only function in the repository that returns it.
.retrieval_embedding_key <- function() {
  .retrieval_env_chr("RETRIEVAL_EMBEDDING_API_KEY", "")
}

# Remove the credential from any string that is about to be surfaced to a
# user, a log or a warning. Belt-and-braces: nothing here deliberately
# includes the key, but an httr2/curl condition message is third-party
# text and is treated as untrusted for this purpose.
.retrieval_embedding_scrub <- function(msg) {
  msg <- paste(as.character(msg), collapse = " ")
  key <- .retrieval_embedding_key()
  if (nzchar(key)) msg <- gsub(key, "<redacted>", msg, fixed = TRUE)
  msg
}

#' Read the semantic tier's configuration from the environment.
#'
#' Never returns the API key. `has_key` reports only whether one is set,
#' so the result is safe to print, log or include in a diagnostic.
#'
#' @return A list with `enabled` (logical), `url` (character), `model`
#'   (character), `timeout` (numeric) and `has_key` (logical).
retrieval_embedding_config <- function() {
  timeout <- suppressWarnings(as.numeric(
    .retrieval_env_chr("RETRIEVAL_EMBEDDING_TIMEOUT",
                       as.character(RETRIEVAL_EMBEDDING_DEFAULT_TIMEOUT))
  ))
  if (length(timeout) != 1L || is.na(timeout) || timeout <= 0) {
    timeout <- RETRIEVAL_EMBEDDING_DEFAULT_TIMEOUT
  }

  list(
    enabled = .retrieval_env_flag("RETRIEVAL_EMBEDDING_ENABLED", FALSE),
    url     = .retrieval_env_chr("RETRIEVAL_EMBEDDING_URL", ""),
    model   = .retrieval_env_chr("RETRIEVAL_EMBEDDING_MODEL", ""),
    timeout = timeout,
    has_key = nzchar(.retrieval_embedding_key())
  )
}

#' A non-secret provider identifier for an index artifact.
#'
#' Section 14 requires the semantic index to record which provider and
#' model produced its vectors, so an artifact built against one encoder is
#' never queried with another. The obvious identifier -- the endpoint URL
#' -- can legitimately carry credentials in its userinfo
#' (`https://user:token@host/v1/embeddings`), and this string is written
#' into a committed-adjacent artifact and printed by the build script.
#' Everything before an `@`, along with any query string, is therefore
#' dropped: what remains is scheme, host, port and path.
#'
#' @param config Optional pre-read config; read from the environment when
#'   NULL.
#'
#' @return character(1) of the form "<scheme://host/path> <model>", or ""
#'   when nothing is configured. Never contains the API key.
retrieval_embedding_provider_id <- function(config = NULL) {
  cfg <- if (is.null(config)) retrieval_embedding_config() else config

  url <- if (is.character(cfg$url) && length(cfg$url) == 1L && !is.na(cfg$url)) cfg$url else ""
  model <- if (is.character(cfg$model) && length(cfg$model) == 1L && !is.na(cfg$model)) cfg$model else ""

  if (nzchar(url)) {
    scheme <- sub("^([A-Za-z][A-Za-z0-9+.-]*://).*$", "\\1", url)
    if (identical(scheme, url)) scheme <- ""
    rest <- substring(url, nchar(scheme) + 1L)
    # Strip userinfo: anything up to and including the LAST "@" before the
    # first "/" of the path.
    authority_end <- regexpr("/", rest, fixed = TRUE)
    authority <- if (authority_end > 0L) substr(rest, 1L, authority_end - 1L) else rest
    tail_path <- if (authority_end > 0L) substring(rest, authority_end) else ""
    at <- regexpr("@[^@]*$", authority)
    if (at > 0L) authority <- substring(authority, at + 1L)
    tail_path <- sub("[?#].*$", "", tail_path)
    url <- paste0(scheme, authority, tail_path)
  }

  out <- trimws(paste(url, model))
  # Belt and braces: the credential must never reach an artifact or a log.
  .retrieval_embedding_scrub(out)
}

#' Is the semantic tier configured well enough to attempt a call?
#'
#' A pure configuration check -- it performs NO network I/O, so it is safe
#' to call on every request and during app startup. A missing API key is
#' deliberately not disqualifying: a self-hosted endpoint on a private
#' network legitimately has none.
#'
#' @param config Optional pre-read config; read from the environment when
#'   NULL.
#'
#' @return logical(1).
retrieval_embedding_available <- function(config = NULL) {
  cfg <- if (is.null(config)) retrieval_embedding_config() else config
  isTRUE(cfg$enabled) &&
    is.character(cfg$url) && length(cfg$url) == 1L && nzchar(cfg$url) &&
    is.character(cfg$model) && length(cfg$model) == 1L && nzchar(cfg$model) &&
    requireNamespace("httr2", quietly = TRUE) &&
    requireNamespace("jsonlite", quietly = TRUE)
}

# Pull an (n x d) numeric matrix out of a decoded response body.
#
# Written against the OpenAI-compatible contract
#   {"data": [{"embedding": [...]}, ...]}
# but tolerant of the two other shapes commonly emitted by self-hosted
# servers, because pinning to one vendor's JSON would be a needless
# lock-in for an optional tier:
#   {"embeddings": [[...], ...]}      (text-embeddings-inference)
#   [[...], ...]                      (HF feature-extraction)
#
# Returns NULL for anything it cannot confidently interpret. It never
# guesses: a ragged or non-numeric payload is a failure, not something to
# be padded into shape.
.retrieval_embedding_parse <- function(body, n_expected) {
  rows <- NULL

  if (is.list(body) && !is.null(body$data) && is.list(body$data)) {
    rows <- lapply(body$data, function(el) if (is.list(el)) el$embedding else NULL)
  } else if (is.list(body) && !is.null(body$embeddings)) {
    rows <- body$embeddings
  } else if (is.list(body) && is.null(names(body))) {
    rows <- body
  }

  if (is.null(rows) || !is.list(rows) || length(rows) == 0L) return(NULL)

  rows <- lapply(rows, function(r) suppressWarnings(as.numeric(unlist(r, use.names = FALSE))))
  if (any(vapply(rows, is.null, logical(1)))) return(NULL)

  dims <- vapply(rows, length, integer(1))
  if (length(unique(dims)) != 1L || dims[1] == 0L) return(NULL)
  if (!is.null(n_expected) && length(rows) != n_expected) return(NULL)

  m <- matrix(unlist(rows, use.names = FALSE), nrow = length(rows), byrow = TRUE)
  if (!is.numeric(m) || any(!is.finite(m))) return(NULL)
  m
}

#' Embed a character vector via the configured endpoint.
#'
#' THIS FUNCTION NEVER THROWS AND NEVER LOGS THE CREDENTIAL. Every failure
#' mode -- disabled config, missing httr2, connection refused, DNS
#' failure, timeout, non-2xx status, non-JSON body, unrecognised JSON
#' shape, ragged/short/non-finite vectors -- collapses to NULL plus at
#' most one scrubbed `warning()`. Callers treat NULL as "the semantic tier
#' has nothing to contribute" and continue with the deterministic tiers.
#'
#' @param texts character vector to embed.
#' @param config Optional pre-read config; read from the environment when
#'   NULL.
#'
#' @return A numeric matrix with one row per input text, or NULL.
retrieval_embed_texts <- function(texts, config = NULL) {
  cfg <- if (is.null(config)) retrieval_embedding_config() else config

  texts <- tryCatch(as.character(texts), error = function(e) NULL)
  if (is.null(texts) || length(texts) == 0L) return(NULL)
  texts[is.na(texts)] <- ""

  if (!retrieval_embedding_available(cfg)) return(NULL)

  key <- .retrieval_embedding_key()
  headers <- list("Content-Type" = "application/json")
  if (nzchar(key)) headers[["Authorization"]] <- paste("Bearer", key)

  out <- tryCatch({
    req <- httr2::request(cfg$url)
    req <- do.call(httr2::req_headers, c(list(req), headers))
    req <- httr2::req_body_json(req, list(model = cfg$model, input = as.list(texts)))
    req <- httr2::req_timeout(req, cfg$timeout)
    # Turn httr2's own status-based error into a value we inspect, so a
    # 401/429/500 takes the same quiet NULL path as a timeout instead of
    # surfacing provider internals to a public user.
    req <- httr2::req_error(req, is_error = function(resp) FALSE)
    # Retries are deliberately NOT configured: this runs inside a user's
    # search request and a retry storm would be worse than no result.
    resp <- httr2::req_perform(req)

    status <- httr2::resp_status(resp)
    if (!is.numeric(status) || status < 200 || status >= 300) {
      warning(sprintf(
        "Retrieval embedding endpoint returned HTTP %s; semantic tier skipped.",
        status
      ), call. = FALSE)
      return(NULL)
    }

    raw_body <- httr2::resp_body_string(resp)
    parsed <- tryCatch(
      jsonlite::fromJSON(raw_body, simplifyVector = FALSE),
      error = function(e) NULL
    )
    if (is.null(parsed)) {
      warning("Retrieval embedding response was not valid JSON; semantic tier skipped.",
              call. = FALSE)
      return(NULL)
    }

    m <- .retrieval_embedding_parse(parsed, n_expected = length(texts))
    if (is.null(m)) {
      warning("Retrieval embedding response had an unusable shape; semantic tier skipped.",
              call. = FALSE)
      return(NULL)
    }
    m
  }, error = function(e) {
    warning(paste0("Retrieval embedding request failed; semantic tier skipped: ",
                   .retrieval_embedding_scrub(conditionMessage(e))), call. = FALSE)
    NULL
  })

  out
}

#' L2-normalize the rows of a numeric matrix.
#'
#' Document and query vectors are stored unit-length so that cosine
#' similarity reduces to a single matrix-vector product at query time.
#' Zero-length rows stay zero, which scores 0 against everything rather
#' than producing NaN.
#'
#' @param m numeric matrix.
#'
#' @return numeric matrix of the same shape, or NULL if `m` is unusable.
retrieval_embedding_l2_normalize <- function(m) {
  if (is.null(m) || !is.numeric(m)) return(NULL)
  if (is.null(dim(m))) m <- matrix(m, nrow = 1L)
  if (nrow(m) == 0L || ncol(m) == 0L) return(NULL)

  norms <- sqrt(rowSums(m * m))
  norms[!is.finite(norms) | norms <= 0] <- 1
  m / norms
}
