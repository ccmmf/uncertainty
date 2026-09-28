#' Read one PEcAn sensitivity result file
#'
#' @param sa_file Path to a `sensitivity.results.*.Rdata` file.
#' @param site_ids Named character vector mapping ensemble id to site id.
#' @return Data frame of variance decomposition metrics, one row per PFT and
#'   parameter.
#' @export
read_sa_file <- function(sa_file, site_ids) {
  # sensitivity.results.<ensemble_id>.<variable>.<start>.<end>.Rdata
  parts <- strsplit(basename(sa_file), ".", fixed = TRUE)[[1]]
  ensemble_id <- parts[[3]]
  variable <- parts[[4]]

  if (!ensemble_id %in% names(site_ids)) {
    PEcAn.logger::logger.severe(
      "No site for ensemble id ", ensemble_id, " from ", sa_file
    )
  }

  sensitivity.results <- PEcAn.utils::load_local(sa_file)[["sensitivity.results"]]

  purrr::map_dfr(names(sensitivity.results), function(pft) {
    vd <- sensitivity.results[[pft]]$variance.decomposition.output
    tibble::tibble(
      site_id = site_ids[[ensemble_id]],
      pft = pft,
      variable = variable,
      parameter = names(vd$coef.vars),
      coef_var = vd$coef.vars,
      elasticity = vd$elasticities,
      # partial_variance sums to one within each pft; variance is the absolute
      # contribution, needed to compare plant and soil traits on one denominator
      variance = vd$variances,
      partial_variance = vd$partial.variances,
      sensitivity = vd$sensitivities
    )
  })
}


#' Collect the statewide sensitivity results into one table
#'
#' @description
#' PEcAn names each result file by ensemble id alone, so the site comes from
#' each site's settings, which carry its sensitivity analysis ensemble id.
#'
#' @param settings A MultiSettings read from `pecan.CONFIGS.xml`.
#' @return Data frame of variance decomposition metrics for every site, PFT,
#'   variable and parameter.
#' @export
aggregate_sensitivity <- function(settings) {
  # read per site: a MultiSettings merges a value shared by every site, so with a
  # single site sensitivity.analysis is not split into site.<id> entries
  ensemble_ids <- lapply(settings, function(s) s$sensitivity.analysis$ensemble.id)
  if (any(vapply(ensemble_ids, is.null, logical(1)))) {
    PEcAn.logger::logger.severe(
      "settings has no sensitivity analysis ensemble id for some sites; ",
      "run 011_run_local_sensitivity.R first"
    )
  }
  site_ids <- stats::setNames(
    vapply(settings, function(s) as.character(s$run$site$id), character(1)),
    unlist(ensemble_ids)
  )

  sa_files <- list.files(settings$outdir, "^sensitivity\\.results\\..*\\.Rdata$",
                         full.names = TRUE, recursive = TRUE)
  if (length(sa_files) == 0) {
    PEcAn.logger::logger.severe("No sensitivity results under ", settings$outdir)
  }

  purrr::map_dfr(sa_files, read_sa_file, site_ids = site_ids) |>
    dplyr::arrange(.data$site_id, .data$variable,
                   dplyr::desc(.data$partial_variance))
}
