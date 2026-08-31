# The OPTIONAL semantic candidate generator.
#
# Contract with the rest of the hybrid retriever: this file exposes one
# candidate generator with the same signature shape as the fuzzy and
# n-gram tiers, and it FAILS OPEN. When no embedding backend is
# configured -- the default -- `retrieval_embeddings_candidates()` returns
# `retrieval_no_candidates()`, `retrieval_rrf()` drops the empty set, and
# Search / Dual Search / RM behave exactly as they do today. Nothing in
# this file may ever be able to break classification retrieval.
#
# COST MODEL
# -----------------------------------------------------------------
# Document vectors are computed ONCE, offline, by
# scripts/build_retrieval_embeddings.R and stored as an .rds. At runtime
# only the user's query is embedded: one short HTTP call, then one
# matrix-vector product. Embedding the corpus per request would be
# unaffordable and is never done.
#
# WHAT A COSINE SCORE IS AND IS NOT
# -----------------------------------------------------------------
# The score returned here is the cosine of the angle between a query
# vector and a document vector in an embedding space. IT IS NOT A
# PROBABILITY THAT A CLASSIFICATION IS CORRECT, and it must never be
# presented to a user, or to the model, as a confidence that a code is the
# right answer. It orders candidates for a downstream verification step
# against the canonical repository; that verification, not this number,
# decides what may be shown. This is the same rule as CLAUDE.md's
# "no retrieved code = no classification code presented as the answer":
# a high cosine is not retrieval, it is a suggestion of where to look.
#
# Consistent with the evidence hierarchy in CLAUDE.md, semantic
# similarity sits at the BOTTOM of the ordering. It may surface a
# candidate; it may never outrank an exact code or exact label match.
#
# SEMANTIC DOCUMENTS ARE NOT LABELS
# -----------------------------------------------------------------
# `retrieval_embedding_documents()` builds a richer text per canonical row
# than the bare label: canonical current label, official description where
# the canonical table actually carries one, the immediate parent label as
# hierarchy context, the classification level, and -- for PSOC only --
# survey-guidance and curated occupation PHRASES whose code was verified
# against the current edition at build time. For PSIC, survey-guidance
# ACTIVITY WORDING is admitted as semantic text only and its historical
# 2009/2019 code is never carried into a current document, never stored,
# and never authoritative. See sections 10 and 11 of
# SEMANTIC_RETRIEVAL_AND_CONTEXT_CONSISTENCY_HARDENING.md.

# On-disk index schema. Bumped when the artifact layout changes, so a
# stale artifact built by an earlier version is rejected rather than
# silently misread. v1 stored a label-only vector set with a single
# fingerprint and no system/version/code identity.
RETRIEVAL_EMBEDDING_INDEX_VERSION <- 2L

# Document-construction ("recipe") version. Bumped whenever the TEXT that
# gets embedded is constructed differently, even if the artifact layout is
# unchanged: the same corpus embedded under a different recipe produces
# vectors that are not comparable with queries built under the new one.
# v1 = normalized canonical label only.
# v2 = label + description + hierarchy + level + verified phrase evidence.
RETRIEVAL_EMBEDDING_DOC_RECIPE_VERSION <- 2L

# Hard cap on a single document's length, in characters, applied after
# assembly and truncated on a token boundary. Embedding endpoints charge
# and truncate by token; an unbounded document would let one verbose
# canonical description dominate the build cost and dilute the vector.
RETRIEVAL_EMBEDDING_DOC_MAX_CHARS <- 512L

# Runtime query-embedding cache bound (section 51). Small on purpose: this
# exists to stop a repeated query inside one session from paying for a
# second remote call, not to be a general-purpose store.
RETRIEVAL_EMBEDDING_QUERY_CACHE_MAX <- 512L

# A cheap, dependency-free, deterministic fingerprint of a text vector.
#
# Purpose is narrow: detect that an index was built against DIFFERENT
# classification data, or under a different document recipe, than the one
# it is now being used with. It is not a cryptographic digest and is not
# used for any security decision, which is why base arithmetic is
# preferred over adding a hashing dependency.
.retrieval_embedding_fingerprint <- function(texts) {
  texts <- as.character(texts)
  texts[is.na(texts)] <- ""
  n <- length(texts)
  if (n == 0L) return("v1-0-0-0-0")

  s <- paste(texts, collapse = "")
  v <- utf8ToInt(s)
  if (length(v) == 0L) return(paste0("v1-", n, "-0-0-0"))

  # Position-weighted sum: sensitive to reordering as well as to content.
  # Values are reduced before multiplication so the running totals stay
  # well inside a double's exact-integer range for any realistic corpus.
  cv <- as.numeric(v %% 65536L)
  w <- as.numeric((seq_along(v) %% 8191L) + 1L)
  a <- sum(cv * w) %% 2147483647
  b <- sum((cv %% 251) * (cv %% 251)) %% 2147483647

  paste0("v1-", n, "-", nchar(s), "-",
         format(a, scientific = FALSE), "-", format(b, scientific = FALSE))
}

# Deliberately local rather than a shared `%||%`: this file must not
# install an infix operator into the global environment that Shiny, rlang
# or another workstream's file might also define.
.retrieval_first_chr <- function(x) {
  if (is.null(x) || length(x) == 0L) return("")
  x <- as.character(x)[1L]
  if (is.na(x)) "" else x
}

.retrieval_embedding_int <- function(x, default) {
  if (is.null(x) || length(x) == 0L) return(as.integer(default))
  v <- suppressWarnings(as.integer(x)[1L])
  if (is.na(v)) as.integer(default) else v
}

.retrieval_embedding_chr <- function(x, n) {
  if (is.null(x)) return(rep("", n))
  out <- as.character(x)
  if (length(out) != n) return(rep("", n))
  out[is.na(out)] <- ""
  out
}

# ---------------------------------------------------------------------
# Canonical row identity
# ---------------------------------------------------------------------
#
# The identity text is what `retrieval_embeddings_index_is_valid()`
# fingerprints, and it is deliberately NOT the embedded document: the
# validator runs at app startup with only a `retrieval_corpus()` in hand
# (see `retrieval_index_for()` in retrieval_engine.R), which carries no
# descriptions, no hierarchy and no guidance evidence. Identity is
# therefore built from the two things a corpus always has and that
# uniquely pin a row to a canonical record: its normalized code and its
# normalized label.
#
# Code is included as well as label because two rows can legitimately
# share a label across levels, and because a re-coding with unchanged
# wording is exactly the silent substitution the classification rules
# forbid.
.retrieval_embedding_identity_texts <- function(corpus) {
  if (is.null(corpus) || is.null(corpus$n) || corpus$n == 0L) return(character(0))
  n <- as.integer(corpus$n)
  code <- .retrieval_embedding_chr(corpus$code_key, n)
  label <- .retrieval_embedding_chr(corpus$label_key, n)
  # Interleaved rather than concatenated with a separator: the fingerprint
  # is position-weighted and length-aware, so two fields kept as two
  # elements cannot blur into one another and no separator character has to
  # be assumed absent from a code key.
  as.character(c(rbind(code, label)))
}

# The v1 recipe, retained as the corpus-only fallback.
#
# Used when `retrieval_embeddings_build()` is handed a corpus with no
# canonical table alongside it (tests, ad-hoc tooling). It is the SHARED
# normalized label key from retrieval_corpus(), not a private variant:
# query and document must traverse an identical text pipeline or the two
# vectors are not comparable. Singularization is skipped here (unlike the
# lexical tier) because a multilingual encoder handles morphology itself,
# and folding plurals would discard signal it can use.
.retrieval_embedding_doc_texts <- function(corpus) {
  if (is.null(corpus) || is.null(corpus$n) || corpus$n == 0L) return(character(0))
  txt <- as.character(corpus$label_key)
  fallback <- as.character(corpus$text_key)
  blank <- is.na(txt) | !nzchar(txt)
  if (any(blank) && length(fallback) == length(txt)) txt[blank] <- fallback[blank]
  txt[is.na(txt)] <- ""
  txt
}

# The query goes through the same normalization the documents did.
.retrieval_embedding_query_text <- function(query) {
  if (is.null(query) || length(query) != 1L) return(NA_character_)
  if (is.na(query)) return(NA_character_)
  q <- retrieval_normalize(as.character(query))
  if (length(q) != 1L || is.na(q) || !nzchar(q)) return(NA_character_)
  q
}

# ---------------------------------------------------------------------
# Document construction (spec sections 10 and 11)
# ---------------------------------------------------------------------

#' Which document recipe applies to a classification system?
#'
#' PSOC and PSIC get named recipes because their evidence sources differ:
#' PSOC admits code-verified occupation phrases, PSIC admits activity
#' wording as text only. Every other system falls back to the generic
#' recipe (label + description + hierarchy + level), which is correct for
#' them and adds no system-specific assumptions.
#'
#' @param system character(1) or NULL.
#'
#' @return one of "psoc", "psic", "generic".
retrieval_embedding_doc_recipe <- function(system) {
  s <- tolower(.retrieval_first_chr(system))
  if (identical(s, "psoc")) return("psoc")
  if (identical(s, "psic")) return("psic")
  "generic"
}

# Trim an assembled, already-normalized document on a token boundary.
.retrieval_embedding_truncate <- function(x, max_chars = RETRIEVAL_EMBEDDING_DOC_MAX_CHARS) {
  long <- !is.na(x) & nchar(x) > max_chars
  if (!any(long)) return(x)
  x[long] <- vapply(x[long], function(s) {
    cut <- substr(s, 1L, max_chars)
    sp <- regexpr(" [^ ]*$", cut)
    if (sp > 1L) substr(cut, 1L, sp - 1L) else cut
  }, character(1))
  x
}

# Normalize a set of parallel segment vectors and join them into one
# document per row. Normalization is applied PER SEGMENT and the join is a
# plain space, because `retrieval_normalize()` would reduce any visible
# separator to a space anyway -- pretending otherwise would only make the
# stored text differ from what the model actually sees.
.retrieval_embedding_assemble <- function(segments, n) {
  parts <- lapply(segments, function(seg) {
    v <- .retrieval_embedding_chr(seg, n)
    v <- retrieval_normalize(v)
    v[is.na(v)] <- ""
    v
  })
  out <- character(n)
  for (i in seq_len(n)) {
    pieces <- vapply(parts, function(p) p[i], character(1))
    pieces <- pieces[nzchar(pieces)]
    out[i] <- paste(pieces, collapse = " ")
  }
  .retrieval_embedding_truncate(out)
}

# Immediate parent label per row, resolved through parent_code.
#
# Hierarchy is canonical current evidence and is the only structural
# context these tables carry now that `description` is empty across both
# PSOC 2022 and PSIC 2026 (measured: 0 of 649 and 0 of 2202 rows have a
# description). It is what supplies the education-level and
# government-level qualifiers section 10.2 asks for -- "Education",
# "Public Administration and Defence" and so on arrive as the section
# label of the rows beneath them.
.retrieval_embedding_parent_labels <- function(data) {
  n <- nrow(data)
  if (is.null(data$parent_code) || is.null(data$code)) return(rep("", n))
  code <- as.character(data$code)
  parent <- as.character(data$parent_code)
  label <- as.character(data$label)
  hit <- match(parent, code)
  out <- rep("", n)
  ok <- !is.na(hit)
  out[ok] <- label[hit[ok]]
  out[is.na(out)] <- ""
  out
}

# Look a build-time evidence table up out of the session, without taking a
# hard dependency on the file that defines it.
#
# The PSA survey-guidance constants live in R/assistant/, which is owned by
# a different workstream. Reading them through `exists()` means this file
# never sources that one, never breaks if it is mid-edit, and simply
# records "no guidance evidence" when it has not been loaded.
.retrieval_embedding_global <- function(name) {
  if (!exists(name, inherits = TRUE)) return(NULL)
  out <- tryCatch(get(name, inherits = TRUE), error = function(e) NULL)
  if (is.null(out) || !is.list(out) || length(out) == 0L) return(NULL)
  out
}

# PSOC occupation phrases, keyed by CURRENT canonical code.
#
# Every phrase is admitted only when its recorded code is present in the
# current edition being indexed. A guidance row naming a code this edition
# no longer has contributes nothing -- it is not re-pointed at a
# "nearby" code, because guessing a replacement is precisely the silent
# substitution the classification rules forbid.
.retrieval_embedding_psoc_phrases <- function(codes, guidance = NULL) {
  n <- length(codes)
  out <- rep("", n)
  used <- rep(FALSE, n)

  rows <- guidance
  if (is.null(rows)) rows <- .retrieval_embedding_global("ASSISTANT_GUIDANCE_PSOC_EXAMPLES")
  if (is.null(rows)) return(list(text = out, used = used))

  terms <- vapply(rows, function(r) .retrieval_first_chr(r$term), character(1))
  cds <- vapply(rows, function(r) .retrieval_first_chr(r$code), character(1))
  keep <- nzchar(terms) & nzchar(cds)
  terms <- terms[keep]; cds <- cds[keep]
  if (!length(terms)) return(list(text = out, used = used))

  hit <- match(cds, as.character(codes))
  for (i in seq_along(terms)) {
    if (is.na(hit[i])) next
    j <- hit[i]
    out[j] <- if (nzchar(out[j])) paste(out[j], terms[i]) else terms[i]
    used[j] <- TRUE
  }
  list(text = out, used = used)
}

# Curated occupation terminology, keyed by CURRENT canonical code.
#
# Same admission rule as the survey-guidance phrases: the curated code must
# exist in the edition being indexed, or the phrase is dropped.
.retrieval_embedding_curated_phrases <- function(codes, curated = NULL) {
  n <- length(codes)
  out <- rep("", n)
  used <- rep(FALSE, n)
  if (is.null(curated) || !is.data.frame(curated) || nrow(curated) == 0L) {
    return(list(text = out, used = used))
  }
  if (!all(c("occupation", "curated_psoc") %in% names(curated))) {
    return(list(text = out, used = used))
  }

  phrase <- as.character(curated$occupation)
  cds <- as.character(curated$curated_psoc)
  keep <- !is.na(phrase) & nzchar(phrase) & !is.na(cds) & nzchar(cds)
  phrase <- phrase[keep]; cds <- cds[keep]
  if (!length(phrase)) return(list(text = out, used = used))

  hit <- match(cds, as.character(codes))
  for (i in seq_along(phrase)) {
    if (is.na(hit[i])) next
    j <- hit[i]
    out[j] <- if (nzchar(out[j])) paste(out[j], phrase[i]) else phrase[i]
    used[j] <- TRUE
  }
  list(text = out, used = used)
}

# PSIC activity wording, attached as SEMANTIC TEXT ONLY.
#
# The survey-guidance activity hints carry a 2009/2019 PSIC code purely for
# audit. That code is historical and is NEVER written into a current
# document, never stored on the index, and never returned as a candidate:
# section 10.2 forbids placing an old PSIC code into a current semantic
# document as if it were current, and a 2019 code resolved against a 2026
# table would be exactly that.
#
# The wording is instead re-resolved against the CURRENT labels by
# deterministic phrase containment -- equality of the normalized activity
# with a current normalized label, or the activity phrase appearing whole
# inside one. No fuzzy matching and no nearest-neighbour fallback: an
# activity that does not land on a current label contributes nothing.
.retrieval_embedding_psic_phrases <- function(label_norm, guidance = NULL) {
  n <- length(label_norm)
  out <- rep("", n)
  used <- rep(FALSE, n)

  rows <- guidance
  if (is.null(rows)) rows <- .retrieval_embedding_global("ASSISTANT_GUIDANCE_PSIC_ACTIVITY_HINTS")
  if (is.null(rows)) return(list(text = out, used = used))

  for (r in rows) {
    activity <- .retrieval_first_chr(r$activity)
    term <- .retrieval_first_chr(r$term)
    if (!nzchar(activity)) next
    a <- retrieval_normalize(activity)
    if (is.na(a) || !nzchar(a)) next

    j <- which(label_norm == a)
    if (!length(j)) {
      j <- which(nzchar(label_norm) &
                   vapply(label_norm, function(l) grepl(a, l, fixed = TRUE), logical(1)))
    }
    if (!length(j)) next

    phrase <- if (nzchar(term)) paste(term, activity) else activity
    for (jj in j) {
      out[jj] <- if (nzchar(out[jj])) paste(out[jj], phrase) else phrase
      used[jj] <- TRUE
    }
  }
  list(text = out, used = used)
}

#' Build the semantic documents and their provenance for a canonical table.
#'
#' BUILD TIME ONLY. This is the single definition of what text gets
#' embedded, so the build script and the tests cannot drift apart.
#'
#' @param data A canonical classification tibble with at least `code` and
#'   `label`; `description`, `level`, `parent_code`, `system` and `version`
#'   are used when present.
#' @param system,version character(1) or NULL. Default to the values
#'   carried on `data`. They select the recipe and are recorded on the
#'   index; they are NOT embedded as text.
#' @param guidance NULL to resolve the PSA survey-guidance evidence from
#'   the session if it has been loaded, `FALSE` to use none, or an explicit
#'   list of guidance rows (for tests).
#' @param curated NULL to load `data-raw/curated_psoc_overrides.csv` when
#'   it can be found, `FALSE` to use none, or an explicit data.frame.
#'
#' @return A list with `text` (character, one document per row),
#'   `recipe`, `doc_recipe_version` and `provenance` (a data.frame carrying
#'   the section 11 fields). Never NULL for a non-empty `data`.
retrieval_embedding_documents <- function(data, system = NULL, version = NULL,
                                          guidance = NULL, curated = NULL) {
  if (is.null(data) || !is.data.frame(data) || nrow(data) == 0L) {
    return(list(
      text = character(0),
      recipe = retrieval_embedding_doc_recipe(system),
      doc_recipe_version = RETRIEVAL_EMBEDDING_DOC_RECIPE_VERSION,
      provenance = .retrieval_embedding_empty_provenance()
    ))
  }

  n <- nrow(data)
  system <- if (!is.null(system)) .retrieval_first_chr(system) else .retrieval_first_chr(data$system)
  version <- if (!is.null(version)) .retrieval_first_chr(version) else .retrieval_first_chr(data$version)
  recipe <- retrieval_embedding_doc_recipe(system)

  code <- .retrieval_embedding_chr(data$code, n)
  label <- .retrieval_embedding_chr(data$label, n)
  description <- .retrieval_embedding_chr(data$description, n)
  level <- .retrieval_embedding_chr(data$level, n)
  parent_label <- .retrieval_embedding_parent_labels(data)

  label_norm <- retrieval_normalize(label)
  label_norm[is.na(label_norm)] <- ""

  # Guidance and curated evidence are opt-out (FALSE), not opt-in, so a
  # build that has the evidence loaded uses it without extra ceremony.
  psoc_ev <- list(text = rep("", n), used = rep(FALSE, n))
  psic_ev <- list(text = rep("", n), used = rep(FALSE, n))
  curated_ev <- list(text = rep("", n), used = rep(FALSE, n))

  if (!identical(guidance, FALSE)) {
    g <- if (is.list(guidance)) guidance else NULL
    if (identical(recipe, "psoc")) {
      psoc_ev <- .retrieval_embedding_psoc_phrases(code, guidance = g)
    } else if (identical(recipe, "psic")) {
      psic_ev <- .retrieval_embedding_psic_phrases(label_norm, guidance = g)
    }
  }
  if (identical(recipe, "psoc") && !identical(curated, FALSE)) {
    tbl <- if (is.data.frame(curated)) curated else .retrieval_embedding_load_curated()
    curated_ev <- .retrieval_embedding_curated_phrases(code, curated = tbl)
  }

  # Segment order is deliberate: the canonical current label first, so a
  # truncated document keeps the authoritative wording; the derived and
  # supplementary evidence last, so truncation sheds the weakest evidence
  # first.
  text <- .retrieval_embedding_assemble(
    list(
      label,
      description,
      parent_label,
      level,
      psoc_ev$text,
      curated_ev$text,
      psic_ev$text
    ),
    n
  )

  # A row whose label normalizes to nothing would otherwise embed an empty
  # string and score identically against every query. Fall back to the
  # code text so it at least stays addressable.
  blank <- !nzchar(text)
  if (any(blank)) text[blank] <- retrieval_normalize_code(code[blank])
  text[is.na(text)] <- ""

  used_label <- nzchar(label_norm)
  used_desc <- nzchar(retrieval_normalize(description))
  used_hier <- nzchar(retrieval_normalize(parent_label))
  used_level <- nzchar(retrieval_normalize(level))

  sources <- vapply(seq_len(n), function(i) {
    s <- character(0)
    if (used_label[i]) s <- c(s, "current_label")
    if (used_desc[i]) s <- c(s, "current_description")
    if (used_hier[i]) s <- c(s, "hierarchy_parent_label")
    if (used_level[i]) s <- c(s, "classification_level")
    if (psoc_ev$used[i]) s <- c(s, "survey_guidance_occupation_phrase")
    if (curated_ev$used[i]) s <- c(s, "curated_terminology")
    if (psic_ev$used[i]) s <- c(s, "historical_activity_text")
    paste(s, collapse = ";")
  }, character(1))

  provenance <- data.frame(
    row_index = seq_len(n),
    code = code,
    semantic_document_sources = sources,
    current_label_used = used_label,
    current_description_used = used_desc,
    hierarchy_used = used_hier,
    classification_level_used = used_level,
    survey_guidance_used = psoc_ev$used,
    curated_terminology_used = curated_ev$used,
    historical_activity_text_used = psic_ev$used,
    # Invariant, not a computed value: no historical code is ever carried
    # into a current semantic document, so nothing here can be
    # authoritative on the strength of a historical edition.
    historical_code_authoritative = rep(FALSE, n),
    stringsAsFactors = FALSE
  )

  list(
    text = text,
    recipe = recipe,
    doc_recipe_version = RETRIEVAL_EMBEDDING_DOC_RECIPE_VERSION,
    provenance = provenance
  )
}

.retrieval_embedding_empty_provenance <- function() {
  data.frame(
    row_index = integer(0), code = character(0),
    semantic_document_sources = character(0),
    current_label_used = logical(0), current_description_used = logical(0),
    hierarchy_used = logical(0), classification_level_used = logical(0),
    survey_guidance_used = logical(0), curated_terminology_used = logical(0),
    historical_activity_text_used = logical(0),
    historical_code_authoritative = logical(0),
    stringsAsFactors = FALSE
  )
}

# Curated PSOC terminology, if the file can be found from wherever the
# caller happens to be running. Absence is normal, not an error.
.retrieval_embedding_load_curated <- function(path = NULL) {
  paths <- if (!is.null(path)) path else c(
    "data-raw/curated_psoc_overrides.csv",
    "../data-raw/curated_psoc_overrides.csv",
    "../../data-raw/curated_psoc_overrides.csv"
  )
  for (p in paths) {
    if (!file.exists(p)) next
    out <- tryCatch(
      utils::read.csv(p, colClasses = "character", stringsAsFactors = FALSE,
                      encoding = "UTF-8"),
      error = function(e) NULL
    )
    if (is.data.frame(out) && nrow(out) > 0L) return(out)
  }
  NULL
}

# ---------------------------------------------------------------------
# Index build / load / validate
# ---------------------------------------------------------------------

#' Build a semantic index over a retrieval corpus. BUILD TIME ONLY.
#'
#' Embeds every document once and stores L2-normalized vectors alongside
#' the metadata needed to detect a stale artifact later. This is called by
#' scripts/build_retrieval_embeddings.R, never from a running Shiny
#' session.
#'
#' @param corpus A corpus from `retrieval_corpus()`.
#' @param config Optional pre-read provider config.
#' @param embed_fn Optional embedding function taking a character vector
#'   and returning an (n x d) numeric matrix or NULL. Defaults to the HTTP
#'   provider. Exists so the build script can batch, and so tests can
#'   exercise this code with no network.
#' @param batch_size integer(1) texts per provider call.
#' @param data Optional canonical tibble aligned row-for-row with `corpus`.
#'   Supplying it selects the v2 document recipe; omitting it falls back to
#'   the label-only text the corpus alone can supply.
#' @param system,version,level character(1) or NULL. Recorded on the index
#'   so a PSOC artifact can never be accepted for a PSIC corpus.
#' @param documents Optional pre-built result of
#'   `retrieval_embedding_documents()`, for tooling that wants to inspect
#'   or cache the text before paying for embeddings.
#'
#' @return An index list of class "retrieval_embedding_index", or NULL if
#'   the corpus is empty, the inputs are misaligned, or embedding failed.
#'   Never throws.
retrieval_embeddings_build <- function(corpus, config = NULL, embed_fn = NULL,
                                       batch_size = 64L, data = NULL,
                                       system = NULL, version = NULL,
                                       level = NULL, documents = NULL) {
  cfg <- if (is.null(config)) retrieval_embedding_config() else config
  fn <- if (is.null(embed_fn)) function(x) retrieval_embed_texts(x, cfg) else embed_fn

  if (is.null(corpus) || is.null(corpus$n) || corpus$n == 0L) return(NULL)
  n <- as.integer(corpus$n)

  # A canonical table that does not line up row-for-row with the corpus
  # would attach the wrong document to a row and, through it, the wrong
  # code to a vector. Refuse rather than fall back silently.
  if (!is.null(data)) {
    if (!is.data.frame(data) || nrow(data) != n) return(NULL)
  }

  if (is.null(documents)) {
    documents <- if (!is.null(data)) {
      retrieval_embedding_documents(data, system = system, version = version)
    } else {
      list(
        text = .retrieval_embedding_doc_texts(corpus),
        recipe = retrieval_embedding_doc_recipe(system),
        doc_recipe_version = RETRIEVAL_EMBEDDING_DOC_RECIPE_VERSION,
        provenance = .retrieval_embedding_empty_provenance()
      )
    }
  }

  texts <- as.character(documents$text)
  if (length(texts) != n) return(NULL)

  batch_size <- suppressWarnings(as.integer(batch_size))
  if (length(batch_size) != 1L || is.na(batch_size) || batch_size < 1L) batch_size <- 64L

  starts <- seq(1L, length(texts), by = batch_size)
  mats <- vector("list", length(starts))

  for (i in seq_along(starts)) {
    lo <- starts[i]
    hi <- min(lo + batch_size - 1L, length(texts))
    m <- tryCatch(fn(texts[lo:hi]), error = function(e) NULL)
    # A partial index is worse than none: a corpus half-covered would rank
    # the covered half systematically above the rest for no semantic
    # reason. Any failed batch abandons the whole build.
    if (is.null(m) || !is.numeric(m) || is.null(dim(m)) || nrow(m) != (hi - lo + 1L)) {
      return(NULL)
    }
    mats[[i]] <- m
  }

  dims <- vapply(mats, ncol, integer(1))
  if (length(unique(dims)) != 1L) return(NULL)

  vectors <- do.call(rbind, mats)
  vectors <- retrieval_embedding_l2_normalize(vectors)
  if (is.null(vectors) || nrow(vectors) != length(texts)) return(NULL)

  # Canonical row identity. Prefer the unmodified canonical codes; fall
  # back to the corpus's normalized code key when no canonical table was
  # supplied.
  codes <- if (!is.null(data)) .retrieval_embedding_chr(data$code, n)
           else .retrieval_embedding_chr(corpus$code_key, n)

  sys <- if (!is.null(system)) .retrieval_first_chr(system)
         else if (!is.null(data)) .retrieval_first_chr(data$system) else ""
  ver <- if (!is.null(version)) .retrieval_first_chr(version)
         else if (!is.null(data)) .retrieval_first_chr(data$version) else ""

  structure(
    list(
      # -- schema identity (section 14)
      index_version      = RETRIEVAL_EMBEDDING_INDEX_VERSION,
      doc_recipe_version = .retrieval_embedding_int(
                             documents$doc_recipe_version,
                             RETRIEVAL_EMBEDDING_DOC_RECIPE_VERSION),
      doc_recipe         = .retrieval_first_chr(documents$recipe),
      # -- what this index is FOR
      system             = sys,
      version            = ver,
      level              = .retrieval_first_chr(level),
      # -- shape
      vectors            = vectors,
      n_docs             = nrow(vectors),
      dim                = ncol(vectors),
      # -- provider/model identifier
      model              = .retrieval_first_chr(cfg$model),
      provider           = if (exists("retrieval_embedding_provider_id", mode = "function"))
                             retrieval_embedding_provider_id(cfg) else "",
      # -- canonical row identity and checksums
      codes              = codes,
      corpus_fingerprint = .retrieval_embedding_fingerprint(
                             .retrieval_embedding_identity_texts(corpus)),
      doc_fingerprint    = .retrieval_embedding_fingerprint(texts),
      # -- section 11 provenance
      provenance         = documents$provenance,
      built_at           = as.character(Sys.time())
    ),
    class = "retrieval_embedding_index"
  )
}

#' Load a semantic index from disk.
#'
#' A missing, unreadable or structurally wrong file is NOT an error: it
#' means the optional tier is unavailable. Returns NULL and never throws.
#'
#' @param path Path to an .rds written by
#'   scripts/build_retrieval_embeddings.R.
#'
#' @return An index, or NULL.
retrieval_embeddings_load <- function(path) {
  if (is.null(path) || length(path) != 1L || is.na(path) || !nzchar(path)) return(NULL)
  if (!file.exists(path)) return(NULL)

  idx <- tryCatch(readRDS(path), error = function(e) NULL)
  if (!.retrieval_embedding_index_ok(idx)) return(NULL)
  idx
}

# Structural validation, shared by load and query. Kept separate from
# `retrieval_embeddings_index_is_valid()` because that one additionally
# asks "does this index match THIS corpus".
#
# The schema and recipe version checks are what implement section 15: an
# artifact built before either changed is rejected outright rather than
# read under assumptions that no longer hold.
.retrieval_embedding_index_ok <- function(index) {
  if (is.null(index) || !is.list(index)) return(FALSE)
  if (!identical(index$index_version, RETRIEVAL_EMBEDDING_INDEX_VERSION)) return(FALSE)
  if (!identical(.retrieval_embedding_int(index$doc_recipe_version, NA_integer_),
                 RETRIEVAL_EMBEDDING_DOC_RECIPE_VERSION)) return(FALSE)
  v <- index$vectors
  if (is.null(v) || !is.numeric(v) || is.null(dim(v))) return(FALSE)
  if (nrow(v) == 0L || ncol(v) == 0L) return(FALSE)
  if (!identical(as.integer(index$n_docs), nrow(v))) return(FALSE)
  if (!identical(as.integer(index$dim), ncol(v))) return(FALSE)
  if (!is.null(index$codes) && length(index$codes) != nrow(v)) return(FALSE)
  if (any(!is.finite(v))) return(FALSE)
  TRUE
}

#' Does this index correspond to this corpus?
#'
#' Guards the case that matters most: classification data was rebuilt but
#' the embedding artifact was not, so row 412 of the index no longer means
#' row 412 of the corpus. A mismatch would attach real codes to the wrong
#' vectors -- the exact class of silent substitution the classification
#' rules forbid -- so a mismatched index is refused outright.
#'
#' Section 15's four invalidation triggers all land here or in
#' `.retrieval_embedding_index_ok()`: canonical dataset change (the
#' fingerprint over code+label identity), document-recipe change
#' (`doc_recipe_version`), embedding model/provider change (see
#' `retrieval_semantic_search()` and the build script, which stamp
#' `model`/`provider`), and index-schema change (`index_version`).
#'
#' @param index An index, possibly NULL.
#' @param corpus A corpus from `retrieval_corpus()`, possibly NULL.
#' @param system,version character(1) or NULL. When supplied, an index
#'   built for a different classification system or edition is rejected
#'   even if it happens to be structurally sound. Optional so the existing
#'   two-argument call in retrieval_engine.R is unchanged.
#'
#' @return logical(1).
retrieval_embeddings_index_is_valid <- function(index, corpus,
                                                system = NULL, version = NULL) {
  if (!.retrieval_embedding_index_ok(index)) return(FALSE)
  if (is.null(corpus) || is.null(corpus$n)) return(FALSE)
  if (!identical(as.integer(corpus$n), as.integer(index$n_docs))) return(FALSE)

  if (!is.null(system)) {
    s <- tolower(.retrieval_first_chr(system))
    if (!identical(tolower(.retrieval_first_chr(index$system)), s)) return(FALSE)
  }
  if (!is.null(version)) {
    if (!identical(.retrieval_first_chr(index$version),
                   .retrieval_first_chr(version))) return(FALSE)
  }

  identical(as.character(index$corpus_fingerprint),
            .retrieval_embedding_fingerprint(.retrieval_embedding_identity_texts(corpus)))
}

# ---------------------------------------------------------------------
# Query-side
# ---------------------------------------------------------------------
#
# Runtime query-embedding cache (section 51). Keyed by the normalized
# query TOGETHER with the identity of the index it will be compared
# against -- system, version, model, schema version, recipe version and
# corpus fingerprint -- so a vector produced under one index can never be
# reused against an incompatible one.
#
# Only the real provider path is cached. When a caller injects `embed_fn`
# (tests, build tooling) the closure's behaviour is not part of the key
# and caching would be unsound, so it is skipped.

.retrieval_embedding_query_cache <- new.env(parent = emptyenv())

#' Clear the runtime query-embedding cache.
#'
#' @return invisible NULL.
retrieval_embedding_cache_reset <- function() {
  rm(list = ls(.retrieval_embedding_query_cache),
     envir = .retrieval_embedding_query_cache)
  invisible(NULL)
}

.retrieval_embedding_cache_key <- function(q, index) {
  paste(
    .retrieval_first_chr(index$system),
    .retrieval_first_chr(index$version),
    .retrieval_first_chr(index$model),
    as.character(index$index_version),
    as.character(index$doc_recipe_version),
    .retrieval_first_chr(index$corpus_fingerprint),
    q,
    sep = "|"
  )
}

#' Semantic candidates for a query.
#'
#' FAIL-OPEN GUARANTEE. This returns `retrieval_no_candidates()` -- never
#' NULL, never a condition -- for every one of: NULL index, structurally
#' invalid index, empty index, NULL/NA/blank/multi-element query, provider
#' disabled, provider unreachable, provider timeout, non-2xx response,
#' malformed response, dimension mismatch between query and index, and an
#' `embed_fn` that throws. The deterministic tiers therefore keep working
#' unchanged whatever the backend does.
#'
#' @param query character(1) user query.
#' @param index An index from `retrieval_embeddings_load()`.
#' @param top_k integer(1) maximum candidates.
#' @param min_score numeric(1) or NULL. Cosine is in [-1, 1] and is NOT
#'   clamped or rescaled; the default of 0 discards candidates pointing
#'   away from the query, which are never useful.
#' @param config Optional pre-read provider config.
#' @param embed_fn Optional embedding function, for build tooling and
#'   tests. Defaults to the HTTP provider. Supplying it also disables the
#'   query cache.
#'
#' MODE GATE. `mode` is resolved from `RETRIEVAL_SEMANTIC_MODE` (see
#' R/retrieval/retrieval_shadow.R) and decides whether these candidates
#' may reach the caller at all:
#'
#'   off      nothing runs. Returns no candidates immediately, so the
#'            tier costs nothing -- no normalization, no provider call,
#'            no allocation. This is the repository default.
#'   shadow   the query RUNS and is RECORDED, and then no candidates are
#'            returned. Fusion therefore receives exactly what it
#'            receives at `off`, which is what makes shadow mode
#'            provably unable to move `selected_code`, `allowed_codes`,
#'            clarification status or current-edition verification.
#'   active   candidates are returned. Not reachable in this release:
#'            `retrieval_semantic_mode()` clamps `active` to `shadow`.
#'   NULL     UNGATED. The caller is explicitly taking responsibility for
#'            authority. Used by `retrieval_semantic_search()` -- which
#'            is a measurement interface with no authority of its own --
#'            by the index builder, and by the benchmark harness.
#'
#' @param mode "off", "shadow", "active", or NULL for ungated generation.
#'
#' @return A candidate data.frame (idx, score, rank).
retrieval_embeddings_candidates <- function(query, index, top_k = 50L,
                                            min_score = 0, config = NULL,
                                            embed_fn = NULL,
                                            mode = retrieval_semantic_mode()) {
  # `off` short-circuits before anything is touched. Zero overhead is a
  # requirement, not an optimisation: this is the default state.
  if (!is.null(mode) && identical(mode, "off")) return(retrieval_no_candidates())

  status <- new.env(parent = emptyenv())
  status$value <- "ok"
  out <- .retrieval_embeddings_candidates_raw(query, index, top_k = top_k,
                                              min_score = min_score,
                                              config = config,
                                              embed_fn = embed_fn,
                                              status = status)

  if (!is.null(mode) && identical(mode, "shadow")) {
    # Measure, then discard. The deterministic half of the record is
    # unknown at this point and is attached later by
    # `retrieval_shadow_annotate()` if the caller knows it.
    .retrieval_shadow_capture(query, index, out, status$value, mode)
    return(retrieval_no_candidates())
  }

  out
}

# Translate a candidate frame into a shadow observation. Never throws,
# never affects the return value of its caller.
.retrieval_shadow_capture <- function(query, index, cand, status, mode) {
  if (!exists("retrieval_shadow_record", mode = "function")) return(invisible(NULL))
  tryCatch({
    codes <- character(0); scores <- numeric(0); ranks <- integer(0)
    if (is.data.frame(cand) && nrow(cand) > 0L && !is.null(index$codes)) {
      all_codes <- as.character(index$codes)
      keep <- utils::head(seq_len(nrow(cand)), RETRIEVAL_SHADOW_TOP_K)
      idx <- as.integer(cand$idx[keep])
      codes <- ifelse(idx >= 1L & idx <= length(all_codes), all_codes[idx], NA_character_)
      scores <- as.numeric(cand$score[keep])
      ranks <- as.integer(cand$rank[keep])
    }
    retrieval_shadow_record(
      query = query,
      system = if (is.null(index)) NULL else index$system,
      version = if (is.null(index)) NULL else index$version,
      codes = codes, scores = scores, ranks = ranks,
      provider_status = status, origin = "fusion", mode = mode
    )
  }, error = function(e) NULL)
  invisible(NULL)
}

# The candidate generator itself, with no authority policy applied.
#
# `status` is an optional environment into which the reason for an empty
# result is written, so shadow telemetry can distinguish "the provider
# never answered" from "nothing cleared the floor". Values: "ok",
# "no_index", "no_query", "provider_unavailable", "degenerate", "error".
.retrieval_embeddings_candidates_raw <- function(query, index, top_k = 50L,
                                                 min_score = 0, config = NULL,
                                                 embed_fn = NULL,
                                                 status = NULL) {
  set_status <- function(v) {
    if (!is.null(status)) status$value <- v
    invisible(NULL)
  }

  # An inner function rather than a bare block: `return()` inside a
  # `tryCatch()` expression returns from the ENCLOSING function, which
  # would skip every post-condition below.
  generate <- function() {
    if (!.retrieval_embedding_index_ok(index)) {
      set_status("no_index")
      return(retrieval_no_candidates())
    }

    q <- .retrieval_embedding_query_text(query)
    if (is.na(q)) {
      set_status("no_query")
      return(retrieval_no_candidates())
    }

    qv <- .retrieval_embedding_query_vector(q, index, config = config,
                                            embed_fn = embed_fn)
    if (is.null(qv)) {
      set_status("provider_unavailable")
      return(retrieval_no_candidates())
    }

    # Both sides are unit-length, so this product IS the cosine.
    score <- as.numeric(index$vectors %*% as.numeric(qv))
    if (length(score) != nrow(index$vectors) || all(!is.finite(score))) {
      set_status("degenerate")
      return(retrieval_no_candidates())
    }
    score[!is.finite(score)] <- NA_real_

    retrieval_candidates(
      idx = seq_len(nrow(index$vectors)),
      score = score,
      top_k = top_k,
      min_score = min_score
    )
  }

  # Everything is wrapped: no failure inside the semantic tier may ever
  # reach the caller as a condition.
  out <- tryCatch(generate(), error = function(e) {
    set_status("error")
    retrieval_no_candidates()
  })

  if (is.null(out) || !is.data.frame(out)) return(retrieval_no_candidates())
  out
}

# Embed one already-normalized query and return a unit-length numeric
# vector, or NULL. Never throws.
.retrieval_embedding_query_vector <- function(q, index, config = NULL,
                                              embed_fn = NULL) {
  cacheable <- is.null(embed_fn)
  key <- if (cacheable) .retrieval_embedding_cache_key(q, index) else NULL

  if (cacheable && exists(key, envir = .retrieval_embedding_query_cache, inherits = FALSE)) {
    cached <- get(key, envir = .retrieval_embedding_query_cache, inherits = FALSE)
    if (is.numeric(cached) && length(cached) == ncol(index$vectors)) return(cached)
  }

  cfg <- if (is.null(config)) retrieval_embedding_config() else config
  fn <- if (is.null(embed_fn)) function(x) retrieval_embed_texts(x, cfg) else embed_fn

  qm <- tryCatch(fn(q), error = function(e) NULL)
  if (is.null(qm) || !is.numeric(qm)) return(NULL)
  if (is.null(dim(qm))) qm <- matrix(qm, nrow = 1L)
  if (nrow(qm) < 1L || ncol(qm) != ncol(index$vectors)) return(NULL)

  qv <- retrieval_embedding_l2_normalize(qm[1L, , drop = FALSE])
  if (is.null(qv)) return(NULL)
  vec <- as.numeric(qv[1L, ])

  if (cacheable) {
    # Crude bound: the cache exists to spare a repeated remote call inside
    # one session, so wholesale eviction at the cap is cheaper and more
    # predictable than tracking recency.
    if (length(ls(.retrieval_embedding_query_cache)) >= RETRIEVAL_EMBEDDING_QUERY_CACHE_MAX) {
      retrieval_embedding_cache_reset()
    }
    assign(key, vec, envir = .retrieval_embedding_query_cache)
  }
  vec
}

#' Semantic search over one classification system+version. CANDIDATE
#' GENERATION ONLY.
#'
#' The section 8.1 interface. It resolves candidates to canonical codes
#' using the row identity stored ON THE INDEX, so it never needs the
#' repository and never mints a code: every code it returns was written
#' into the artifact from a canonical row at build time.
#'
#' SYSTEM ISOLATION (section 9). When `system`/`version` are supplied they
#' are checked against the index's own stamp and a mismatch returns zero
#' rows. Indexes are separate artifacts per system+version by file path, so
#' this is a second line of defence rather than the only one -- but it is
#' the line that catches an index passed to the wrong caller in process.
#'
#' AUTHORITY. Nothing here authorizes a code. `semantic_score` is a cosine,
#' not a confidence, and section 41 requires a candidate to additionally
#' pass context compatibility, level policy and canonical verification
#' before it may be presented.
#'
#' @param query character(1).
#' @param index An index from `retrieval_embeddings_load()`.
#' @param top_k integer(1).
#' @param system,version character(1) or NULL. When supplied, enforced.
#' @param min_score numeric(1) or NULL.
#' @param config,embed_fn as for `retrieval_embeddings_candidates()`.
#'
#' @return A data.frame with `row_index`, `code`, `semantic_score`,
#'   `semantic_rank`, `source` and `semantic_document_sources`. Zero rows
#'   on any failure; never NULL, never a condition.
retrieval_semantic_search <- function(query, index, top_k = 10L,
                                      system = NULL, version = NULL,
                                      min_score = 0, config = NULL,
                                      embed_fn = NULL) {
  empty <- data.frame(
    row_index = integer(0), code = character(0),
    semantic_score = numeric(0), semantic_rank = integer(0),
    source = character(0), semantic_document_sources = character(0),
    stringsAsFactors = FALSE
  )

  out <- tryCatch({
    if (!.retrieval_embedding_index_ok(index)) return(empty)

    if (!is.null(system) &&
        !identical(tolower(.retrieval_first_chr(index$system)),
                   tolower(.retrieval_first_chr(system)))) {
      return(empty)
    }
    if (!is.null(version) &&
        !identical(.retrieval_first_chr(index$version),
                   .retrieval_first_chr(version))) {
      return(empty)
    }

    # UNGATED on purpose. This function is a MEASUREMENT interface: it
    # is what shadow telemetry and the benchmark harness call, and it
    # feeds nothing into fusion. Routing it through the mode gate would
    # make shadow mode unable to measure the very thing it exists to
    # measure. Authority still lives entirely at the gate, which is on
    # `retrieval_embeddings_candidates()` -- the only entry point the
    # engine uses.
    cand <- .retrieval_embeddings_candidates_raw(
      query, index, top_k = top_k, min_score = min_score,
      config = config, embed_fn = embed_fn
    )
    if (!is.data.frame(cand) || nrow(cand) == 0L) return(empty)

    codes <- as.character(index$codes)
    code <- if (length(codes) == nrow(index$vectors)) codes[cand$idx] else rep(NA_character_, nrow(cand))

    prov <- index$provenance
    sources <- if (is.data.frame(prov) && nrow(prov) == nrow(index$vectors) &&
                   "semantic_document_sources" %in% names(prov)) {
      as.character(prov$semantic_document_sources)[cand$idx]
    } else {
      rep("", nrow(cand))
    }
    sources[is.na(sources)] <- ""

    data.frame(
      row_index = as.integer(cand$idx),
      code = code,
      semantic_score = as.numeric(cand$score),
      semantic_rank = as.integer(cand$rank),
      source = rep("semantic", nrow(cand)),
      semantic_document_sources = sources,
      stringsAsFactors = FALSE
    )
  }, error = function(e) empty)

  if (is.null(out) || !is.data.frame(out)) return(empty)
  out
}
