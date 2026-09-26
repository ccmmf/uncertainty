#!/usr/bin/env Rscript

# Build the multisite PEcAn settings for the statewide OAT sensitivity analysis.
# Met, initial conditions and events come from the production ensemble's own
# input tree, so the decomposition describes the runs CARB is getting.

library(PEcAn.settings)
library(PEcAn.logger)

source("000-config.R")

options <- list(
  optparse::make_option("--site_file",
    default = "data_raw/statewide_sites.csv",
    help = "CSV of sites: id, lat, lon, site.pft, ERA5_grid_cell"
  ),
  optparse::make_option("--template_file",
    default = "data_raw/template.xml",
    help = "XML file containing whole-run settings"
  ),
  optparse::make_option("--output_file",
    default = "data_raw/settings_sa.xml",
    help = "path to write output XML"
  ),
  optparse::make_option("--output_dir",
    default = file.path(run_dir, "output"),
    help = "path the settings should declare as output directory"
  ),
  optparse::make_option("--met_dir",
    default = file.path(input_dir, "data", "ERA5_SIPNET"),
    help = "directory of ERA5 .clim files, one subdirectory per grid cell"
  ),
  optparse::make_option("--ic_dir",
    default = file.path(input_dir, "IC_files"),
    help = "directory of initial condition netCDFs, one subdirectory per site"
  ),
  optparse::make_option("--event_dir",
    default = file.path(input_dir, "data", "events"),
    help = "directory of management files, one subdirectory per ensemble member"
  ),
  optparse::make_option("--pft_dir",
    default = file.path(input_dir, "data_raw", "pfts"),
    help = "directory of PFT posteriors, one subdirectory per PFT"
  ),
  optparse::make_option("--binary",
    default = sipnet_binary,
    help = "SIPNET executable"
  ),
  optparse::make_option("--n_ens", default = 20, help = "ensemble members"),
  optparse::make_option("--n_met", default = 10, help = "met replicates"),
  optparse::make_option("--n_ic", default = 20, help = "IC replicates"),
  optparse::make_option("--n_event", default = 20, help = "event replicates"),
  optparse::make_option("--start_date", default = "2016-01-01"),
  optparse::make_option("--end_date", default = "2023-12-31")
) |>
  purrr::modify(\(x) {
    x@help <- paste(x@help, "[default: %default]")
    x
  })

args <- optparse::OptionParser(option_list = options) |>
  optparse::parse_args()

# papply emits a lot of uninformative debug messages; let's ignore those
PEcAn.logger::logger.setLevel("INFO")

site_info <- utils::read.csv(args$site_file)
stopifnot(
  length(unique(site_info$id)) == nrow(site_info),
  all(c("lat", "lon", "site.pft", "ERA5_grid_cell") %in% names(site_info))
)

# The restart code changes working directory and gets confused by relative
# paths, and dirs that don't exist yet need the getwd() because normalizePath
# only expands existing ones.
abs_path <- function(path) {
  if (substr(path, 1, 1) != "/") path <- file.path(getwd(), path)
  normalizePath(path, mustWork = FALSE)
}
args$met_dir <- abs_path(args$met_dir)
args$ic_dir <- abs_path(args$ic_dir)
args$event_dir <- abs_path(args$event_dir)
args$output_dir <- abs_path(args$output_dir)

settings <- read.settings(args$template_file) |>
  setDates(args$start_date, args$end_date)

settings$model$binary <- abs_path(args$binary)
settings$ensemble$size <- args$n_ens
settings$run$inputs$poolinitcond$ensemble <- args$n_ens

# setEnsemblePaths leaves every path component except the site id identical
# across sites, so the met grid cell is patched in afterwards.
id2grid <- function(s) {
  for (p in seq_along(s$run$inputs$met$path)) {
    s$run$inputs$met$path[[p]] <- gsub(
      pattern = s$run$site$id,
      replacement = s$run$site$ERA5_grid_cell,
      x = s$run$inputs$met$path[[p]]
    )
  }
  s
}

# write.sa.configs subsets the quantile samples to the PFTs named here, so this
# is what keeps a vineyard site from being perturbed through corn's traits.
# An uncropped site is already assigned "soil" as its vegetation, and naming it
# twice would perturb every soil trait twice.
add_soil_pft <- function(s) {
  veg <- s$run$site$site.pft
  s$run$site$site.pft <- if (veg == "soil") {
    list(soil = "soil")
  } else {
    list(veg = veg, soil = "soil")
  }
  s
}

settings <- settings |>
  createMultiSiteSettings(site_info) |>
  setEnsemblePaths(
    n_reps = args$n_met,
    input_type = "met",
    path = args$met_dir,
    d1 = args$start_date,
    d2 = args$end_date,
    path_template = "{path}/{id}/ERA5.{n}.{d1}.{d2}.clim"
  ) |>
  papply(id2grid) |>
  setEnsemblePaths(
    n_reps = args$n_ic,
    input_type = "poolinitcond",
    path = args$ic_dir,
    path_template = "{path}/{id}/IC_site_{id}_{n}.nc"
  ) |>
  setEnsemblePaths(
    n_reps = sprintf("%03d", seq_len(args$n_event)),
    input_type = "events",
    path = args$event_dir,
    path_template = "{path}/ens_{n}/events-{id}.in"
  ) |>
  papply(add_soil_pft)

settings$outdir <- args$output_dir
settings$modeloutdir <- file.path(args$output_dir, "out")
settings$rundir <- file.path(args$output_dir, "run")
settings$host$outdir <- file.path(args$output_dir, "out")
settings$host$rundir <- file.path(args$output_dir, "run")

# Every subdirectory of pft_dir becomes a PFT, named for the directory, and
# each site's own PFTs are selected from this list by site.pft above.
build_pft_entry <- function(name) {
  posterior <- file.path(args$pft_dir, name, "post.distns.Rdata")
  if (!file.exists(posterior)) {
    PEcAn.logger::logger.severe("No posterior for pft", sQuote(name))
  }
  list(name = name, posterior.files = posterior)
}
pft_names <- list.dirs(args$pft_dir, full.names = FALSE, recursive = FALSE)
settings$pfts <- lapply(pft_names, build_pft_entry) |>
  setNames(nm = rep("pft", length(pft_names)))

write.settings(
  settings,
  outputfile = basename(args$output_file),
  outputdir = dirname(args$output_file)
)

logger.info("Wrote", args$output_file, "with", length(settings), "sites and",
            length(pft_names), "pfts")
