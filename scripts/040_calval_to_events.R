#!/usr/bin/env Rscript
# 040_calval_to_events.R
#
# CLI entry point for the cal/val workbook -> events.json pipeline (MVP).
# Reads a curated cal/val .xlsx, takes the midpoint of uncertain dates,
# maps each managements row to a PEcAn v0.1.1 event, and writes one
# events.json per treatment. Required schema fields that the data does
# not yet provide (leaf_c_kg_m2, frac_above_removed_0to1,
# tillage_eff_0to1) are emitted as `null` and will be filled later by
# the prior-sampling stage.
#
# Usage:
#   Rscript scripts/040_calval_to_events.R \
#     --in data_raw/white_salinas_2020/White_Salinas_2020_filled.xlsx \
#     --out data/events/white_salinas_2020 \
#     --dataset white_salinas_2020 \
#     [--no-validate]

suppressPackageStartupMessages({
  library(readxl)
  library(jsonlite)
})

# Resolve project root (parent of scripts/) so the entry works whether
# launched from the repo root or the scripts/ directory.
file_arg <- grep("^--file=", commandArgs(trailingOnly = FALSE), value = TRUE)
project_root <- if (length(file_arg) > 0) {
  dirname(dirname(normalizePath(sub("^--file=", "", file_arg[1]))))
} else {
  getwd()
}

for (f in list.files(file.path(project_root, "R"), pattern = "\\.R$", full.names = TRUE)) {
  source(f)
}
# Vendored priors helpers from ccmmf/scenarios PR #3 (see inst/akash_priors/README.md).
source(file.path(project_root, "inst", "akash_priors", "sample_priors.R"))

# ---- Argument parsing (lightweight; avoids a dependency on optparse) -------
args <- commandArgs(trailingOnly = TRUE)
get_arg <- function(flag, default = NULL) {
  i <- match(flag, args)
  if (is.na(i) || i == length(args)) return(default)
  args[i + 1L]
}

input    <- get_arg("--in",      file.path(project_root, "data_raw", "white_salinas_2020",
                                           "White_Salinas_2020_filled.xlsx"))
out_dir  <- get_arg("--out",     file.path(project_root, "data", "events", "white_salinas_2020"))
dataset  <- get_arg("--dataset", "white_salinas_2020")
do_validate <- !("--no-validate" %in% args)
do_priors   <- !("--no-priors"   %in% args)

cat("calval -> events.json pipeline (MVP)\n")
cat("  input    : ", input, "\n", sep = "")
cat("  output   : ", out_dir, "\n", sep = "")
cat("  dataset  : ", dataset, "\n", sep = "")
cat("  validate : ", do_validate, "\n", sep = "")
cat("  priors   : ", do_priors, "\n", sep = "")

wb <- read_calval_workbook(input)
cat("\nLoaded ", nrow(wb$managements), " managements rows across ",
    length(unique(wb$managements$`treatments.name`)), " treatments.\n", sep = "")

priors <- if (do_priors) {
  load_priors(file.path(project_root, "inst", "akash_priors", "management_priors.yaml"))
} else NULL

written <- write_events_json(
  mgmt        = wb$managements,
  sites       = wb$sites,
  out_dir     = out_dir,
  dataset_id  = dataset,
  schema_path = file.path(project_root, "inst", "extdata", "events_schema_v0.1.1.json"),
  validate    = do_validate,
  priors      = priors
)

cat("\nWrote ", length(written), " events.json files:\n", sep = "")
for (f in written) cat("  - ", basename(f), "\n", sep = "")
