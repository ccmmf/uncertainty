#!/usr/bin/env Rscript

# Write configs and run SIPNET for the statewide OAT design points. Results are
# read per site by 012_site_results.R, which runs as an array, since reading all
# runs serially here takes about 16 hours.
# Resumable through the STATUS file in the output directory.

library(PEcAn.all)
library(PEcAn.logger)

options <- list(
  optparse::make_option(c("-s", "--settings"),
    default = "data_raw/settings_sa.xml",
    help = "path to multisite SA settings XML"
  ),
  optparse::make_option(c("-c", "--continue"),
    action = "store_true", default = FALSE,
    help = "resume an interrupted workflow"
  )
) |>
  purrr::modify(\(x) {
    x@help <- paste(x@help, "[default: %default]")
    x
  })

args <- optparse::OptionParser(option_list = options) |>
  optparse::parse_args()

options(warn = 1)
options(error = quote({
  try(PEcAn.utils::status.end("ERROR"))
  if (!interactive()) q(status = 1)
}))

PEcAn.all::pecan_version()

settings <- PEcAn.settings::read.settings(args$settings)
dir.create(settings$outdir, recursive = TRUE, showWarnings = FALSE)

status_file <- file.path(settings$outdir, "STATUS")
if (!args$continue && file.exists(status_file)) file.remove(status_file)

if (PEcAn.utils::status.check("CONFIG") == 0) {
  PEcAn.utils::status.start("CONFIG")
  # The design is built from the first site and shared, which is how every site
  # draws the same samples. Generating it here rather than letting
  # run.write.configs do it internally is the documented path, and the internal
  # one reads no posteriors: it calls load_pft_posteriors with posterior.files
  # set to NA for every PFT, so the priors come back empty.
  design <- PEcAn.uncertainty::generate_joint_ensemble_design(
    settings = settings[1],
    ensemble_size = settings$ensemble$size
  )
  settings <- runModule.run.write.configs(settings, input_design = design)
  PEcAn.settings::write.settings(settings, outputfile = "pecan.CONFIGS.xml")
  PEcAn.utils::status.end()
} else if (file.exists(file.path(settings$outdir, "pecan.CONFIGS.xml"))) {
  settings <- PEcAn.settings::read.settings(
    file.path(settings$outdir, "pecan.CONFIGS.xml")
  )
}

if (PEcAn.utils::status.check("MODEL") == 0) {
  PEcAn.utils::status.start("MODEL")
  PEcAn.workflow::runModule_start_model_runs(settings, stop.on.error = FALSE)
  PEcAn.utils::status.end()
}

logger.info("Finished model runs for", length(settings), "sites")
