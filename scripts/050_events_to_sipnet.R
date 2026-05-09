#!/usr/bin/env Rscript
# 050_events_to_sipnet.R
#
# Convert events.json files produced by 040_calval_to_events.R into SIPNET
# events.in files using PEcAn's write.events.SIPNET(), then patch the
# settings.xml produced by `magic-ensemble prepare` to wire in the events
# ensemble paths.
#
# Requires the PEcAn model.SIPNET package (loaded via pecan-all conda env).
#
# Usage:
#   Rscript scripts/050_events_to_sipnet.R \
#     --events  data/events/white_salinas_2020 \
#     --out     data/sipnet_events \
#     --xml     /path/to/magic-ensemble/prepare/settings.xml \
#     [--n-ens  20]
#
# The script writes one events-<site_id>.in per site_id found across all
# events.json files in --events, then patches --xml in-place to add
# <inputs><events> ensemble paths.

suppressPackageStartupMessages({
  library(jsonlite)
  library(xml2)
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

# Collect unique site_ids across all events.json files, then write one
# events-<site_id>.in per site using PEcAn's writer.
all_site_ids <- character(0)
for (jf in json_files) {
  x <- jsonlite::fromJSON(jf, simplifyVector = FALSE)
  site_objs <- if (!is.null(x$site_id)) list(x) else x
  for (s in site_objs) {
    sid <- s$site_id
    if (!sid %in% all_site_ids) {
      all_site_ids <- c(all_site_ids, sid)
      written <- PEcAn.model.SIPNET::write.events.SIPNET(jf, out_dir)
      cat("  wrote: ", basename(written), "\n", sep = "")
    }
  }
}

cat("\nDone writing", length(all_site_ids), "events.in file(s).\n")

# Optionally patch settings.xml to add events ensemble paths
if (!is.null(xml_path)) {
  if (!file.exists(xml_path)) stop("settings.xml not found: ", xml_path)
  doc <- xml2::read_xml(xml_path)

  inputs_node <- xml2::xml_find_first(doc, "//run/inputs")
  if (is.na(inputs_node)) stop("Could not find //run/inputs in settings.xml")

  # Remove any existing events block to avoid duplicates on re-run
  existing <- xml2::xml_find_all(doc, "//run/inputs/events")
  xml2::xml_remove(existing)

  events_node <- xml2::xml_add_child(inputs_node, "events")
  for (n in seq_len(n_ens)) {
    # One path per ensemble member — each member gets the same events.in
    # (management is deterministic; uncertainty comes from IC and met).
    # site_id is taken from the first site found; multi-site XMLs would
    # need one events block per site (handled by magic-ensemble xml_build).
    sid <- all_site_ids[1]
    path_n <- xml2::xml_add_child(events_node, paste0("path", n))
    xml2::xml_text(path_n) <- file.path(out_dir, sprintf("events-%s.in", sid))
  }

  xml2::write_xml(doc, xml_path)
  cat("\nPatched settings.xml at: ", xml_path, "\n", sep = "")
  cat("Added", n_ens, "events ensemble paths for site:", all_site_ids[1], "\n")
}
