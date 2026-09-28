#!/usr/bin/env Rscript

# Read the model output at every design point and compute its Sobol indices with
# bootstrap intervals. Sites are independent here and reading the runs is the
# slow part (1 to 2 hours per site), so sites run in parallel. A site whose
# indices are already written is skipped.

library(PEcAn.all)
library(PEcAn.logger)

options <- list(
  optparse::make_option(c("-s", "--settings"),
    default = "output/pecan.CONFIGS.xml",
    help = "settings written by 021_run_global_sensitivity.R"
  ),
  optparse::make_option(c("-d", "--sobol_dir"),
    default = "output/sobol",
    help = "directory for the per-site index files"
  ),
  optparse::make_option("--nboot", default = 1000L, help = "bootstrap replicates"),
  optparse::make_option("--seed", default = 1L, help = "seed for the bootstrap"),
  optparse::make_option("--n_cores",
    default = 1L,
    help = "sites processed in parallel"
  )
) |>
  purrr::modify(\(x) {
    x@help <- paste(x@help, "[default: %default]")
    x
  })

args <- optparse::OptionParser(option_list = options) |>
  optparse::parse_args()

options(warn = 1)

settings <- PEcAn.settings::read.settings(args$settings)
sobol_obj <- readRDS(file.path(settings$outdir, "sobol_design.rds"))
dir.create(args$sobol_dir, recursive = TRUE, showWarnings = FALSE)

site_indices <- function(site) {
  s <- site[[1]]
  out_file <- file.path(args$sobol_dir, paste0(s$run$site$id, ".csv"))
  if (file.exists(out_file)) return(invisible())

  variables <- unlist(s$ensemble[names(s$ensemble) == "variable"])
  output_files <- purrr::map_chr(variables, function(v) {
    PEcAn.uncertainty::ensemble.filename(s, "ensemble.output", "Rdata",
                                         all.var.yr = FALSE, variable = v,
                                         start.year = s$ensemble$start.year,
                                         end.year = s$ensemble$end.year)
  }) |>
    stats::setNames(variables)
  # reading the runs takes hours, so it is skipped when every variable was already read
  if (!all(file.exists(output_files))) PEcAn.uncertainty::runModule.get.results(site)

  # the same seed at every site, so a site's intervals do not depend on which
  # other sites run or in what order
  set.seed(args$seed)
  indices <- purrr::map(variables, function(v) {
    y <- unlist(PEcAn.utils::load_local(output_files[[v]])$ensemble.output, use.names = FALSE)
    # an output that is the same in every run has no variance to split
    if (length(unique(y)) == 1) {
      PEcAn.logger::logger.warn(v, "is constant at site", s$run$site$id, "; no indices")
      return(NULL)
    }
    told <- PEcAn.uncertainty::compute_sobol_indices(s, sobol_obj, v, nboot = args$nboot)
    purrr::map(c(first_order = "S", total_order = "T"), function(k) {
      tibble::tibble(site_id = s$run$site$id, variable = v, factor = rownames(told[[k]]),
                     estimate = told[[k]][, "original"], std_error = told[[k]][, "std. error"],
                     lower = told[[k]][, "min. c.i."], upper = told[[k]][, "max. c.i."])
    }) |>
      purrr::list_rbind(names_to = "index")
  }) |>
    purrr::list_rbind()

  utils::write.csv(indices, out_file, row.names = FALSE)
  PEcAn.logger::logger.info("wrote", out_file)
}

# subset here: the MultiSettings method for `[` is not attached in the workers
sites <- lapply(seq_along(settings), function(i) settings[i])
future::plan(future::multisession, workers = args$n_cores)
furrr::future_walk(sites, site_indices,
                   .options = furrr::furrr_options(seed = NULL))

logger.info("indices written for", length(settings), "sites")
