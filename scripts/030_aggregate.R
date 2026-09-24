#!/usr/bin/env Rscript

# collect the per block variance decompositions into one table for the figures.
#
#   Rscript scripts/030_aggregate.R [-c examples/calval/config.yml]

suppressMessages(library(PEcAn.logger))
source("R/data_root.R")
source("R/aggregate_sa.R")

args <- optparse::parse_args(optparse::OptionParser(option_list = list(
  optparse::make_option(c("-c", "--config"), default = "examples/calval/config.yml",
    help = "project config [default: %default]")
)))
config <- config::get(file = args$config)

sites <- utils::read.csv(config$sites, stringsAsFactors = FALSE)
tab <- aggregate_sa(data_root(config$workspace, "output", "blocks"), sites)

dir.create("data", showWarnings = FALSE)
out <- file.path("data", "calval_sa_table.csv")
utils::write.csv(tab, out, row.names = FALSE)
logger.info("wrote ", out, ": ", nrow(tab), " rows, ",
            length(unique(tab$id)), " blocks, ",
            length(unique(tab$variable)), " variables")
