# Package repositories
options(repos = c(
  PEcAn = "https://pecanproject.r-universe.dev",
  CRAN  = "https://cloud.r-project.org"
))

# Activate renv
if (file.exists("renv/activate.R")) {
  source("renv/activate.R")
}

# Graphics backend for headless HPC nodes
options(bitmapType = "cairo")

if (interactive()) {
  # httpgd for VS Code remote sessions

  if (requireNamespace("httpgd", quietly = TRUE)) {
    options(device = function(...) httpgd::hgd(silent = TRUE, ...))
  }
  
  # Validate environment on startup
  ccmmf <- Sys.getenv("CCMMF_DIR")
  if (!nzchar(ccmmf)) {
    message("CCMMF_DIR not set. Copy .Renviron.example and edit paths.")
  } else if (!dir.exists(ccmmf)) {
    message("CCMMF_DIR (", ccmmf, ") not found. Check path in .Renviron")
  }
}

# Sensible defaults
options(
  readr.show_col_types = FALSE,
  tibble.width = Inf,
  warn = 1
)