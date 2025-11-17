#!/usr/bin/env Rscript

library(config)
library(dplyr)
library(lubridate)
library(PEcAn.settings)
library(PEcAn.logger)

PEcAn.logger::logger.info("*** Starting 002_build_xml.R ***")

cfg <- config::get(file = "000-config.yml")

ccmmf_dir    <- cfg$paths$ccmmf_dir
raw_data_dir <- cfg$paths$raw_data_dir

# SA configuration (configurable paths)
options <- list(
  n_ens = 20,
  n_met = 10,
  start_date = "2016-01-01",
  end_date   = "2023-12-31",
  sigma_levels = cfg$sensitivity$sigma_levels %||% c(-3, -2, -1, 1, 2, 3),
  ic_dir     = file.path(ccmmf_dir, "ensemble/IC_files"),
  met_dir    = file.path(ccmmf_dir, "ensemble/ERA5_SIPNET"),
  pft_dir    = file.path(ccmmf_dir, "ensemble/pfts"),
  site_file  = file.path(raw_data_dir, "sa_design_points.csv"),
  template_file = file.path(raw_data_dir, "template.xml"),
  output_file   = file.path(raw_data_dir, "settings_sa.xml")
)

# Load SA design points (expect at least one row)
site_info <- read.csv(options$site_file, stringsAsFactors = FALSE)
stopifnot(
  all(c("site_id", "lat", "lon") %in% names(site_info)),
  nrow(site_info) > 0
)
site_info <- site_info |> dplyr::rename(id = site_id)

# Read template settings
settings <- PEcAn.settings::read.settings(options$template_file)

# Set run dates
settings$run$start.date <- options$start_date
settings$run$end.date   <- options$end_date

# Ensemble meta
settings$ensemble$size      <- options$n_ens
settings$ensemble$start.year <- lubridate::year(options$start_date)
settings$ensemble$end.year   <- lubridate::year(options$end_date)
settings$run$inputs$poolinitcond$ensemble <- options$n_ens

# Sensitivity windows and sigma levels
settings$sensitivity.analysis$start.year <- lubridate::year(options$start_date)
settings$sensitivity.analysis$end.year   <- lubridate::year(options$end_date)
settings$sensitivity.analysis$quantiles  <- lapply(
  options$sigma_levels,
  function(x) list(sigma = x)
)

# Make multisite settings and set ensemble input paths (met + IC)
settings <- settings |>
  PEcAn.settings::createMultiSiteSettings(site_info) |>
  PEcAn.settings::setEnsemblePaths(
    n_reps = options$n_met,
    input_type = "met",
    path = options$met_dir,
    d1 = options$start_date,
    d2 = options$end_date,
    path_template = "{path}/{id}/ERA5.{n}.{d1}.{d2}.clim"
  ) |>
  PEcAn.settings::setEnsemblePaths(
    n_reps = options$n_ens,
    input_type = "poolinitcond",
    path = options$ic_dir,
    path_template = "{path}/{id}/IC_site_{id}_{n}.nc"
  )

# -----------------------------------------------------------------------
# Set PFT posterior files and outdirs
#  - options$pft_dir is the base folder containing per-pft directories
#  - each pft should contain 'post.distns.Rdata'
# -----------------------------------------------------------------------
if (!is.null(options$pft_dir) && nzchar(options$pft_dir)) {
  if (!dir.exists(options$pft_dir)) {
    PEcAn.logger::logger.warn("Configured pft_dir does not exist: ", options$pft_dir)
  }

  settings$pfts <- settings$pfts |>
    lapply(function(pft) {
      # Construct absolute posterior file path
      candidate <- file.path(options$pft_dir, pft$name, "post.distns.Rdata")
      
      if (!file.exists(candidate)) {
        # If absent, raise a severe error - posterior files are required for SA/ensemble
        PEcAn.logger::logger.severe(
          "Posterior file for PFT '", pft$name, "' not found at: ", candidate,
          "\nPlease place post.distns.Rdata there or adjust cfg$paths$ccmmf_dir."
        )
      }
      
      pft$posterior.files <- candidate
      pft$outdir <- file.path(settings$outdir, "pfts", pft$name)
      pft
    })
} else {
  PEcAn.logger::logger.warn("options$pft_dir is empty; skipping posterior file configuration.")
}

# Write settings XML (multisite)
PEcAn.settings::write.settings(
  settings,
  outputfile = basename(options$output_file),
  outputdir  = dirname(options$output_file)
)

PEcAn.logger::logger.info("Wrote multisite SA settings to ", options$output_file)
PEcAn.logger::logger.info("*** Finished 002_build_xml.R ***")
