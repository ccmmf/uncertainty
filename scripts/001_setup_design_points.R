#!/usr/bin/env Rscript

# =======================================================================
# 001_setup_design_points.R
# Select representative design points for UA (Local + Global Sensitivity)
# =======================================================================

library(config)
library(dplyr)
library(readr)
library(furrr)
library(factoextra)
library(cluster)
library(PEcAn.logger)

PEcAn.logger::logger.info("*** Starting 001_setup_design_points.R ***")

# -----------------------------------------------------------------------
# Load Configuration
# -----------------------------------------------------------------------
cfg <- config::get(file = "000-config.yml")

ccmmf_dir    <- cfg$paths$ccmmf_dir
raw_data_dir <- cfg$paths$raw_data_dir
cache_dir    <- cfg$paths$cache_dir

design_file  <- file.path(raw_data_dir, "design_points_198.csv")

# -----------------------------------------------------------------------
# Load 198 mixed-PFT design points
# -----------------------------------------------------------------------
design_points <- readr::read_csv(design_file)

# -----------------------------------------------------------------------
# Load covariates
# -----------------------------------------------------------------------
covariate_path <- file.path(ccmmf_dir, "data/site_covariates.csv")

site_covariates <- readr::read_csv(covariate_path) |>
  dplyr::filter(site_id %in% design_points$site_id)

dp_cov <- design_points |>
  dplyr::left_join(site_covariates, by = "site_id")

# -----------------------------------------------------------------------
# Select covariates
# -----------------------------------------------------------------------
selected_covariates <- c("temp", "precip", "srad", "vapr",
                         "clay", "ocd", "twi")

missing <- setdiff(selected_covariates, names(dp_cov))
if (length(missing) > 0) {
  PEcAn.logger::logger.severe(
    "Missing covariates: ", paste(missing, collapse = ", ")
  )
}

clust_data <- dp_cov |>
  dplyr::select(site_id, all_of(selected_covariates)) |>
  tidyr::drop_na()

# -----------------------------------------------------------------------
# K-means clustering (select K using silhouette score)
# -----------------------------------------------------------------------

# now using 10 sites for testing will expand as design points expands;
# and will make the range configurable
k_range <- 2:10
scaled <- scale(clust_data |> dplyr::select(-site_id))

sil_scores <- purrr::map_dbl(k_range, function(k) {
  model <- kmeans(scaled, centers = k, nstart = 20)
  mean(cluster::silhouette(model$cluster, dist(scaled))[, 3])
})

elbow_k <- k_range[which.max(sil_scores)]

# -----------------------------------------------------------------------
# Final clustering
# -----------------------------------------------------------------------
final_model <- kmeans(scaled, centers = elbow_k, nstart = 25)

sites_clustered <- clust_data |>
  dplyr::mutate(cluster = final_model$cluster)

# Store intermediate result
saveRDS(sites_clustered, file.path(cache_dir, "sites_clustered.rds"))

set.seed(2025)  # reproducibility

dp_selected <- sites_clustered |>
  dplyr::slice_sample(n = 10) |>
  dplyr::left_join(design_points, by = "site_id") |>
  # Map LandIQ PFT names to PEcAn PFT names (currently used two pft in original design_points_198.csv)
  ddplyr::mutate(
    pft = dplyr::case_when(
      pft == "annual crop" ~ "grass",
      pft == "woody perennial crop" ~ "temperate.deciduous",
      TRUE ~ NA_character_
    )
  ) |>
  dplyr::select(site_id, lat, lon, pft)

out_file <- file.path(raw_data_dir, "sa_design_points.csv")
readr::write_csv(dp_selected, out_file)

PEcAn.logger::logger.info("Saved SA design points to ", out_file)
PEcAn.logger::logger.info("*** Finished 001_setup_design_points.R ***")
