#!/usr/bin/env Rscript

# Write configs and run SIPNET for the one-at-a-time sensitivity analysis.
# Results are read per site by 012_site_results.R, which runs sites in parallel,
# since reading all runs serially here takes about 16 hours.
# A rerun resumes from the STATUS file in the output directory; a fresh run
# needs a fresh output directory.

library(PEcAn.all)
library(PEcAn.logger)

options <- list(
  optparse::make_option(c("-s", "--settings"),
    default = "settings.xml",
    help = "path to multisite SA settings XML written by 001_build_xml.R"
  ),
  optparse::make_option("--seed",
    default = 1L,
    help = "seed for the prior draws the quantiles are taken from"
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

if (PEcAn.utils::status.check("CONFIG") == 0) {
  PEcAn.utils::status.start("CONFIG")
  # The design is built from the first site and shared, which is how every site
  # draws the same samples. Generating it here rather than letting
  # run.write.configs do it internally is the documented path, and the internal
  # one reads no posteriors: it calls load_pft_posteriors with posterior.files
  # set to NA for every PFT, so the priors come back empty.
  set.seed(args$seed)
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
