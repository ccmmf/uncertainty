#!/usr/bin/env Rscript

# Collect the per-site variance decompositions into one table for the report.

library(PEcAn.settings)
library(PEcAn.logger)

source("000-config.R")
source("R/local_sensitivity.R")

options <- list(
  optparse::make_option(c("-s", "--settings"),
    default = file.path(run_dir, "output", "pecan.CONFIGS.xml"),
    help = "settings written by 011_run_local_sensitivity.R"
  ),
  optparse::make_option(c("-o", "--output_file"),
    default = file.path(run_dir, "statewide_sensitivity.csv"),
    help = "path to write the aggregated table"
  ),
  optparse::make_option("--site_file",
    default = "data_raw/statewide_sites.csv",
    help = "site table, joined for location and PFT"
  )
) |>
  purrr::modify(\(x) {
    x@help <- paste(x@help, "[default: %default]")
    x
  })

args <- optparse::OptionParser(option_list = options) |>
  optparse::parse_args()

settings <- read.settings(args$settings)
sites <- utils::read.csv(args$site_file, colClasses = c(id = "character"))

results <- aggregate_sensitivity(settings) |>
  dplyr::left_join(
    dplyr::select(sites, site_id = "id", "lat", "lon", veg_pft = "site.pft"),
    by = "site_id"
  )

dir.create(dirname(args$output_file), recursive = TRUE, showWarnings = FALSE)
utils::write.csv(results, args$output_file, row.names = FALSE)

logger.info("Wrote", args$output_file, "with", nrow(results), "rows over",
            length(unique(results$site_id)), "sites and",
            length(unique(results$variable)), "variables")
