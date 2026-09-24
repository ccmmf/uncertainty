#!/usr/bin/env Rscript

# run the OAT sensitivity analysis: write configs at the sensitivity knots,
# submit the model array, convert output, then decompose the variance.
# resumable through the workflow STATUS file.
#
#   Rscript scripts/020_run_sa.R [-c examples/calval/config.yml] [--continue]

suppressMessages(library(PEcAn.all))
source("R/data_root.R")

args <- optparse::parse_args(optparse::OptionParser(option_list = list(
  optparse::make_option(c("-c", "--config"), default = "examples/calval/config.yml",
    help = "project config [default: %default]"),
  optparse::make_option("--continue", action = "store_true", default = FALSE,
    help = "resume an interrupted run [default: %default]")
)))
config <- config::get(file = args$config)

options(warn = 1)
options(error = quote({
  try(PEcAn.utils::status.end("ERROR"))
  if (!interactive()) q(status = 1)
}))

# these settings are database free, so prepare.settings is not run: its
# check.settings half needs a bety connection and the site to PFT linkage is
# already done at build time
settings <- PEcAn.settings::read.settings(
  data_root(config$workspace, "settings.xml"))

status_file <- file.path(settings$outdir, "STATUS")
if (!args$continue && file.exists(status_file)) file.remove(status_file)
dir.create(settings$outdir, recursive = TRUE, showWarnings = FALSE)

# status.check returns -1 for a stage that ended in ERROR. the gates below only
# test for "not yet done", so without this a resumed run would step over a
# failure and decompose incomplete output.
for (stage in c("CONFIG", "MODEL", "OUTPUT", "SENSITIVITY")) {
  if (PEcAn.utils::status.check(stage) == -1L) {
    PEcAn.logger::logger.severe(stage,
      " previously failed; resolve before continuing")
  }
}

# host$modellauncher$binary is relative to the run directory and qsub runs with
# -cwd, so configuring and launching happen from the workspace
old_wd <- setwd(data_root(config$workspace))
on.exit(setwd(old_wd), add = TRUE)

if (PEcAn.utils::status.check("CONFIG") == 0) {
  PEcAn.utils::status.start("CONFIG")
  settings <- PEcAn.workflow::runModule.run.write.configs(settings)
  PEcAn.settings::write.settings(settings, outputfile = "pecan.CONFIGS.xml")
  PEcAn.utils::status.end()
} else if (file.exists(file.path(settings$outdir, "pecan.CONFIGS.xml"))) {
  settings <- PEcAn.settings::read.settings(
    file.path(settings$outdir, "pecan.CONFIGS.xml"))
}

if (PEcAn.utils::status.check("MODEL") == 0) {
  PEcAn.utils::status.start("MODEL")
  PEcAn.workflow::runModule_start_model_runs(settings, stop.on.error = FALSE)
  PEcAn.utils::status.end()
}

if (PEcAn.utils::status.check("OUTPUT") == 0) {
  PEcAn.utils::status.start("OUTPUT")
  runModule.get.results(settings)
  PEcAn.utils::status.end()
}

if (PEcAn.utils::status.check("SENSITIVITY") == 0) {
  PEcAn.utils::status.start("SENSITIVITY")
  runModule.run.sensitivity.analysis(settings)
  PEcAn.utils::status.end()
}

PEcAn.logger::logger.info("sensitivity analysis complete: ", length(settings),
                          " blocks under ", settings$outdir)
