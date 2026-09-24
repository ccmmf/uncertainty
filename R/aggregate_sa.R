#' Collect PEcAn variance decompositions into one tidy table
#'
#' @description
#' Reads every `sensitivity.results.*.Rdata` written under a run tree and
#' returns one row per block, PFT, output variable, window and parameter.
#'
#' Every key is taken from the data rather than assumed. The block comes from
#' the directory the file sits in, and the output variable and the window come
#' from the file name, so two analyses of the same block that differ only in
#' their years stay distinct rows. This matters because the cal/val sites do not
#' share a run window and a plant-plus-soil run carries two PFTs: dropping
#' either key silently merges results that describe different things.
#'
#' PEcAn normalises partial variance within a PFT, so the shares sum to one per
#' PFT and to two per block. `partial_variance` keeps that per-PFT share and
#' `joint_share` puts the plant and soil PFTs on a common denominator, which is
#' what a figure comparing them needs.
#'
#' @param blocks_dir Directory holding one subdirectory per block, as written by
#'   [build_settings()].
#' @param sites Optional site table; when given, its per-block columns are
#'   joined on `id` and every block found on disk must appear in it.
#' @return A data frame with columns `id`, `pft`, `variable`,
#'   `start_year`, `end_year`, `parameter`, `cv`, `elasticity`,
#'   `partial_variance`, `variance` and `joint_share`.
#' @export
aggregate_sa <- function(blocks_dir, sites = NULL) {
  if (!dir.exists(blocks_dir)) {
    PEcAn.logger::logger.severe("no such directory: ", blocks_dir)
  }
  files <- list.files(blocks_dir, pattern = SA_RESULT_GLOB,
                      recursive = TRUE, full.names = TRUE)
  if (length(files) == 0) {
    PEcAn.logger::logger.severe("no sensitivity.results files under ", blocks_dir)
  }

  rows <- list()
  for (f in files) {
    parts <- regmatches(basename(f), regexec(SA_RESULT_KEYS, basename(f)))[[1]]
    if (length(parts) != 4L) {
      PEcAn.logger::logger.severe(
        "cannot read variable and window from ", basename(f),
        ". the window is part of the run identity and is not recoverable ",
        "from anything else in the file."
      )
    }
    id <- basename(dirname(f))
    env <- new.env()
    load(f, envir = env)
    if (!exists("sensitivity.results", envir = env)) {
      PEcAn.logger::logger.severe("no sensitivity.results object in ", f)
    }
    results <- get("sensitivity.results", envir = env)
    for (pft in names(results)) {
      vd <- results[[pft]]$variance.decomposition.output
      if (is.null(vd)) next
      rows[[length(rows) + 1L]] <- data.frame(
        id = id,
        pft = pft,
        variable = parts[2],
        start_year = as.integer(parts[3]),
        end_year = as.integer(parts[4]),
        parameter = names(vd$coef.vars),
        cv = as.numeric(vd$coef.vars),
        elasticity = as.numeric(vd$elasticities),
        partial_variance = as.numeric(vd$partial.variances),
        variance = as.numeric(vd$variances),
        stringsAsFactors = FALSE
      )
    }
  }
  if (length(rows) == 0) {
    PEcAn.logger::logger.severe("every file under ", blocks_dir,
                                " lacked a variance decomposition")
  }
  out <- do.call(rbind, rows)

  # common denominator across the PFTs of one block, variable and window
  key <- paste(out$id, out$variable, out$start_year, out$end_year)
  total <- stats::ave(out$variance, key, FUN = function(x) sum(x, na.rm = TRUE))
  out$joint_share <- ifelse(total > 0, out$variance / total, NA_real_)

  if (!is.null(sites)) {
    if (!"id" %in% names(sites)) {
      PEcAn.logger::logger.severe("site table has no id column")
    }
    unknown <- setdiff(unique(out$id), sites$id)
    if (length(unknown) > 0) {
      PEcAn.logger::logger.severe(
        length(unknown), " block(s) on disk are not in the site table: ",
        paste(unknown, collapse = ", ")
      )
    }
    missing <- setdiff(sites$id, unique(out$id))
    if (length(missing) > 0) {
      PEcAn.logger::logger.warn(
        length(missing), " block(s) in the site table produced no results: ",
        paste(missing, collapse = ", ")
      )
    }
    out <- merge(out, sites, by = "id", all.x = TRUE)
  }
  out[order(out$id, out$variable, out$pft, out$parameter), ]
}

# PEcAn's sensitivity.filename() writes
#   sensitivity.results.<ensemble id>.<variable>.<start year>.<end year>.Rdata
# The first pattern finds the files, the second pulls the variable and the
# window out of one. They are kept apart on purpose: a file that is named like a
# result but cannot be parsed is an error rather than something the listing
# quietly skips.
SA_RESULT_GLOB <- "^sensitivity\\.results\\..*\\.Rdata$"
SA_RESULT_KEYS <- paste0("^sensitivity\\.results\\..+\\.([A-Za-z0-9_]+)",
                         "\\.(-?\\d{4})\\.(-?\\d{4})\\.Rdata$")
