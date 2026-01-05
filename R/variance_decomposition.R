# ======================================================================
# R/variance_decomposition.R
#
# Uncertainty Partitioning (Variance Decomposition) using:
#  - Global Sobol indices
#  - Ensemble variance from global runs
#  - Local OAT partial variances
#
# NOTE: This file does NOT handle residual/process/observation error yet.
#       That will be added once validation-based error estimates are
#       available (calculate_residual_variance()).
# ======================================================================


#' Calculate Total Variance of Ensemble Outputs
#'
#' Reads the raw PEcAn ensemble output files (Rdata) and calculates the 
#' scalar variance of the output variable Y for each runid.
#' 
#' Uses the PEcAn settings object to map 'runid' (Ensemble ID) to 'site_id'
#' by parsing the <ensemble> block in the XML.
#'
#' @param output_dir Path to the 'output' directory containing ensemble.output.*.Rdata
#' @param run_ids Vector of run IDs (from sobol_indices or filenames)
#' @param settings PEcAn settings object (read from pecan.CONFIGS.xml). Required to map runid -> site_id.
#' @return Tibble with columns: runid, site_id, variable, ensemble_variance
#' @export
calculate_ensemble_variance <- function(output_dir, run_ids, settings) {

  # 1. Build runid -> siteid map from settings$ensemble

  # The XML structure has sites nested under 'ensemble' like:
  # <ensemble>
  #   <site.SITEID>
  #     <ensemble.id>RUNID</ensemble.id>
  #   </site.SITEID>
  # </ensemble>
  
  # filter the ensemble list for elements starting with "site."
  site_keys <- grep("^site\\.", names(settings$ensemble), value = TRUE)
  
  workflow_site_map <- purrr::map_dfr(site_keys, function(key) {
    # extract site ID (remove "site." prefix)
    site_id <- sub("^site\\.", "", key)
    
    # extract ensemble ID (runid)
    run_id <- settings$ensemble[[key]]$ensemble.id
    
    if (is.null(run_id)) return(NULL)
    
    data.frame(
      site_id = site_id,
      runid = as.character(run_id),
      stringsAsFactors = FALSE
    )
  })
  
  if (nrow(workflow_site_map) == 0) {
    PEcAn.logger::logger.warn("Could not parse Site IDs from settings$ensemble. 'site_id' will be NA.")
  }


  # 2. process files
  results <- list()
  target_run_ids <- as.character(run_ids)
  
  for(rid in target_run_ids) {
    # pattern to find the file -> ensemble.output.<runid>.<variable>.*.Rdata
    pattern <- paste0("ensemble\\.output\\.", rid, "\\..*\\.Rdata$")
    files <- list.files(output_dir, pattern = pattern, full.names = TRUE)
    
    if(length(files) == 0) {
      PEcAn.logger::logger.warn(sprintf("No output found for Run ID %s", rid))
      next
    }
    
    # lookup site_id for this run_id using our new map
    curr_site_id <- workflow_site_map$site_id[workflow_site_map$runid == rid]
    
    # check if map lookup failed
    if(length(curr_site_id) == 0) {
      PEcAn.logger::logger.warn(sprintf("Run ID %s not found in settings$ensemble map.", rid))
      curr_site_id <- NA
    }
    
    for(f in files) {
      # load 'ensemble.output' list
      env <- new.env()
      load(f, envir = env)
      
      # extract variable name from filename (usually 4th token)
      # ex: ensemble.output.fd8e8...NPP.2016.2023.Rdata
      parts <- strsplit(basename(f), "\\.")[[1]]
      var_name <- parts[4] 
      
      if(exists("ensemble.output", envir = env)) {
        # calculate variance of Y
        Y <- unlist(env$ensemble.output)
        
        # calculate scalar variance (Total modeled variance)
        var_y <- var(Y, na.rm = TRUE)
        
        results[[length(results) + 1]] <- tibble::tibble(
          runid = rid,
          site_id = curr_site_id, 
          variable = var_name,
          ensemble_variance = var_y
        )
      }
    }
  }
  
  if(length(results) == 0) return(NULL)
  dplyr::bind_rows(results)
}


#' Build parameter category lookup from Sobol metadata
#'
#' Uses sobol_design_metadata.rds to map each parameter into a category:
#'  - "parameter": all PFT parameters
#'  - "IC":        initial conditions (ic_ensemble)
#'  - "driver":    meteorological drivers (met_ensemble)
#'  - "dummy":     dummy parameter used for numerical baseline
#'
#' @param sobol_metadata List read from sobol_design_metadata.rds
#'   (written by scripts/021_generate_sobol_design.R)
#'
#' @return tibble with columns:
#'   - parameters: parameter name as used in sobol_indices.csv
#'   - source_pft: PFT name for parameters (if available)
#'   - category:   one of "parameter", "IC", "driver", "dummy"
#'
#' @export
build_param_category_lookup <- function(sobol_metadata) {
  param_names   <- sobol_metadata$param_names
  param_sources <- sobol_metadata$param_sources

  if (is.null(param_names) || length(param_names) == 0) {
    PEcAn.logger::logger.severe("sobol_metadata$param_names is missing/empty.")
  }

  # 1. create base table from metadata (params + dummy)
  lookup <- tibble::tibble(
    parameters = param_names,
    source_pft = if(is.null(param_sources)) NA else param_sources
  )

  # 2. manually append drivers (IC and met) 
  # these are added in script 024, so they exist in results but not in metadata.
  drivers <- tibble::tibble(
    parameters = c("ic_ensemble", "met_ensemble"),
    source_pft = c(NA, NA)
  )
  
  lookup <- dplyr::bind_rows(lookup, drivers)

  # 3. assign categories
  lookup <- lookup %>%
    dplyr::mutate(
      category = dplyr::case_when(
        parameters == "ic_ensemble"  ~ "IC",
        parameters == "met_ensemble" ~ "driver",
        parameters == "dummy"        ~ "dummy",
        TRUE                         ~ "parameter" # All others are params
      )
    )
  
  return(lookup)
}

# ----------------------------------------------------------------------
# 1) Category-level variance partition using Sobol + ensemble variance
# ----------------------------------------------------------------------

#' Partition ensemble variance among parameter / IC / driver / dummy
#'
#' This function combines:
#'  - Sobol first-order sensitivity indices (S_i) for each input
#'  - Total ensemble variance Var(Y_ens) from the global ensemble runs
#'
#' to estimate the variance contribution of each category:
#'  - parameter (all PFT parameters)
#'  - IC (ic_ensemble)
#'  - driver (met_ensemble)
#'  - dummy (optional numerical baseline)
#'  - interaction (leftover variance not explained by first-order effects)
#'
#' For each runid * variable:
#'   Var_i       = S_i * Var_total
#'   Var_cat     = sum(Var_i) for parameters in that category
#'   Var_first   = sum(Var_i) across all parameters
#'   Var_int     = max(Var_total - Var_first, 0)
#'
#' @param sobol_indices Data frame read from data/sobol_indices.csv
#'   (output of scripts/024_compute_sobol_indices.R).
#'   Must contain at least columns:
#'     - runid
#'     - variable
#'     - parameters
#'     - Si_original (first-order S_i)
#'     - Ti_original (total-order ST_i)
#'
#' @param ensemble_variance Data frame with at least:
#'     - runid
#'     - variable (matching sobol_indices$variable)
#'     - ensemble_variance (Var(Y_ens) for that runid * variable)
#'   Optionally:
#'     - site_id (used later to link to local SA)
#'
#' @param sobol_metadata List from data/sobol_design_metadata.rds
#'   containing param_names and param_sources.
#'
#' @return tibble with columns:
#'   - runid
#'   - variable
#'   - category        ("parameter", "IC", "driver", "dummy", "interaction")
#'   - Var_category    (absolute variance contributed by that category)
#'   - Var_total       (total ensemble variance)
#'   - Var_interaction (same for all categories; kept for convenience)
#'   - frac_of_total   (Var_category / Var_total)
#'
#' @export

partition_variance_sources <- function(sobol_indices,
                                       ensemble_variance,
                                       sobol_metadata) {


  required_sobol_cols <- c("runid", "variable", "parameters", 
                           "Si_original", "Ti_original")
  
  missing_sobol <- setdiff(required_sobol_cols, names(sobol_indices))
  if (length(missing_sobol) > 0) {
    PEcAn.logger::logger.severe(
      paste("sobol_indices is missing required columns:",
            paste(missing_sobol, collapse = ", "))
    )
  }

  # Update: Check for site_id in ensemble_variance
  required_var_cols <- c("runid", "site_id", "variable", "ensemble_variance")
  missing_var <- setdiff(required_var_cols, names(ensemble_variance))
  if (length(missing_var) > 0) {
    PEcAn.logger::logger.severe(
      paste("ensemble_variance is missing required columns:",
            paste(missing_var, collapse = ", "))
    )
  }

  # build category lookup
  param_lookup <- build_param_category_lookup(sobol_metadata)

  # prepare Sobol indices
  sobol_long <- sobol_indices %>%
    dplyr::select(runid, variable, parameters,
                  Si_original, Ti_original) %>%
    dplyr::rename(
      Si  = Si_original,
      STi = Ti_original
    ) %>%
    dplyr::left_join(param_lookup, by = "parameters") %>%
    dplyr::mutate(
      # treat any missing category as "parameter"
      category = dplyr::if_else(is.na(category), "parameter", category)
    )

  # join ensemble variance
  sobol_joined <- sobol_long %>%
    dplyr::left_join(ensemble_variance,
                     by = c("runid", "variable")) %>%
    dplyr::mutate(
      Var_total = ensemble_variance,
      Var_i     = Si * Var_total
    )

  # summarize by category
  var_cat <- sobol_joined %>%
    # Update: Group by site_id to preserve it
    dplyr::group_by(runid, site_id, variable, category) %>%
    dplyr::summarize(
      Var_category = sum(Var_i, na.rm = TRUE),
      .groups = "drop"
    )

  # add Var_total for each runid * variable
  var_cat <- var_cat %>%
    dplyr::left_join(
      sobol_joined %>%
        # Update: distinct includes site_id
        dplyr::distinct(runid, site_id, variable, Var_total),
      by = c("runid", "site_id", "variable")
    )

  # compute interaction term per runid * variable
  var_cat <- var_cat %>%
    # Update: Group by site_id
    dplyr::group_by(runid, site_id, variable) %>%
    dplyr::mutate(
      Var_first_sum   = sum(Var_category, na.rm = TRUE),
      Var_interaction = pmax(Var_total - Var_first_sum, 0)
    ) %>%
    dplyr::ungroup()

  # add interaction as its own category row
  interaction_rows <- var_cat %>%
    # Update: distinct includes site_id
    dplyr::distinct(runid, site_id, variable, Var_total, Var_interaction) %>%
    dplyr::mutate(
      category     = "interaction",
      Var_category = Var_interaction
    )

  variance_partition_site <- var_cat %>%
    # Update: Select site_id
    dplyr::select(runid, site_id, variable, category,
                  Var_category, Var_total, Var_interaction) %>%
    dplyr::bind_rows(interaction_rows) %>%
    dplyr::mutate(
      frac_of_total = dplyr::if_else(
        Var_total > 0,
        Var_category / Var_total,
        NA_real_
      )
    ) %>%
    dplyr::arrange(runid, variable, category)

  return(variance_partition_site)
}

# ----------------------------------------------------------------------
# 2) Parameter-level partition using local SA (OAT partial variances)
# ----------------------------------------------------------------------

#' Partition parameter variance into individual parameters using local SA
#'
#' Sobol analysis (global SA) tells us the total variance attributable
#' to all parameters combined (Var_parameter). Local SA (OAT variance
#' decomposition) tells us how important each specific parameter is
#' relative to other parameters, via partial_variance.
#'
#' This function uses partial_variance from aggregated_sensitivity.csv
#' to split Var_parameter (from partition_variance_sources()) into
#' individual parameter contributions.
#'
#' For each site_id * response_var:
#'   f_p             = partial_variance_p / sum(partial_variance)
#'   Var_param_p     = f_p * Var_parameter
#'   frac_of_total_p = Var_param_p / Var_total
#'
#' @param local_sa Data frame from aggregated_sensitivity.csv
#'   (output of scripts/012_aggregate_sensitivity.R) with at least:
#'     - site_id
#'     - response_var
#'     - pft
#'     - parameter
#'     - partial_variance
#'
#' @param variance_partition_site Data frame returned by
#'   partition_variance_sources(), containing:
#'     - runid
#'     - variable
#'     - category
#'     - Var_category
#'     - Var_total
#'
#' @param ensemble_variance Data frame with mapping between runid and
#'   site_id, e.g.:
#'     - runid
#'     - site_id
#'     - variable
#'
#' @return tibble with columns:
#'   - site_id
#'   - runid
#'   - response_var
#'   - parameter
#'   - pft
#'   - local_param_frac
#'   - Var_parameter_param
#'   - Var_total
#'   - frac_of_total
#'
#' @export
partition_parameter_variance_local <- function(local_sa,
                                               variance_partition_site,
                                               ensemble_variance) {


  required_local_cols <- c("site_id", "response_var",
                           "pft", "parameter", "partial_variance")
  missing_local <- setdiff(required_local_cols, names(local_sa))
  if (length(missing_local) > 0) {
    PEcAn.logger::logger.severe(
      paste("local_sa is missing required columns:",
            paste(missing_local, collapse = ", "))
    )
  }

  if (!all(c("runid", "site_id", "variable") %in% names(ensemble_variance))) {
    PEcAn.logger::logger.severe(
      "ensemble_variance must contain 'runid', 'site_id', and 'variable' to map runid -> site_id."
    )
  }

  # compute local parameter fractions
  local_param_frac <- local_sa %>%
    dplyr::group_by(site_id, response_var) %>%
    dplyr::mutate(
      total_partial_var = sum(partial_variance, na.rm = TRUE),
      local_param_frac = dplyr::if_else(
        total_partial_var > 0,
        partial_variance / total_partial_var,
        NA_real_
      )
    ) %>%
    dplyr::ungroup() %>%
    dplyr::select(site_id, response_var, pft, parameter, local_param_frac)

  # extract Var_parameter per runid * variable
  var_param_run <- variance_partition_site %>%
    dplyr::filter(category == "parameter") %>%
    dplyr::select(runid, variable,
                  Var_parameter = Var_category,
                  Var_total)

  # map runid -> site_id, response_var
  runid_site_lookup <- ensemble_variance %>%
    dplyr::distinct(runid, site_id, variable) %>%
    dplyr::rename(response_var = variable)

  var_param_site <- var_param_run %>%
    dplyr::left_join(runid_site_lookup,
                     by = c("runid", "variable" = "response_var"))

  # join local SA fractions and scale
  variance_partition_params <- var_param_site %>%
    dplyr::rename(response_var = variable) %>%
    dplyr::left_join(
      local_param_frac,
      by = c("site_id", "response_var")
    ) %>%
    dplyr::mutate(
      Var_parameter_param = local_param_frac * Var_parameter,
      frac_of_total       = dplyr::if_else(
        Var_total > 0,
        Var_parameter_param / Var_total,
        NA_real_
      )
    ) %>%
    dplyr::arrange(site_id, response_var, parameter, pft)

  return(variance_partition_params)
}
