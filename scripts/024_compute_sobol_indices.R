#!/usr/bin/env Rscript

library(sensobol)
library(dplyr)
library(readr)
library(stringr)
library(tidyr)
library(PEcAn.logger)

PEcAn.logger::logger.info("*** Starting 024_compute_sobol_indices.R ***")

# -------------------------------------------------------------------
# Load metadata
# -------------------------------------------------------------------
metadata <- readRDS("data/sobol_design_metadata.rds")

N <- metadata$N
expected_len <- metadata$total_runs

# -------------------------------------------------------------------
# Reconstruct Parameter List
# -------------------------------------------------------------------
# The Sobol design included PFT parameters PLUS ic_ensemble and met_ensemble.
# We must include them here so sensobol calculates their sensitivity indices.
pft_params <- metadata$param_names
params <- c(pft_params, "ic_ensemble", "met_ensemble")
k <- length(params)

PEcAn.logger::logger.info(
  sprintf("Computing indices for %d parameters (including IC/Met)", k)
)

# -------------------------------------------------------------------
# Locate output files
# -------------------------------------------------------------------
all_files <- list.files("output",
                        "^ensemble\\.output.*\\.Rdata$",
                        full.names = TRUE)

if (length(all_files) == 0) {
  PEcAn.logger::logger.severe("No ensemble.output.*.Rdata found!")
}

# Extract RUNIDs
run_ids <- unique(sapply(strsplit(basename(all_files), "\\."), `[`, 3))

results_all_sites <- list()

# -------------------------------------------------------------------
# Process each site
# -------------------------------------------------------------------
for (rid in run_ids) {

  site_files <- grep(
    paste0("^output/ensemble\\.output\\.", rid),
    paste0("output/", basename(all_files)),
    value = TRUE
  )

  if (length(site_files) == 0) next
  
  # variable -- 4th token in filename structure
  vars <- unique(sapply(strsplit(basename(site_files), "\\."),
                        function(x) x[4]))

  site_results <- list()

  for (v in vars) {

    vf <- site_files[
      sapply(strsplit(basename(site_files), "\\."), function(x) x[4] == v)
    ]

    if (length(vf) != 1) {
      PEcAn.logger::logger.error(sprintf(
        "Variable %s for runid %s has %d files!",
        v, rid, length(vf)))
      next
    }

    load(vf)
    # ensemble.output is a list of means; unlist to get vector Y
    Y <- as.numeric(unlist(ensemble.output))

    if (length(Y) != expected_len) {
      PEcAn.logger::logger.severe(sprintf(
        "Variable %s for RID %s has %d values (expected %d)",
        v, rid, length(Y), expected_len))
    }

    # -------------------------------
    # Compute Sobol indices
    # -------------------------------
    # We assume the design was generated with type="QRN", order="first", matrices=c("A", "B", "AB")
    # This defaults to first="saltelli", total="jansen" in sobol_indices
    
    idx <- sensobol::sobol_indices(
      Y = Y,
      N = N,
      params = params,
      boot = TRUE,
      R = 500
    )

    df <- as.data.frame(idx$results)
    df$variable <- v
    df$runid <- rid

    site_results[[v]] <- df
  }

  results_all_sites[[rid]] <- bind_rows(site_results)
}

long <- bind_rows(results_all_sites)

# -------------------------------------------------------------------
# Convert to wide format (final output)
# -------------------------------------------------------------------
wide <- long %>%
  select(runid, variable, parameters, sensitivity,
         original, low.ci, high.ci, bias, std.error) %>%
  pivot_wider(
    names_from = sensitivity,
    values_from = c(original, low.ci, high.ci, bias, std.error),
    names_glue = "{sensitivity}_{.value}"
  ) %>%
  arrange(runid, variable, parameters)

# -------------------------------------------------------------------
# Save final file
# -------------------------------------------------------------------
write.csv(wide, "data/sobol_indices.csv", row.names = FALSE)

PEcAn.logger::logger.info("*** Finished 024_compute_sobol_indices.R ***")