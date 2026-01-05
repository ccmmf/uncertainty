#!/usr/bin/env Rscript

library(PEcAn.all)
library(optparse)

options <- list(
  make_option(c("-s", "--settings"),
    default = "data_raw/settings_sa.xml",
    help = "Path to PEcAn settings XML file [default: %default]"
  ),
  make_option(c("--continue"),
    default = FALSE,
    help = "Continue previously interrupted workflow [default: %default]"
  )
)
args <- parse_args(OptionParser(option_list = options))

options(warn = 1)
options(error = quote({
  try(PEcAn.utils::status.end("ERROR"))
  if (!interactive()) q(status = 1)
}))

settings <- PEcAn.settings::read.settings(args$settings)

# Will this run only 1 model ? 
# NO. It will run exactly N times (k+2) models, 
# because input_design contains that many rows.
settings$ensemble$size <- 1

input_design_path <- "cache/input_design.rds"
input_design <- readRDS(input_design_path)

status_file <- file.path(settings$outdir, "STATUS")
if (!args$continue && file.exists(status_file)) file.remove(status_file)

if (PEcAn.utils::status.check("CONFIG") == 0) {
  PEcAn.utils::status.start("CONFIG")

  settings <- runModule.run.write.configs(
    settings = settings,
    input_design = input_design
  )
  PEcAn.settings::write.settings(settings, outputfile = "pecan.CONFIGS.xml")
  PEcAn.utils::status.end()
} else {
  settings <- PEcAn.settings::read.settings(file.path(settings$outdir, "pecan.CONFIGS.xml"))
}

if (PEcAn.utils::status.check("MODEL") == 0) {
  PEcAn.utils::status.start("MODEL")
  PEcAn.workflow::runModule_start_model_runs(settings, stop.on.error = FALSE)
  PEcAn.utils::status.end()
}

loglevel <- PEcAn.logger::logger.setLevel("WARN")
if (PEcAn.utils::status.check("OUTPUT") == 0) {
  PEcAn.utils::status.start("OUTPUT")
  runModule.get.results(settings)
  PEcAn.utils::status.end()
}
PEcAn.logger::logger.setLevel(loglevel)

PEcAn.logger::logger.info("---------- PEcAn Global SA Workflow Complete ----------\n")
