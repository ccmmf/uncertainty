#!/usr/bin/env Rscript
# 031_partition_variance.R
# Variance decomposition: combine Sobol indices with ensemble variance
# to partition forecast uncertainty into parameter / driver / IC / management.
# Outputs: data/ensemble_variance.csv, data/variance_partition_*.csv

library(PEcAn.settings, include.only = "read.settings")
library(readr, include.only = c("read_csv", "write_csv"))
library(yaml, include.only = "read_yaml")
library(PEcAn.logger)

source("R/variance_decomposition.R")

# --- CLI args ---
opts <- list(
  optparse::make_option(c("-c", "--config"),
    default = "000-config.yml",
    help = "Path to project config YAML [default: %default]"
  ),
  optparse::make_option(c("-f", "--force"),
    action = "store_true", default = FALSE,
    help = "Overwrite existing output"
  )
)

args <- optparse::parse_args(optparse::OptionParser(option_list = opts))

# --- config ---
cfg <- yaml::read_yaml(args$config)

data_dir   <- cfg$default$paths$data_dir %||% "data"
output_dir <- "output"

final_output <- file.path(data_dir, "variance_partition_site_level.csv")

# skip-if-exists guard
if (!args$force && file.exists(final_output)) {
  PEcAn.logger::logger.info(
    "Output exists: ", final_output, ". Use --force to regenerate. Skipping."
  )
  quit(save = "no", status = 0)
}

if (!dir.exists(data_dir)) dir.create(data_dir, recursive = TRUE)

plots_dir <- file.path(data_dir, "plots")
if (!dir.exists(plots_dir)) dir.create(plots_dir, recursive = TRUE)

# --- load sobol indices and metadata ---
sobol_indices <- safe_read_csv(file.path(data_dir, "sobol_indices.csv"))

sobol_metadata_path <- file.path(data_dir, "sobol_design_metadata.rds")
if (!file.exists(sobol_metadata_path)) {
  PEcAn.logger::logger.severe("Sobol metadata not found: ", sobol_metadata_path)
}
sobol_metadata <- readRDS(sobol_metadata_path)

# --- load settings (for runid -> site_id mapping) ---
settings_path <- file.path(output_dir, "pecan.CONFIGS.xml")
if (!file.exists(settings_path)) {
  PEcAn.logger::logger.severe("Settings not found: ", settings_path)
}
settings <- PEcAn.settings::read.settings(settings_path)

# --- calculate ensemble variance ---
run_ids <- unique(sobol_indices$runid)

ensemble_variance <- calculate_ensemble_variance(
  output_dir = output_dir,
  run_ids    = run_ids,
  settings   = settings
)

if (is.null(ensemble_variance) || nrow(ensemble_variance) == 0) {
  PEcAn.logger::logger.severe("No ensemble variance computed.")
}

readr::write_csv(ensemble_variance, file.path(data_dir, "ensemble_variance.csv"))

# --- partition variance by category ---
variance_partition_site <- partition_variance_sources(
  sobol_indices    = sobol_indices,
  ensemble_variance = ensemble_variance,
  sobol_metadata   = sobol_metadata
)

readr::write_csv(variance_partition_site, final_output)

# --- load local SA for parameter-level breakdown ---
local_sa <- safe_read_csv(file.path(data_dir, "aggregated_sensitivity.csv"))

variance_partition_params <- partition_parameter_variance_local(
  local_sa                = local_sa,
  variance_partition_site = variance_partition_site,
  ensemble_variance       = ensemble_variance
)

readr::write_csv(
  variance_partition_params,
  file.path(data_dir, "variance_partition_parameters.csv")
)

# --- category-level summary ---
category_summary <- variance_partition_site |>
  dplyr::filter(.data$category != "interaction") |>
  dplyr::summarize(
    mean_frac   = mean(.data$frac_of_total, na.rm = TRUE),
    median_frac = median(.data$frac_of_total, na.rm = TRUE),
    sd_frac     = sd(.data$frac_of_total, na.rm = TRUE),
    n_sites     = dplyr::n(),
    .by = c("variable", "category")
  ) |>
  dplyr::arrange(.data$variable, dplyr::desc(.data$mean_frac))

readr::write_csv(category_summary, file.path(data_dir, "variance_partition_summary.csv"))

# --- parameter-level summary ---
param_summary <- variance_partition_params |>
  dplyr::filter(!is.na(.data$Var_parameter_param)) |>
  dplyr::summarize(
    mean_frac   = mean(.data$frac_of_total, na.rm = TRUE),
    median_frac = median(.data$frac_of_total, na.rm = TRUE),
    sd_frac     = sd(.data$frac_of_total, na.rm = TRUE),
    n_sites     = dplyr::n(),
    .by = c("response_var", "parameter")
  ) |>
  dplyr::arrange(.data$response_var, dplyr::desc(.data$mean_frac))

readr::write_csv(param_summary, file.path(data_dir, "variance_partition_params_summary.csv"))

# --- generate plots ---
create_variance_plots(
  variance_partition_site = variance_partition_site,
  param_summary           = param_summary,
  plots_dir               = plots_dir
)

PEcAn.logger::logger.info("Variance decomposition complete")
