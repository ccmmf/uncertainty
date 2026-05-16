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

# Priors helpers live in the sibling ccmmf/scenarios checkout (PR #3,
# branch `management_prac`). Until scenarios is released as a proper R
# package, we source the files directly via relative path. Override the
# location with the SCENARIOS_DIR environment variable if your sibling
# checkout lives elsewhere.
scenarios_dir <- Sys.getenv("SCENARIOS_DIR",
                            unset = normalizePath(
                              file.path(project_root, "..", "scenarios"),
                              mustWork = FALSE))
if (!dir.exists(scenarios_dir)) {
  stop("ccmmf/scenarios sibling checkout not found at: ", scenarios_dir,
       "\n  Clone it next to this repo:",
       "\n    git clone -b management_prac https://github.com/ccmmf/scenarios.git ",
       dirname(scenarios_dir),
       "\n  Or set SCENARIOS_DIR to point at an existing checkout.")
}
source(file.path(scenarios_dir, "R", "sample_priors.R"))

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
  load_priors(file.path(scenarios_dir, "data", "management_priors.yaml"))
} else NULL

written <- write_events_json(
  mgmt       = wb$managements,
  sites      = wb$sites,
  out_dir    = out_dir,
  dataset_id = dataset,
  validate   = do_validate,
  priors     = priors
)

cat("\nWrote ", length(written), " events.json files:\n", sep = "")
for (f in written) cat("  - ", basename(f), "\n", sep = "")
