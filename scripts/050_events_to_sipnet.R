#!/usr/bin/env Rscript
# 050_events_to_sipnet.R
#
# Convert events.json files produced by 040_calval_to_events.R into SIPNET
# events.in files via PEcAn.SIPNET::write.events.sipnet(), then optionally
# patch the settings.xml produced by `magic-ensemble prepare` to wire in
# the events ensemble paths.
#
# Usage:
#   Rscript scripts/050_events_to_sipnet.R \
#     --events  data/events/white_salinas_2020 \
#     --out     data/sipnet_events \
#     --xml     /path/to/magic-ensemble/prepare/settings.xml \
#     [--n-ens  20]

suppressPackageStartupMessages({
  library(jsonlite)
  library(xml2)
  library(PEcAn.SIPNET)
})

file_arg <- grep("^--file=", commandArgs(trailingOnly = FALSE), value = TRUE)
project_root <- if (length(file_arg) > 0) {
  dirname(dirname(normalizePath(sub("^--file=", "", file_arg[1]))))
} else {
  getwd()
}

args <- commandArgs(trailingOnly = TRUE)
get_arg <- function(flag, default = NULL) {
  i <- match(flag, args)
  if (is.na(i) || i == length(args)) return(default)
  args[i + 1L]
}

events_dir <- get_arg("--events", file.path(project_root, "data", "events", "white_salinas_2020"))
out_dir    <- get_arg("--out",    file.path(project_root, "data", "sipnet_events"))
xml_path   <- get_arg("--xml",    NULL)
n_ens      <- as.integer(get_arg("--n-ens", "20"))

cat("events.json -> events.in converter\n")
cat("  events dir : ", events_dir, "\n", sep = "")
cat("  output dir : ", out_dir, "\n", sep = "")
cat("  settings   : ", if (is.null(xml_path)) "(none)" else xml_path, "\n", sep = "")
cat("  n_ens      : ", n_ens, "\n\n", sep = "")

json_files <- list.files(events_dir, pattern = "\\.json$", full.names = TRUE)
if (length(json_files) == 0) stop("No .json files found in: ", events_dir)

dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)

all_site_ids <- character(0)
for (jf in json_files) {
  x <- jsonlite::fromJSON(jf, simplifyVector = FALSE)
  site_objs <- if (!is.null(x$site_id)) list(x) else x
  for (s in site_objs) {
    sid <- s$site_id
    if (!sid %in% all_site_ids) {
      all_site_ids <- c(all_site_ids, sid)
      written <- PEcAn.SIPNET::write.events.SIPNET(jf, out_dir)
      cat("  wrote: ", basename(written), "\n", sep = "")
    }
  }
}

cat("\nDone writing", length(all_site_ids), "events.in file(s).\n")

if (!is.null(xml_path)) {
  if (!file.exists(xml_path)) stop("settings.xml not found: ", xml_path)
   settings <- PEcAn.settings::read.settings(xml_path)
   settings <- PEcAn.settings::setEnsemblePaths(
    settings,
    n_reps = n_ens,
    input_type = "events",
    path = out_dir,
    path_template = "{path}/events-{id}-{n}.in"
  )
  PEcAn.settings::write.settings(
    settings,
    outputfile = basename(xml_path),
    outputdir = dirname(xml_path)
  )
}
