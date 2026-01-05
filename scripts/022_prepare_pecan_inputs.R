#!/usr/bin/env Rscript

# =======================================================================
# 022_prepare_pecan_inputs.R
# Convert Sobol design to PEcAn format (trait.samples + input_design)
# =======================================================================

library(PEcAn.all)
library(PEcAn.logger)
library(readr)

PEcAn.logger::logger.info("*** Starting 022_prepare_pecan_inputs.R ***")

# -----------------------------------------------------------------------
# Runtime parameters
# -----------------------------------------------------------------------
options <- list(
  optparse::make_option(c("-s", "--settings"),
    default = "data_raw/settings_sa.xml",
    help = "Path to multisite SA settings XML"
  ),
  optparse::make_option(c("-d", "--design"),
    default = "data/sobol_design_matrix.csv",
    help = "Path to Sobol design matrix"
  )
)

args <- optparse::OptionParser(option_list = options) |>
  optparse::parse_args()

# -----------------------------------------------------------------------
# Load inputs
# -----------------------------------------------------------------------
settings <- PEcAn.settings::read.settings(args$settings)
sobol_design <- readr::read_csv(args$design, show_col_types = FALSE)
metadata <- readRDS("data/sobol_design_metadata.rds")

PEcAn.logger::logger.info(
  sprintf("Loaded Sobol design: %d samples * %d columns", 
          nrow(sobol_design), ncol(sobol_design))
)

# -----------------------------------------------------------------------
# Create trait.samples
# -----------------------------------------------------------------------
# We need to parse the column names (e.g. "grass.SLA") back into PFT lists.

site_pfts <- unique(unlist(lapply(settings$run, function(s) s$site$pft)))

trait.samples <- list()
# Initialize empty lists for all active PFTs
for (pft_name in site_pfts) {
  trait.samples[[pft_name]] <- list()
}

# Iterate over all columns in the Sobol Design
for (col_name in names(sobol_design)) {
  
  # Skip metadata/driver/dummy columns
  if (col_name %in% c("sample_id", "ic_ensemble", "met_ensemble", "dummy")) next
  
  # PARSE: Split "pft.param" -> "pft" and "param"
  # We expect format: "pftname.paramname" from Script 021
  parts <- strsplit(col_name, "\\.")[[1]]
  
  # Handle case where param name itself might contain dots, though rare in PEcAn
  pft_prefix <- parts[1]
  # Reassemble param name if it had dots
  actual_param_name <- paste(parts[-1], collapse = ".") 
  
  # Only put this data into the correct PFT list
  if (pft_prefix %in% names(trait.samples)) {
    # We assign the vector of values from the design matrix
    trait.samples[[pft_prefix]][[actual_param_name]] <- sobol_design[[col_name]]
  }
}

PEcAn.logger::logger.info(
  sprintf("Parsed parameters for PFTs: %s", paste(names(trait.samples), collapse=", "))
)

# -----------------------------------------------------------------------
# Create ensemble.samples (Data Frames)
# -----------------------------------------------------------------------
# Note: PEcAn requires 'ensemble.samples' to be a list of Data Frames.
# 'trait.samples' is a list of lists (vectors).

ensemble.samples <- list()

for (pft_name in names(trait.samples)) {
  # Convert the list of vectors into a df
  # Each column is a parameter, each row is a sample (run)
  if (length(trait.samples[[pft_name]]) > 0) {
    ensemble.samples[[pft_name]] <- as.data.frame(trait.samples[[pft_name]])
  } else {
    # Edge case: PFT in site but no params sampled (use defaults)
    # Create dummy df with correct number of rows
    ensemble.samples[[pft_name]] <- data.frame(row.names = 1:nrow(sobol_design))
  }
}

# -----------------------------------------------------------------------
# Create input_design
# -----------------------------------------------------------------------
# Maps run ID to sample index. Since our design is 1-to-1, indices match sample_id.
input_design <- data.frame(
  param = sobol_design$sample_id,        
  poolinitcond = sobol_design$ic_ensemble, 
  met = sobol_design$met_ensemble 
)

PEcAn.logger::logger.info(
  sprintf("Created input_design: %d rows * %d columns", 
          nrow(input_design), ncol(input_design))
)

# -----------------------------------------------------------------------
# Save samples.Rdata
# -----------------------------------------------------------------------
sa.samples <- NULL
runs.samples <- list()
env.samples <- list()
pft.names <- names(trait.samples)
trait.names <- lapply(trait.samples, names)

# create output directory if it doesn't exist
if (!dir.exists(settings$outdir)) {
  dir.create(settings$outdir, recursive = TRUE)
}

# Save correctly formatted objects
save(
  ensemble.samples, # List of data frames
  trait.samples,    # List of Lists
  sa.samples, 
  runs.samples, 
  pft.names, 
  trait.names,
  env.samples,
  file = file.path(settings$outdir, "samples.Rdata")
)

# -----------------------------------------------------------------------
# Save input_design
# -----------------------------------------------------------------------
cache_dir <- "cache"
if (!dir.exists(cache_dir)) {
  dir.create(cache_dir, recursive = TRUE)
}
saveRDS(input_design, "cache/input_design.rds")
readr::write_csv(input_design, "data/input_design.csv")

PEcAn.logger::logger.info("*** Finished 022_prepare_pecan_inputs.R ***")