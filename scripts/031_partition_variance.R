#!/usr/bin/env Rscript

# =======================================================================
# 031_partition_variance.R
# 
# Variance Decomposition / Uncertainty Partitioning
# 
# This script combines:
#  - Global Sobol sensitivity indices
#  - Ensemble variance from global SA runs
#  - Local OAT partial variances
#
# to partition total ensemble variance among:
#  - Parameter uncertainty
#  - Initial condition uncertainty
#  - Driver (met) uncertainty
#  - Dummy (numerical baseline)
#  - Interaction effects
#
# Then uses local SA to break the parameter component down to 
# individual parameters.
#
# Outputs:
#  - data/ensemble_variance.csv
#  - data/variance_partition_site_level.csv
#  - data/variance_partition_parameters.csv
#  - data/plots/variance_partition_*.png
# =======================================================================

library(config)
library(dplyr)
library(readr)
library(tidyr)
library(ggplot2)
library(purrr)
library(PEcAn.logger)
library(PEcAn.settings)

# Source helper functions
source("R/variance_decomposition.R")

# Load config
cfg <- config::get(file = "000-config.yml")

data_dir   <- cfg$paths$data_dir
output_dir <- "output" #cfg$paths$output_dir  # Typically "output" where ensemble files live

if (!dir.exists(data_dir)) {
  dir.create(data_dir, recursive = TRUE)
}

plots_dir <- file.path(data_dir, "plots")
if (!dir.exists(plots_dir)) {
  dir.create(plots_dir, recursive = TRUE)
}


# Helper func: CSV reader
safe_read_csv <- function(path, ...) {
  if (!file.exists(path)) {
    PEcAn.logger::logger.severe(paste("File not found:", path))
  }
  readr::read_csv(path, show_col_types = FALSE, ...)
}

# 1. Load Sobol indices and metadata
sobol_indices_path <- file.path(data_dir, "sobol_indices.csv")
sobol_indices <- safe_read_csv(sobol_indices_path)

sobol_metadata_path <- file.path(data_dir, "sobol_design_metadata.rds")
if (!file.exists(sobol_metadata_path)) {
  PEcAn.logger::logger.severe(paste("Sobol metadata not found:", sobol_metadata_path))
}
sobol_metadata <- readRDS(sobol_metadata_path)


# 2. Load PEcAn settings (for runid -> site_id mapping)
settings_path <- file.path(output_dir, "pecan.CONFIGS.xml")
if (!file.exists(settings_path)) {
  PEcAn.logger::logger.severe(paste("Settings file not found:", settings_path))
}
settings <- PEcAn.settings::read.settings(settings_path)


# 3. Calculate ensemble variance
# Extract unique run IDs from sobol_indices
run_ids <- unique(sobol_indices$runid)

ensemble_variance <- calculate_ensemble_variance(
  output_dir = output_dir,
  run_ids = run_ids,
  settings = settings
)

if (is.null(ensemble_variance) || nrow(ensemble_variance) == 0) {
  PEcAn.logger::logger.severe("No ensemble variance computed. Check ensemble output files.")
}

# Save ensemble variance for reference
ensemble_var_path <- file.path(data_dir, "ensemble_variance.csv")
readr::write_csv(ensemble_variance, ensemble_var_path)


# 4. Partition variance by category (parameter, IC, driver, dummy, interaction)
variance_partition_site <- partition_variance_sources(
  sobol_indices = sobol_indices,
  ensemble_variance = ensemble_variance,
  sobol_metadata = sobol_metadata
)

# Save site-level variance partition
site_partition_path <- file.path(data_dir, "variance_partition_site_level.csv")
readr::write_csv(variance_partition_site, site_partition_path)


# 5. Load local SA results for parameter-level breakdown
local_sa_path <- file.path(data_dir, "aggregated_sensitivity.csv")
local_sa <- safe_read_csv(local_sa_path)


# 6. Partition parameter variance into individual parameters
variance_partition_params <- partition_parameter_variance_local(
  local_sa = local_sa,
  variance_partition_site = variance_partition_site,
  ensemble_variance = ensemble_variance
)

# Save parameter-level variance partition
param_partition_path <- file.path(data_dir, "variance_partition_parameters.csv")
readr::write_csv(variance_partition_params, param_partition_path)


# 7. Generate summary statistics
# Category-level summary across all sites
category_summary <- variance_partition_site %>%
  filter(category != "interaction") %>%  # Exclude interaction for mean calculation
  group_by(variable, category) %>%
  summarize(
    mean_frac = mean(frac_of_total, na.rm = TRUE),
    median_frac = median(frac_of_total, na.rm = TRUE),
    sd_frac = sd(frac_of_total, na.rm = TRUE),
    n_sites = n(),
    .groups = "drop"
  ) %>%
  arrange(variable, desc(mean_frac))

category_summary_path <- file.path(data_dir, "variance_partition_summary.csv")
readr::write_csv(category_summary, category_summary_path)

# Parameter-level summary (top parameters by variance contribution)
param_summary <- variance_partition_params %>%
  filter(!is.na(Var_parameter_param)) %>%
  group_by(response_var, parameter) %>%
  summarize(
    mean_frac = mean(frac_of_total, na.rm = TRUE),
    median_frac = median(frac_of_total, na.rm = TRUE),
    sd_frac = sd(frac_of_total, na.rm = TRUE),
    n_sites = n(),
    .groups = "drop"
  ) %>%
  arrange(response_var, desc(mean_frac))

param_summary_path <- file.path(data_dir, "variance_partition_params_summary.csv")
readr::write_csv(param_summary, param_summary_path)


# 8. Generate visualizations
# Get unique variables
variables <- unique(variance_partition_site$variable)

# Plot 1 -> Stacked bar chart of variance fractions by category for each variable
for (var in variables) {
  
  plot_data <- variance_partition_site %>%
    filter(variable == var, category != "interaction") %>%
    group_by(runid) %>%
    mutate(
      category = factor(category, 
                       levels = c("parameter", "IC", "driver", "dummy"))
    )
  
  p1 <- ggplot(plot_data, aes(x = runid, y = frac_of_total, fill = category)) +
    geom_col(position = "stack") +
    scale_fill_brewer(palette = "Set2", name = "Uncertainty source") +
    labs(
      title = paste("Variance partition by category:", var),
      subtitle = "Stacked by runid (site)",
      x = "Run ID (Site)",
      y = "Fraction of total variance"
    ) +
    theme_minimal() +
    theme(
      axis.text.x = element_text(angle = 45, hjust = 1, size = 8),
      legend.position = "bottom"
    )
  
  ggsave(
    file.path(plots_dir, paste0("variance_partition_stacked_", var, ".png")),
    p1, width = 10, height = 6, dpi = 300
  )
}

# Plot 2 -> Mean variance fractions across all sites by category
for (var in variables) {
  
  mean_fracs <- variance_partition_site %>%
    filter(variable == var, category != "interaction") %>%
    group_by(category) %>%
    summarize(
      mean_frac = mean(frac_of_total, na.rm = TRUE),
      sd_frac = sd(frac_of_total, na.rm = TRUE),
      .groups = "drop"
    ) %>%
    mutate(
      category = factor(category, 
                       levels = c("parameter", "IC", "driver", "dummy"))
    )
  
  p2 <- ggplot(mean_fracs, aes(x = category, y = mean_frac, fill = category)) +
    geom_col() +
    geom_errorbar(aes(ymin = mean_frac - sd_frac, ymax = mean_frac + sd_frac),
                  width = 0.2) +
    scale_fill_brewer(palette = "Set2", guide = "none") +
    labs(
      title = paste("Mean variance partition:", var),
      subtitle = "Averaged across all sites with ±1 SD",
      x = "Uncertainty source",
      y = "Mean fraction of total variance"
    ) +
    theme_minimal() +
    theme(axis.text.x = element_text(angle = 45, hjust = 1))
  
  ggsave(
    file.path(plots_dir, paste0("variance_partition_mean_", var, ".png")),
    p2, width = 8, height = 6, dpi = 300
  )
}

# Plot 3 -> Top parameters contributing to parameter variance
for (var in variables) {
  
  top_params <- param_summary %>%
    filter(response_var == var) %>%
    slice_head(n = 15)
  
  if (nrow(top_params) > 0) {
    p3 <- ggplot(top_params, 
                 aes(x = reorder(parameter, mean_frac), y = mean_frac)) +
      geom_col(fill = "steelblue") +
      geom_errorbar(aes(ymin = mean_frac - sd_frac, ymax = mean_frac + sd_frac),
                    width = 0.2) +
      coord_flip() +
      labs(
        title = paste("Top 15 Parameters contributing to", var, "variance"),
        subtitle = "Mean fraction of total variance +/-1 SD",
        x = "Parameter",
        y = "Mean fraction of total variance"
      ) +
      theme_minimal()
    
    ggsave(
      file.path(plots_dir, paste0("variance_partition_top_params_", var, ".png")),
      p3, width = 10, height = 8, dpi = 300
    )
  }
}

PEcAn.logger::logger.info("*** Finished 031_partition_variance.R ***")
