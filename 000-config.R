# System specific paths, set once here and sourced by every script, so moving to
# another machine means setting CCMMF_DIR and nothing else.

ccmmf_dir <- Sys.getenv("CCMMF_DIR", "/projectnb/dietzelab/ccmmf")
if (!dir.exists(ccmmf_dir)) {
  PEcAn.logger::logger.severe("CCMMF_DIR", ccmmf_dir, "does not exist")
}

# inputs of the statewide production ensemble: met, initial conditions, events, priors
input_dir <- file.path(ccmmf_dir, "modelout", "production-final")

# where this analysis runs SIPNET and writes its results
run_dir <- file.path(ccmmf_dir, "usr", "akash", "statewide_oat_sa")

sipnet_binary <- file.path(ccmmf_dir, "usr", "akash", "calval_sa_v3_20260821",
                           "tools", "sipnet_v2.2.0-3ccc41c")

climregions_file <- file.path(ccmmf_dir, "data", "caladapt_climregions.gpkg")
