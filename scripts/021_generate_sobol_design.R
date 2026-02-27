#!/usr/bin/env Rscript
# Generate Sobol design matrix for global sensitivity analysis.
# Outputs: data/sobol_design_matrix.csv, data/sobol_design_metadata.rds

library(PEcAn.all)
library(PEcAn.logger)
library(readr, include.only = c("read_csv", "write_csv"))
library(yaml, include.only = "read_yaml")

source("R/global_sensitivity.R")

opts <- list(
  optparse::make_option(c("-c", "--config"),
    default = "000-config.yml",
    help = "Path to project config YAML [default: %default]"
  ),
  optparse::make_option(c("-s", "--settings"),
    default = NULL,
    help = "Path to PEcAn settings XML (overrides config)"
  ),
  optparse::make_option(c("-N", "--sample-size"),
    type = "integer", default = NULL,
    help = "Sobol base sample size (overrides config)"
  ),
  optparse::make_option(c("-o", "--output"),
    default = "data/sobol_design_matrix.csv",
    help = "Output CSV path [default: %default]"
  ),
  optparse::make_option(c("-f", "--force"),
    action = "store_true", default = FALSE,
    help = "Overwrite existing output"
  )
)

args <- optparse::parse_args(optparse::OptionParser(option_list = opts))

cfg <- yaml::read_yaml(args$config)

settings_xml <- args$settings %||% cfg$default$settings_xml
if (is.null(settings_xml)) {
  PEcAn.logger::logger.severe(
    "Settings XML not specified. Set 'settings_xml' in ", args$config,
    " or pass --settings on the command line."
  )
}
if (!file.exists(settings_xml)) {
  PEcAn.logger::logger.severe("Settings XML not found: ", settings_xml)
}

settings <- PEcAn.settings::read.settings(settings_xml)

output_csv  <- args$output
output_meta <- sub("\\.csv$", "_metadata.rds", output_csv)

# skip-if-exists
if (!args$force && file.exists(output_csv) && file.exists(output_meta)) {
  PEcAn.logger::logger.info(
    "Outputs exist: ", output_csv, ". Use --force to regenerate. Skipping."
  )
  quit(save = "no", status = 0)
}

if (!dir.exists(dirname(output_csv))) {
  dir.create(dirname(output_csv), recursive = TRUE)
}

N <- args[["sample-size"]] %||% as.integer(cfg$sobol$N %||% 512L)

# derive IC and Met ranges from actual inputs in settings
# PEcAn stores per-site inputs; use the first site to discover ensemble counts.
first_site <- settings$run[[1]]
if (is.null(first_site)) {
  PEcAn.logger::logger.severe("No sites found in settings$run")
}

ic_paths <- first_site$inputs$poolinitcond$path
n_ic <- if (length(ic_paths) > 0) length(ic_paths) else {
  fallback <- as.integer(cfg$sobol$n_ic %||% 100L)
  PEcAn.logger::logger.warn(
    "No IC paths in settings; falling back to config n_ic = ", fallback
  )
  fallback
}

met_paths <- first_site$inputs$met$path
n_met <- if (length(met_paths) > 0) length(met_paths) else {
  fallback <- as.integer(cfg$sobol$n_met %||% 10L)
  PEcAn.logger::logger.warn(
    "No met paths in settings; falling back to config n_met = ", fallback
  )
  fallback
}



# identify active PFTs (cross-referenced against sites)
# only include PFTs that are actually assigned to at least one site.
site_pfts <- unique(unlist(
  purrr::map(settings$run, \(s) s$site$pft)
))

if (length(site_pfts) == 0) {
  PEcAn.logger::logger.severe("No PFTs found in site definitions (settings$run$site$pft)")
}

PEcAn.logger::logger.info(
  "Active site PFTs: ", paste(site_pfts, collapse = ", ")
)

# build parameter list from PFT posteriors
params <- list()
param_sources <- character(0)  # named vector: param_key -> PFT name

for (pft in settings$pfts) {
  pft_name <- pft$name

  # skip PFTs not assigned to any site
  if (!(pft_name %in% site_pfts)) {
    PEcAn.logger::logger.info("Skipping PFT '", pft_name, "' (not in any site)")
    next
  }

  posterior_file <- pft$posterior.files
  if (!file.exists(posterior_file)) {
    PEcAn.logger::logger.severe(
      "Posterior file not found for PFT '", pft_name, "': ", posterior_file
    )
  }

  env <- new.env(parent = emptyenv())
  load(posterior_file, envir = env)

  if (exists("post.distns", envir = env)) {
    distns_df <- env$post.distns
  } else if (exists("prior.distns", envir = env)) {
    distns_df <- env$prior.distns
    PEcAn.logger::logger.warn("Using prior (not posterior) for PFT '", pft_name, "'")
  } else {
    PEcAn.logger::logger.severe("No distributions found in ", posterior_file)
  }

  for (i in seq_len(nrow(distns_df))) {
    row <- distns_df[i, ]
    param_key <- paste0(pft_name, ".", rownames(distns_df)[i])

    entry <- list(
      distn = row$distn,
      parama = row$parama,
      paramb = row$paramb,
      pft = pft_name,
      original_name = rownames(distns_df)[i] # store raw name for reconstruction
    )
    # truncnorm uses paramc/paramd for bounds
    if ("paramc" %in% names(row) && !is.na(row$paramc)) entry$paramc <- row$paramc
    if ("paramd" %in% names(row) && !is.na(row$paramd)) entry$paramd <- row$paramd

    params[[param_key]] <- entry
    param_sources[[param_key]] <- pft_name
  }
}

PEcAn.logger::logger.info(
  "Loaded ", length(params), " PFT parameters from ",
  length(unique(param_sources)), " PFTs"
)

# management priors - quantile based approach for crop specific N rates
# Phase 3c : N fertilizer and NCC priors from agronomic literature.
# These do NOT require remote sensing data, rates come from published
# lookup tables (UC ANR Pub 3470), surveys (CDFA HSP), and lab standards
# (NRCS 808).
#
# design: sample Uniform[0,1] quantiles in the Sobol design. In
# 023_generate_management_events.R, each site maps the quantile to its
# OWN crop-specific N rate range (from look_up_ca_n_rate()).
#
# why quantiles? "the conservative thing to do is to draw it as the
# statewide mean." One quantile draw is shared across all farms of the
# same crop type, but each crop's min/max N range is different. This keeps
# the Sobol design standard (uniform inputs) while allowing per-site
# crop-specific mapping.

# N fertilizer quantile (mapped to crop-specific [min_n, max_n] in 023)
params[["mgmt.n_quantile"]] <- list(
  distn = "unif",
  parama = 0,
  paramb = 1,
  pft = "management",
  original_name = "n_quantile"
)
param_sources[["mgmt.n_quantile"]] <- "management"

# compost organic carbon quantile (mapped to amendment-specific range in 023)
params[["mgmt.compost_quantile"]] <- list(
  distn = "unif",
  parama = 0,
  paramb = 1,
  pft = "management",
  original_name = "compost_quantile"
)
param_sources[["mgmt.compost_quantile"]] <- "management"

# compost C:N ratio quantile (mapped to material-specific [cn_min, cn_max] in 023)
# uses PEcAn.data.land::look_up_ca_compost_amendment() via CDFA/NRCS dataset
params[["mgmt.cn_quantile"]] <- list(
  distn = "unif",
  parama = 0,
  paramb = 1,
  pft = "management",
  original_name = "cn_quantile"
)
param_sources[["mgmt.cn_quantile"]] <- "management"

PEcAn.logger::logger.info("Added 3 management parameters (N fert + compost + C:N quantiles)")

# build and save per-site crop mapping for downstream use by 023
source("R/crop_lookup.R")
crop_cfg <- cfg$default$crop_lookup
site_crop_info <- get_site_crop_info(
  design_points_csv = cfg$default$sites$design_points_file,
  landiq_parquet    = crop_cfg$landiq_parquet,
  pft_table_csv     = crop_cfg$pft_table_csv,
  crosswalk_csv     = crop_cfg$crosswalk_csv,
  year              = as.integer(crop_cfg$landiq_year),
  season            = as.integer(crop_cfg$landiq_season)
  # NB crop identity is assumed constant across simulation years --
  # this is a simplification for annual rotations.
  # TODO use per-year LandIQ when rotation data is available
)

site_crop_path <- file.path(dirname(output_csv), "site_crop_mapping.csv")
readr::write_csv(site_crop_info, site_crop_path)
PEcAn.logger::logger.info("Saved site-crop mapping: ", site_crop_path)

# TODO:
# add tillage priors when monitoring framework delivers
# NDTI-based tillage detection.

# add planting/harvest priors when monitoring framework
# delivers EVI2-based phenology dates

# add irrigation uncertainty when
# CIMIS/CHIRPS water balance pipeline is integrated.

# add NCC application probability when monitoring
# framework delivers empirically calibrated probability distributions

# dummy parameter (Sobol validation - Si should be ~= 0)
params[["dummy"]] <- list(
  distn = "unif",
  parama = 0, paramb = 1,
  pft = "dummy", original_name = "dummy"
)
param_sources[["dummy"]] <- "dummy"

# generate design
design <- generate_sobol_design(
  N = N,
  params = params,
  ic_size = n_ic,
  met_size = n_met
)

PEcAn.logger::logger.info(
  "Generated Sobol design: ", nrow(design), " rows x ", ncol(design), " cols"
)

readr::write_csv(design, output_csv)

metadata <- list(
  N = N,
  k = length(params),
  total_runs = nrow(design),
  param_names = names(params),
  param_sources = param_sources,
  management_params = c("mgmt.n_quantile", "mgmt.compost_quantile", "mgmt.cn_quantile"),
  site_pfts = site_pfts,
  n_pfts = length(unique(site_pfts)),
  pft_names = unique(param_sources[param_sources != "management" & param_sources != "dummy"]),
  ic_size = n_ic,
  met_size = n_met,
  params = params,
  settings_xml = settings_xml,
  timestamp = Sys.time()
)
saveRDS(metadata, output_meta)

PEcAn.logger::logger.info("Saved: ", output_csv, ", ", output_meta)