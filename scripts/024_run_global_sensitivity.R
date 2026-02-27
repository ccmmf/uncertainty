#!/usr/bin/env Rscript
# 024 -- Run PEcAn global sensitivity workflow (CONFIG, events copy, MODEL, OUTPUT).

library(PEcAn.all)
library(PEcAn.logger)
library(readr, include.only = "read_csv")
library(yaml, include.only = "read_yaml")

source("R/global_sensitivity.R")

# events paths are registered via setEnsemblePaths in the CONFIG step below;
# write.configs.SIPNET copies inputs$events$path into each run directory.

# --- CLI args ---
opts <- list(
  optparse::make_option(c("-c", "--config"),
    default = "000-config.yml",
    help = "Path to project config YAML [default: %default]"
  ),
  optparse::make_option(c("-s", "--settings"),
    default = NULL,
    help = "Path to PEcAn settings XML (overrides config)"
  ),
  optparse::make_option(c("--continue"),
    action = "store_true", default = FALSE,
    help = "Continue previously interrupted workflow"
  ),
  optparse::make_option(c("-f", "--force"),
    action = "store_true", default = FALSE,
    help = "Force re-run even if status file exists"
  )
)

args <- optparse::parse_args(optparse::OptionParser(option_list = opts))

options(warn = 1)
options(error = quote({
  try(PEcAn.utils::status.end("ERROR"))
  if (!interactive()) q(status = 1)
}))

# --- config ---
cfg <- yaml::read_yaml(args$config)
settings_xml <- args$settings %||% cfg$settings_xml %||% "data_raw/settings_sa.xml"
settings <- PEcAn.settings::read.settings(settings_xml)

if (!dir.exists(settings$outdir)) {
  dir.create(settings$outdir, recursive = TRUE)
}

EVENTS_DIR <- cfg$events_dir %||% "data/events"

# ensemble$size = 1: each sample in input_design is a full run;
# PEcAn iterates over rows of input_design, not ensemble$size
settings$ensemble$size <- 1

input_design <- readRDS("cache/input_design.rds")

status_file <- file.path(settings$outdir, "STATUS")
if (!args$continue && file.exists(status_file)) file.remove(status_file)

# --- Register per-sample events via setEnsemblePaths ---
# PEcAn standard: each ensemble member gets its own events.in path
# via settings$run$site.X$inputs$events$path (like IC and met).
n_samples <- nrow(input_design)
events_path <- normalizePath(EVENTS_DIR)

settings <- PEcAn.settings::setEnsemblePaths(
  settings,
  n_reps = n_samples,
  input_type = "events",
  path = events_path,
  path_template = "{path}/events_sample_{n}.in"
)

PEcAn.logger::logger.info(
  "Registered ", n_samples, " per-sample events via setEnsemblePaths"
)

# --- CONFIG step ---
if (PEcAn.utils::status.check("CONFIG") == 0) {
  PEcAn.utils::status.start("CONFIG")
  settings <- runModule.run.write.configs(
    settings = settings,
    input_design = input_design
  )
  PEcAn.settings::write.settings(settings, outputfile = "pecan.CONFIGS.xml")
  PEcAn.utils::status.end()
} else {
  settings <- PEcAn.settings::read.settings(
    file.path(settings$outdir, "pecan.CONFIGS.xml")
  )
}

# --- MODEL step ---
if (PEcAn.utils::status.check("MODEL") == 0) {
  PEcAn.utils::status.start("MODEL")
  PEcAn.workflow::runModule_start_model_runs(settings, stop.on.error = FALSE)
  PEcAn.utils::status.end()
}

# --- OUTPUT step ---
loglevel <- PEcAn.logger::logger.setLevel("WARN")
if (PEcAn.utils::status.check("OUTPUT") == 0) {
  PEcAn.utils::status.start("OUTPUT")
  runModule.get.results(settings)
  PEcAn.utils::status.end()
}
PEcAn.logger::logger.setLevel(loglevel)

PEcAn.logger::logger.info("PEcAn Global SA Workflow Complete")
