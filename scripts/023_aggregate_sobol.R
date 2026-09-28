#!/usr/bin/env Rscript

# Collect the per-site Sobol indices written by 022 into one table for the report.

library(PEcAn.logger)

options <- list(
  optparse::make_option(c("-s", "--settings"),
    default = "output/pecan.CONFIGS.xml",
    help = "settings written by 021_run_global_sensitivity.R, for the sites run"
  ),
  optparse::make_option(c("-d", "--sobol_dir"),
    default = "output/sobol",
    help = "directory of per-site index files written by 022"
  ),
  optparse::make_option(c("-o", "--output_file"),
    default = "global_sensitivity.csv",
    help = "path to write the aggregated table"
  ),
  optparse::make_option("--site_file",
    default = "site_info.csv",
    help = "site table, joined for location and PFT"
  )
) |>
  purrr::modify(\(x) {
    x@help <- paste(x@help, "[default: %default]")
    x
  })

args <- optparse::OptionParser(option_list = options) |>
  optparse::parse_args()

settings <- PEcAn.settings::read.settings(args$settings)
ids <- vapply(settings, function(s) as.character(s$run$site$id), character(1))
files <- file.path(args$sobol_dir, paste0(ids, ".csv"))
if (!all(file.exists(files))) {
  logger.severe("no indices for sites:", paste(ids[!file.exists(files)], collapse = ", "))
}

sites <- utils::read.csv(args$site_file, colClasses = c(id = "character"))
indices <- files |>
  purrr::map(\(f) utils::read.csv(f, colClasses = c(site_id = "character"))) |>
  purrr::list_rbind() |>
  dplyr::left_join(
    dplyr::select(sites, site_id = "id", "lat", "lon", veg_pft = "site.pft"),
    by = "site_id"
  )

dir.create(dirname(args$output_file), recursive = TRUE, showWarnings = FALSE)
utils::write.csv(indices, args$output_file, row.names = FALSE)
logger.info("wrote", args$output_file, "with", nrow(indices), "rows over",
            length(unique(indices$site_id)), "sites")
