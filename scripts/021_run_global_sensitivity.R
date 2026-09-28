#!/usr/bin/env Rscript

# Sobol global sensitivity analysis with parameters, met, initial conditions and
# events as the factors. Writes every site's configs from one shared design and
# runs the model; 022 reads the output and computes indices per site.
# A rerun resumes from the STATUS file in the output directory; a fresh run
# needs a fresh output directory.

library(PEcAn.all)
library(PEcAn.logger)

options <- list(
  optparse::make_option(c("-s", "--settings"),
    default = "settings.xml",
    help = "path to multisite GSA settings XML written by 001_build_xml.R"
  ),
  optparse::make_option("--seed",
    default = 1L,
    help = "seed for the Sobol design"
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
  # One design drawn from the first site and shared by all of them, so every
  # site runs the same parameter and input indices. Saved because the indices
  # can only be computed once the runs are done.
  set.seed(args$seed)
  sobol_obj <- PEcAn.uncertainty::generate_joint_ensemble_design(
    settings = settings[1],
    ensemble_size = settings$ensemble$size,
    sobol = TRUE
  )
  saveRDS(sobol_obj, file.path(settings$outdir, "sobol_design.rds"))
  settings <- runModule.run.write.configs(settings, input_design = sobol_obj)
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

logger.info("Model runs done for", length(settings), "sites; run 022 per site next")
