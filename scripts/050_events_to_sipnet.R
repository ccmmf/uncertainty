#!/usr/bin/env Rscript
# 050_events_to_sipnet.R
#
# Convert events.json files produced by 040_calval_to_events.R into SIPNET
# events.in files, then optionally patch the settings.xml produced by
# `magic-ensemble prepare` to wire in the events ensemble paths.
#
# write_events_sipnet() is vendored inline from PEcAn models/sipnet so this
# script runs without needing PEcAn.model.SIPNET installed.
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
})

# ---- Vendored from PEcAn models/sipnet/R/write.events.SIPNET.R -------------
# Source: https://github.com/PecanProject/pecan/blob/develop/models/sipnet/R/write.events.SIPNET.R
write_events_sipnet <- function(events_json, outdir) {
  kg2g  <- 1000
  mm2cm <- 0.1
  leafAllocation       <- 0.50
  woodAllocation       <- 0.15
  fineRootAllocation   <- 0.10
  coarseRootAllocation <- 0.25

  x <- jsonlite::fromJSON(events_json, simplifyVector = FALSE)
  site_objs <- if (!is.null(x$site_id)) list(x) else x
  files_written <- character(0)

  for (site in site_objs) {
    sid <- site$site_id
    evs <- site$events
    dates <- as.Date(vapply(evs, function(e) as.character(e$date), character(1)))
    years <- as.integer(format(dates, "%Y"))
    days  <- as.integer(format(dates, "%j"))
    ord   <- order(dates)
    evs_sorted   <- evs[ord]
    days_sorted  <- days[ord]
    years_sorted <- years[ord]
    lines <- character(length(evs))

    for (i in seq_along(evs_sorted)) {
      e    <- evs_sorted[[i]]
      year <- years_sorted[[i]]
      day  <- days_sorted[[i]]
      type <- e$event_type

      if (type == "tillage") {
        f <- if (is.null(e$tillage_eff_0to1)) 0 else e$tillage_eff_0to1
        lines[i] <- sprintf("%d  %d  till  %s", year, day, f)
      } else if (type == "planting") {
        leaf_g  <- as.numeric(if (is.null(e$leaf_c_kg_m2)) 0 else e$leaf_c_kg_m2) * kg2g
        total_g <- if (leafAllocation > 0) leaf_g / leafAllocation else leaf_g
        wood_g  <- woodAllocation * total_g
        fr_g    <- fineRootAllocation * total_g
        cr_g    <- coarseRootAllocation * total_g
        lines[i] <- sprintf("%d  %d  plant  %s %s %s %s", year, day, leaf_g, wood_g, fr_g, cr_g)
      } else if (type == "fertilization") {
        orgN_g <- as.numeric(if (is.null(e$org_n_kg_m2))  0 else e$org_n_kg_m2)  * kg2g
        orgC_g <- as.numeric(if (is.null(e$org_c_kg_m2))  0 else e$org_c_kg_m2)  * kg2g
        nh4_g  <- as.numeric(if (is.null(e$nh4_n_kg_m2))  0 else e$nh4_n_kg_m2)  * kg2g
        no3_g  <- as.numeric(if (is.null(e$no3_n_kg_m2))  0 else e$no3_n_kg_m2)  * kg2g
        minN_g <- nh4_g + no3_g
        lines[i] <- sprintf("%d  %d  fert   %s %s %s", year, day, orgN_g, orgC_g, minN_g)
      } else if (type == "irrigation") {
        amt_cm      <- as.numeric(if (is.null(e$amount_mm)) 0 else e$amount_mm) * mm2cm
        method_code <- if (is.null(e$method) || e$method == "soil") 1 else 0
        lines[i] <- sprintf("%d  %d  irrig  %s %s", year, day, amt_cm, method_code)
      } else if (type == "harvest") {
        abv_rem <- if (is.null(e$frac_above_removed_0to1)) 0 else e$frac_above_removed_0to1
        blw_rem <- if (is.null(e$frac_below_removed_0to1)) 0 else e$frac_below_removed_0to1
        abv_lit <- if (is.null(e$frac_above_to_litter_0to1)) 1 - abv_rem else e$frac_above_to_litter_0to1
        blw_lit <- if (is.null(e$frac_below_to_litter_0to1)) 1 - blw_rem else e$frac_below_to_litter_0to1
        lines[i] <- sprintf("%d  %d  harv   %s %s %s %s", year, day, abv_rem, blw_rem, abv_lit, blw_lit)
      }
    }

    dir.create(outdir, showWarnings = FALSE, recursive = TRUE)
    fp <- file.path(outdir, sprintf("events-%s.in", sid))
    writeLines(lines, fp)
    files_written <- c(files_written, fp)
  }
  invisible(files_written)
}
# ---- End vendored code -------------------------------------------------------

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
      written <- write_events_sipnet(jf, out_dir)
      cat("  wrote: ", basename(written), "\n", sep = "")
    }
  }
}

cat("\nDone writing", length(all_site_ids), "events.in file(s).\n")

if (!is.null(xml_path)) {
  if (!file.exists(xml_path)) stop("settings.xml not found: ", xml_path)
  doc <- xml2::read_xml(xml_path)

  inputs_node <- xml2::xml_find_first(doc, "//run/inputs")
  if (is.na(inputs_node)) stop("Could not find //run/inputs in settings.xml")

  existing <- xml2::xml_find_all(doc, "//run/inputs/events")
  xml2::xml_remove(existing)

  events_node <- xml2::xml_add_child(inputs_node, "events")
  for (n in seq_len(n_ens)) {
    sid   <- all_site_ids[1]
    path_n <- xml2::xml_add_child(events_node, paste0("path", n))
    xml2::xml_text(path_n) <- file.path(out_dir, sprintf("events-%s.in", sid))
  }

  xml2::write_xml(doc, xml_path)
  cat("\nPatched settings.xml at: ", xml_path, "\n", sep = "")
  cat("Added", n_ens, "events ensemble paths for site:", all_site_ids[1], "\n")
}
