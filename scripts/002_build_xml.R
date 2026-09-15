#!/usr/bin/env Rscript

# 002_build_xml.R
# Build multisite PEcAn settings XML for sensitivity analysis.
# Run parameters (n_ensemble, n_met, start/end dates) come from
# 000-config.yml so users only need to edit one file.

library(config)
library(dplyr)
library(lubridate)
library(PEcAn.settings)
library(PEcAn.logger)

PEcAn.logger::logger.info("Starting 002_build_xml.R")

cfg <- config::get(file = "000-config.yml")

ccmmf_dir    <- cfg$paths$ccmmf_dir
raw_data_dir <- cfg$paths$raw_data_dir

# run parameters from config (not hardcoded)
n_ens      <- cfg$run$n_ensemble
n_met      <- cfg$run$n_met
start_date <- cfg$run$start_date
end_date   <- cfg$run$end_date

# derived paths from ccmmf_dir
ic_dir        <- file.path(ccmmf_dir, "ensemble/IC_files")
met_dir       <- file.path(ccmmf_dir, "ensemble/ERA5_SIPNET")
pft_dir       <- file.path(ccmmf_dir, "ensemble/pfts")
site_file     <- file.path(raw_data_dir, "sa_design_points.csv")
template_file <- file.path(raw_data_dir, "template.xml")
output_file   <- file.path(raw_data_dir, "settings_sa.xml")

sigma_levels <- cfg$sensitivity$sigma_levels %||% c(-3, -2, -1, 1, 2, 3)

# load SA design points
site_info <- read.csv(site_file, stringsAsFactors = FALSE)
stopifnot(
  all(c("site_id", "lat", "lon") %in% names(site_info)),
  nrow(site_info) > 0
)
site_info <- site_info |> dplyr::rename(id = site_id)

# read template settings
settings <- PEcAn.settings::read.settings(template_file)

# set run dates
settings$run$start.date <- start_date
settings$run$end.date   <- end_date

# ensemble meta
settings$ensemble$size       <- n_ens
settings$ensemble$start.year <- lubridate::year(start_date)
settings$ensemble$end.year   <- lubridate::year(end_date)
settings$run$inputs$poolinitcond$ensemble <- n_ens

# sensitivity windows
settings$sensitivity.analysis$start.year <- lubridate::year(start_date)
settings$sensitivity.analysis$end.year   <- lubridate::year(end_date)

# make multisite settings and set ensemble input paths
settings <- settings |>
  PEcAn.settings::createMultiSiteSettings(site_info) |>
  PEcAn.settings::setEnsemblePaths(
    n_reps = n_met,
    input_type = "met",
    path = met_dir,
    d1 = start_date,
    d2 = end_date,
    path_template = "{path}/{id}/ERA5.{n}.{d1}.{d2}.clim"
  ) |>
  PEcAn.settings::setEnsemblePaths(
    n_reps = n_ens,
    input_type = "poolinitcond",
    path = ic_dir,
    path_template = "{path}/{id}/IC_site_{id}_{n}.nc"
  ) |>
  PEcAn.settings::setEnsemblePaths(
    n_reps = 1,
    input_type = "events",
    path = file.path(ccmmf_dir, "ensemble/events"),
    path_template = "{path}/events-{id}.in"
  )

quantiles_list <- list()
for (sigma_val in sigma_levels) {
  quantiles_list <- c(quantiles_list, list(sigma = as.character(sigma_val)))
}
settings$sensitivity.analysis$quantiles <- quantiles_list

# set PFT posterior files from shared directory
if (!is.null(pft_dir) && nzchar(pft_dir)) {
  if (!dir.exists(pft_dir)) {
    PEcAn.logger::logger.warn("pft_dir does not exist: ", pft_dir)
  }

  settings$pfts <- settings$pfts |>
    lapply(function(pft) {
      candidate <- file.path(pft_dir, pft$name, "post.distns.Rdata")

      if (!file.exists(candidate)) {
        PEcAn.logger::logger.severe(
          "Posterior file for PFT '", pft$name, "' not found at: ", candidate
        )
      }

      pft$posterior.files <- candidate
      pft$outdir <- file.path(settings$outdir, "pfts", pft$name)
      pft
    })
}

# write multisite SA settings
PEcAn.settings::write.settings(
  settings,
  outputfile = basename(output_file),
  outputdir  = dirname(output_file)
)

PEcAn.logger::logger.info("Wrote multisite SA settings to ", output_file)
