#!/usr/bin/env Rscript

# =======================================================================
# 012_aggregate_sensitivity.R
# Aggregate sensitivity analysis results across design points
# =======================================================================

library(config)
library(dplyr)
library(readr)
library(tidyr)
library(ggplot2)
library(PEcAn.logger)
library(PEcAn.settings)

PEcAn.logger::logger.info("*** Starting 012_aggregate_sensitivity.R ***")

# Source helper functions
source("R/local_sensitivity.R")

# -----------------------------------------------------------------------
# Load config and settings
# -----------------------------------------------------------------------
cfg <- config::get(file = "000-config.yml")

if (!dir.exists(cfg$paths$data_dir)) {
  dir.create(cfg$paths$data_dir, recursive = TRUE)
}

# Read PEcAn settings (use pecan.CONFIGS.xml from 011 run)
settings <- PEcAn.settings::read.settings(
  file.path("output", "pecan.CONFIGS.xml")
)

#----------------------------------
# read.settings() uses xmlToList loses duplicate <variable> tags, so read XML directly
library(XML)
xml_doc <- XML::xmlParse(file.path("output", "pecan.CONFIGS.xml"))
sa_variables <- unique(XML::xpathSApply(
  xml_doc,
  "//sensitivity.analysis//variable",
  XML::xmlValue
))
XML::free(xml_doc)

# -----------------------------------------------------------------------
# Load design points
# -----------------------------------------------------------------------
design_points <- readr::read_csv(
  file.path(cfg$paths$raw_data_dir, "sa_design_points.csv")
)

site_covariates <- readr::read_csv(
  file.path(cfg$paths$ccmmf_dir, "data/site_covariates.csv")
) |>
  dplyr::filter(site_id %in% design_points$site_id) |>
  dplyr::select(site_id, temp, precip, clay, ocd, twi) |>
  dplyr::rename(MAT = temp, MAP = precip)

gradient_vars <- c("MAT", "MAP", "clay", "ocd", "twi")
# -----------------------------------------------------------------------
# Aggregate sensitivity results
# -----------------------------------------------------------------------
PEcAn.logger::logger.info("Aggregating sensitivity results...")

aggregated_results <- aggregate_local_sa(
  sensitivity_outdir = settings$outdir,
  design_points = design_points,
  response_vars = sa_variables
)

readr::write_csv(aggregated_results, file.path(cfg$paths$data_dir, "aggregated_sensitivity.csv"))

# -----------------------------------------------------------------------
# Summarize
# -----------------------------------------------------------------------
PEcAn.logger::logger.info("Generating summary...")

summary_results <- summarize_local_sa(aggregated_results)

readr::write_csv(
  summary_results$parameter_rankings,
  file.path(cfg$paths$data_dir, "parameter_rankings.csv")
)

readr::write_csv(
  summary_results$pft_differences,
  file.path(cfg$paths$data_dir, "pft_differences.csv")
)

# -----------------------------------------------------------------------
# Environmental gradients
# -----------------------------------------------------------------------
PEcAn.logger::logger.info("Analyzing environmental gradients...")

gradient_analysis <- analyze_environmental_gradients(
  aggregated_results = aggregated_results,
  env_covariates = site_covariates,
  gradient_vars = gradient_vars,
  min_sites = 5,
  significance_level = 0.05,
  r2_threshold = 0.1
)

# Save FULL regression results (all combinations, both targets)
readr::write_csv(
  gradient_analysis$regression_results,
  file.path(cfg$paths$data_dir, "regression_results.csv")
)

# Save filtered significant gradients (for quick reference)
readr::write_csv(
  gradient_analysis$significant_gradients,
  file.path(cfg$paths$data_dir, "significant_gradients.csv")
)

PEcAn.logger::logger.info(
  "Found ", nrow(gradient_analysis$significant_gradients), " significant gradients"
)

# -----------------------------------------------------------------------
# Plots
# -----------------------------------------------------------------------
PEcAn.logger::logger.info("Generating plots...")

plots_dir <- file.path(cfg$paths$data_dir, "plots")
if (!dir.exists(plots_dir)) dir.create(plots_dir, recursive = TRUE)

# Parameter rankings
for (var in sa_variables) {
  p <- summary_results$parameter_rankings |>
    dplyr::filter(response_var == var) |>
    dplyr::slice_head(n = 15) |>
    ggplot(aes(x = reorder(parameter, mean_abs_elasticity), y = mean_abs_elasticity)) +
    geom_col(fill = "steelblue") +
    coord_flip() +
    labs(
      title = paste("Top 15 Parameters for", var),
      x = "Parameter",
      y = "Mean Absolute Elasticity"
    ) +
    theme_minimal()
  
  ggsave(
    file.path(plots_dir, paste0("param_ranking_", var, ".png")),
    p, width = 8, height = 6, dpi = 300
  )
}

for (var in sa_variables) {
  for (grad in gradient_vars) {
    p_gradient <- plot_sensitivity_gradient(
      aggregated_results = aggregated_results,
      env_covariates = site_covariates,
      gradient_var = grad,
      top_n_parameters = 9,
      response_var = var
    )
    ggsave(
      file.path(plots_dir, paste0("sensitivity_vs_", grad, "_", var, ".png")),
      p_gradient, width = 12, height = 8, dpi = 300
    )
  }
}


PEcAn.logger::logger.info("*** Finished 012_aggregate_sensitivity.R ***")
