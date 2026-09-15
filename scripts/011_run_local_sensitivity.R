#!/usr/bin/env Rscript

# =======================================================================
# 011_run_local_sensitivity.R
# Run PEcAn sensitivity analysis workflow for 10 SA design points
# =======================================================================

library(PEcAn.all)
library(PEcAn.logger)

PEcAn.logger::logger.info("*** Starting 011_run_local_sensitivity.R ***")

# -----------------------------------------------------------------------
# Runtime parameters
# -----------------------------------------------------------------------
options <- list(
  optparse::make_option(c("-s", "--settings"),
    default = "data_raw/settings_sa.xml",
    help = "Path to multisite SA settings XML [default: %default]"
  ),
  optparse::make_option(c("-c", "--continue"),
    default = FALSE,
    help = "Resume interrupted workflow? [default: %default]"
  )
) |>
  purrr::modify(\(x) {
    x@help <- paste(x@help, "[default: %default]")
    x
  })

args <- optparse::OptionParser(option_list = options) |>
  optparse::parse_args()

# -----------------------------------------------------------------------
# Error handling
# -----------------------------------------------------------------------
options(warn = 1)
options(error = quote({
  try(PEcAn.utils::status.end("ERROR"))
  try(PEcAn.remote::kill.tunnel(settings))
  if (!interactive()) {
    q(status = 1)
  }
}))

# -----------------------------------------------------------------------
# PEcAn Workflow
# -----------------------------------------------------------------------

PEcAn.all::pecan_version()

# Read and prepare settings
settings <- PEcAn.settings::read.settings(args$settings)
# settings <- PEcAn.settings::prepare.settings(settings) # still db free settings not supported

if (!dir.exists(settings$outdir)) {
  dir.create(settings$outdir, recursive = TRUE)
}

# Handle workflow resumption
status_file <- file.path(settings$outdir, "STATUS")
if (!args$continue && file.exists(status_file)) {
  file.remove(status_file)
}

# -----------------------------------------------------------------------
# Step 1: Write model configs
# -----------------------------------------------------------------------
if (PEcAn.utils::status.check("CONFIG") == 0) {
  PEcAn.utils::status.start("CONFIG")
  settings <- runModule.run.write.configs(settings)
  PEcAn.settings::write.settings(settings, outputfile = "pecan.CONFIGS.xml")
  PEcAn.utils::status.end()
} else if (file.exists(file.path(settings$outdir, "pecan.CONFIGS.xml"))) {
  settings <- PEcAn.settings::read.settings(
    file.path(settings$outdir, "pecan.CONFIGS.xml")
  )
}

# -----------------------------------------------------------------------
# Step 2: Run SIPNET models
# -----------------------------------------------------------------------
if (PEcAn.utils::status.check("MODEL") == 0) {
  PEcAn.utils::status.start("MODEL")
  
  # Determine stop_on_error behavior
  stop_on_error <- as.logical(settings[[c("run", "stop_on_error")]])
  if (length(stop_on_error) == 0) {
    # For SA runs, don't stop on single failures
    stop_on_error <- FALSE
  }
  
  PEcAn.workflow::runModule_start_model_runs(settings,
                                             stop.on.error = stop_on_error)
  PEcAn.utils::status.end()
}

# -----------------------------------------------------------------------
# Step 3: Extract model outputs
# -----------------------------------------------------------------------
if (PEcAn.utils::status.check("OUTPUT") == 0) {
  PEcAn.utils::status.start("OUTPUT")
  runModule.get.results(settings)
  PEcAn.utils::status.end()
}

# -----------------------------------------------------------------------
# Step 4: Sensitivity analysis
# -----------------------------------------------------------------------
if ("sensitivity.analysis" %in% names(settings) &&
    PEcAn.utils::status.check("SENSITIVITY") == 0) {
  PEcAn.utils::status.start("SENSITIVITY")
  runModule.run.sensitivity.analysis(settings)
  PEcAn.utils::status.end()
}

# -----------------------------------------------------------------------
# Workflow complete
# -----------------------------------------------------------------------
if (PEcAn.utils::status.check("FINISHED") == 0) {
  PEcAn.utils::status.start("FINISHED")
  PEcAn.remote::kill.tunnel(settings)
  PEcAn.utils::status.end()
}

PEcAn.logger::logger.info("*** Finished 011_run_local_sensitivity.R ***")
print("---------- PEcAn Sensitivity Analysis Complete ----------")