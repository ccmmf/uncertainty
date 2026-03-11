#!/usr/bin/env Rscript
# Compute Sobol sensitivity indices from ensemble output.
# Outputs: data/sobol_indices.csv

library(readr, include.only = c("read_csv", "write_csv"))
library(yaml, include.only = "read_yaml")
library(PEcAn.logger)

source("R/global_sensitivity.R")

# --- CLI args ---
opts <- list(
  optparse::make_option(c("-c", "--config"),
    default = "000-config.yml",
    help = "Path to project config YAML [default: %default]"
  ),
  optparse::make_option(c("-o", "--output"),
    default = "data/sobol_indices.csv",
    help = "Output CSV path [default: %default]"
  ),
  optparse::make_option(c("-f", "--force"),
    action = "store_true", default = FALSE,
    help = "Overwrite existing output"
  )
)

args <- optparse::parse_args(optparse::OptionParser(option_list = opts))

# --- config ---
cfg <- yaml::read_yaml(args$config)
output_csv <- args$output

# skip-if-exists guard
if (!args$force && file.exists(output_csv)) {
  PEcAn.logger::logger.info(
    "Output exists: ", output_csv, ". Use --force to regenerate. Skipping."
  )
  quit(save = "no", status = 0)
}

if (!dir.exists(dirname(output_csv))) {
  dir.create(dirname(output_csv), recursive = TRUE)
}

# --- load metadata ---
metadata <- readRDS("data/sobol_design_matrix_metadata.rds")

N <- metadata$N

# param_names includes PFT traits + management quantiles + dummy
design_params <- metadata$param_names
params <- c(design_params, "ic_ensemble", "met_ensemble")

PEcAn.logger::logger.info(
  sprintf("Computing indices for %d parameters (including IC/Met)", length(params))
)

# --- locate output files and extract run IDs ---
output_dir <- "output"
all_files <- list.files(
  output_dir,
  "^ensemble\\.output.*\\.Rdata$",
  full.names = TRUE
)

if (length(all_files) == 0) {
  PEcAn.logger::logger.severe("No ensemble.output.*.Rdata found!")
}

run_ids <- unique(vapply(
  strsplit(basename(all_files), "\\."),
  \(x) x[3],
  character(1)
))

# --- compute indices ---
wide <- compute_sobol_indices(
  output_dir = output_dir,
  run_ids    = run_ids,
  params     = params,
  N          = N,
  R          = 500L
)

readr::write_csv(wide, output_csv)

PEcAn.logger::logger.info("Saved Sobol indices to ", output_csv)
