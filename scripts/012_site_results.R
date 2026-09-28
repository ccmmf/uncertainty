#!/usr/bin/env Rscript

# Read model output and decompose variance at every design point of the
# multisite run. Sites are independent here and reading the runs is the slow
# part (about 16 hours serially for 100 sites), so sites run in parallel.
# A site whose results are already written is skipped.

library(PEcAn.all)
library(PEcAn.logger)

options <- list(
  optparse::make_option(c("-s", "--settings"),
    default = "output/pecan.CONFIGS.xml",
    help = "settings written by 011_run_local_sensitivity.R"
  ),
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

# results are named by each site's ensemble id, so sites write into the shared
# output directory without colliding
is_done <- function(s) {
  sa <- s$sensitivity.analysis
  variables <- unlist(sa[names(sa) == "variable"])
  files <- file.path(s$outdir, sprintf("sensitivity.results.%s.%s.%s.%s.Rdata",
                                       sa$ensemble.id, variables, sa$start.year, sa$end.year))
  all(file.exists(files))
}
todo <- which(!vapply(seq_along(settings), function(i) is_done(settings[[i]]), logical(1)))
logger.info(length(settings) - length(todo), "of", length(settings), "sites already done")

# subset here: the MultiSettings method for `[` is not attached in the workers
sites <- lapply(todo, function(i) settings[i])
future::plan(future::multisession, workers = args$n_cores)
furrr::future_walk(sites, function(site) {
  PEcAn.uncertainty::runModule.get.results(site)
  PEcAn.uncertainty::runModule.run.sensitivity.analysis(site)
  PEcAn.logger::logger.info("done site", site[[1]]$run$site$id)
}, .options = furrr::furrr_options(seed = NULL))

logger.info("results written for", length(settings), "sites")
