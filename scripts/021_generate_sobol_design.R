#!/usr/bin/env Rscript

library(PEcAn.all)
library(PEcAn.logger)
library(readr)

PEcAn.logger::logger.info("*** Starting 021_generate_sobol_design.R ***")

# -----------------------------------------------------------------------
# Runtime parameters
# -----------------------------------------------------------------------
options <- list(
  optparse::make_option(c("-s", "--settings"),
    default = "data_raw/settings_sa.xml",
    help = "Path to multisite SA settings XML"
  ),
  optparse::make_option(c("-N", "--sample-size"),
    default = 512,
    help = "Sobol base sample size (total = N*(k+2))"
  ),
  optparse::make_option(c("-o", "--output"),
    default = "data/sobol_design_matrix.csv",
    help = "Output path for design matrix"
  )
)

args <- optparse::OptionParser(option_list = options) |>
  optparse::parse_args()

# -----------------------------------------------------------------------
# Load settings
# -----------------------------------------------------------------------
settings <- PEcAn.settings::read.settings(args$settings)

# -----------------------------------------------------------------------
# Determine which PFTs are actually used across all sites
# -----------------------------------------------------------------------

site_pfts <- character(0)
for (site_settings in settings$run) {
  if (!is.null(site_settings$site$pft)) {
    site_pfts <- c(site_pfts, unlist(site_settings$site$pft))
  }
}
site_pfts <- unique(site_pfts)

# -----------------------------------------------------------------------
# Extract parameter priors ONLY from PFTs used in sites
# -----------------------------------------------------------------------
params <- list()

# We need to track the source PFT for each parameter column
# so Format -- list( unique_param_name = "pft_name" )
param_source_map <- list()

for (pft in settings$pfts) {
  pft_name <- pft$name
  
  # Optional: Skip PFTs not in site_pfts if strict filtering desired
  # if (!(pft_name %in% site_pfts)) next
  
  posterior_file <- pft$posterior.files
  
  if (!file.exists(posterior_file)) {
    PEcAn.logger::logger.severe(
      sprintf("Posterior file not found for PFT '%s': %s", pft_name, posterior_file)
    )
  }
  
  # Load posterior distributions
  distns <- new.env()
  load(posterior_file, envir = distns)
  
  # Check which object exists
  if (exists("post.distns", envir = distns)) {
    distns_df <- distns$post.distns
  } else if (exists("prior.distns", envir = distns)) {
    distns_df <- distns$prior.distns
    PEcAn.logger::logger.warn(sprintf("Using prior (not posterior) for PFT '%s'", pft_name))
  } else {
    PEcAn.logger::logger.severe(sprintf("No distributions found in %s", posterior_file))
  }
  
  # We loop through parameters and prefix them with the PFT name.
  # This ensures "grass.SLA" and "tree.SLA" are distinct columns in the Sobol design.
  for (i in seq_len(nrow(distns_df))) {
    raw_param_name <- rownames(distns_df)[i]
    
    # Create a Unique Name -- "pftname.paramname"
    unique_param_name <- paste(pft_name, raw_param_name, sep = ".")
    
    # Check for duplicates (should be impossible with prefix, but good safety)
    if (unique_param_name %in% names(params)) {
      PEcAn.logger::logger.warn(sprintf("Duplicate parameter detected: %s", unique_param_name))
    }
    
    # Save distribution info
    params[[unique_param_name]] <- list(
      distn = as.character(distns_df[i, "distn"]),
      parama = as.numeric(distns_df[i, "parama"]),
      paramb = as.numeric(distns_df[i, "paramb"]),
      pft = pft_name,
      original_name = raw_param_name # Store raw name for reconstruction
    )
    
    # Record source for metadata
    param_source_map[[unique_param_name]] <- pft_name
  }
}

# -----------------------------------------------------------------------
# Count available IC and met files from settings
# -----------------------------------------------------------------------
first_site <- settings$run[[1]]
ic_paths <- first_site$inputs$poolinitcond$path
n_ic <- length(ic_paths)
met_paths <- first_site$inputs$met$path
n_met <- length(met_paths)

# -----------------------------------------------------------------------
# Add Dummy Parameter for Factor Fixing
# -----------------------------------------------------------------------
# We add a 'dummy' parameter that samples Uniform(0,1).
# This serves as a baseline for numerical approximation error.
params[["dummy"]] <- list(
  distn = "unif",
  parama = 0,
  paramb = 1,
  pft = "driver", # Label it as a driver so it doesn't get confused with PFTs
  original_name = "dummy"
)

param_source_map[["dummy"]] <- NA_character_ 

# -----------------------------------------------------------------------
# Generate Sobol design
# -----------------------------------------------------------------------
source("R/global_sensitivity.R")

# params now contains uniquely namespaced keys (e.g. "grass.SLA")
sobol_design <- generate_sobol_design(
  N = as.integer(args$`sample-size`),
  params = params, 
  ic_range = 1:n_ic,
  met_range = 1:n_met
)

PEcAn.logger::logger.info(
  sprintf("Generated Sobol design: %d runs * %d columns", 
          nrow(sobol_design), ncol(sobol_design))
)

# -----------------------------------------------------------------------
# Save outputs
# -----------------------------------------------------------------------
output_dir <- dirname(args$output)
if (!dir.exists(output_dir)) {
  dir.create(output_dir, recursive = TRUE)
}

readr::write_csv(sobol_design, args$output)

# Save metadata
param_names_ordered <- names(params)
param_sources_ordered <- sapply(param_names_ordered, function(x) param_source_map[[x]])

metadata <- list(
  N = as.integer(args$`sample-size`),
  k = length(params), # PFT params only
  total_runs = nrow(sobol_design),
  n_ic = n_ic,
  n_met = n_met,
  n_pfts = length(site_pfts),
  pft_names = site_pfts,
  param_names = param_names_ordered, # These are now "pft.param"
  param_sources = unlist(param_sources_ordered), # required for 022 script
  generated_at = Sys.time(),
  settings_file = args$settings
)

metadata_file <- file.path(output_dir, "sobol_design_metadata.rds")
saveRDS(metadata, metadata_file)

PEcAn.logger::logger.info("*** Finished 021_generate_sobol_design.R ***")