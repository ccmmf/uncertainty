#!/usr/bin/env Rscript

# Read model output and decompose variance for one site of the multisite run.
# Sites are independent at this stage and reading 15k runs serially takes about
# 16 hours, so this runs as an SGE array with one task per site.

library(PEcAn.all)
library(PEcAn.logger)

source("000-config.R")

options <- list(
  optparse::make_option(c("-s", "--settings"),
    default = file.path(run_dir, "output", "pecan.CONFIGS.xml"),
    help = "settings written by the config stage"
  ),
  optparse::make_option(c("-i", "--site_index"),
    default = as.integer(Sys.getenv("SGE_TASK_ID", "1")),
    help = "which site to process, defaults to the array task id"
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
if (args$site_index > length(settings)) {
  logger.severe("site_index ", args$site_index, " exceeds ", length(settings),
                " sites")
}

# subset to one site. results are named by that site's ensemble id, so tasks
# write into the shared output directory without colliding.
site <- settings[args$site_index]
logger.info("site", site[[1]]$run$site$id, "(", args$site_index, "of",
            length(settings), ")")

runModule.get.results(site)
runModule.run.sensitivity.analysis(site)

logger.info("done site", site[[1]]$run$site$id)
