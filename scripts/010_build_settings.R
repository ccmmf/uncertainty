#!/usr/bin/env Rscript

# expand a site table into one multi-site settings.xml.
#
#   Rscript scripts/010_build_settings.R [-c examples/calval/config.yml]

suppressMessages(library(PEcAn.settings))
source("R/data_root.R")
source("R/build_settings.R")

args <- optparse::parse_args(optparse::OptionParser(option_list = list(
  optparse::make_option(c("-c", "--config"), default = "examples/calval/config.yml",
    help = "project config [default: %default]")
)))
config <- config::get(file = args$config)

sites <- utils::read.csv(config$sites, stringsAsFactors = FALSE)
settings <- build_settings(
  sites = sites,
  template = config$template,
  input_root = data_root(config$input_root),
  binary = data_root(config$binary),
  outdir = data_root(config$workspace, "output"),
  ensemble_size = config$ensemble_size
)

dir.create(data_root(config$workspace), recursive = TRUE, showWarnings = FALSE)

# modellauncher$binary is relative to the run directory and qsub runs with -cwd,
# so the workspace needs its own copy of the launcher or every array task dies
# before the model starts
launcher_dir <- data_root(config$workspace, "scripts")
dir.create(launcher_dir, recursive = TRUE, showWarnings = FALSE)
file.copy("scripts/sge_array_launcher.sh", launcher_dir, overwrite = TRUE)
Sys.chmod(file.path(launcher_dir, "sge_array_launcher.sh"), "0755")

write.settings(settings, outputfile = "settings.xml",
               outputdir = data_root(config$workspace))
PEcAn.logger::logger.info("wrote ", data_root(config$workspace, "settings.xml"),
                          ": ", nrow(sites), " blocks")
