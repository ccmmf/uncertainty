#' Generate Sobol Design Matrix for Global Sensitivity Analysis
#'
#' Creates Saltelli-style sampling matrices for variance-based sensitivity
#' analysis using the sensobol package.
#' 
#' @description
#' This function generates a Sobol' quasi-random sequence for all uncertain 
#' inputs, including both continuous parameters and discrete 
#' drivers (Initial Conditions and Meteorology).
#' 
#' Discrete inputs (IC, Met) are handled by sampling them continuously on 
#' the interval [0, 1] within the Sobol design and then discretizing them 
#' using the inverse transform method (floor + qunif). This allows their 
#' variance contributions (Si, Ti) to be calculated alongside parameters.
#'
#' @param N Base sample size for Sobol matrices. Total runs = N × (k + 2)
#'   where k is the number of parameters. Recommended: 512-1024 for convergence.
#' @param params Named list of parameter prior specifications. Each element
#'   should contain: `distn` (distribution name), `parama` (first parameter),
#'   `paramb` (second parameter). Typically loaded from PEcAn posterior files.
#' @param ic_range Integer vector of available IC ensemble IDs. Should match
#'   the number of IC files in settings XML (e.g. 1:20, 1:100).
#' @param met_range Integer vector of available met ensemble IDs. Should match
#'   the number of met files in settings XML (e.g. 1:10).
#'
#' @return Data frame with N*(k + 2) rows and columns:
#'
#' @export
generate_sobol_design <- function(N = 512,
                                   params,
                                   ic_range = 1:100,
                                   met_range = 1:10) {

  # -----------------------------------------------------------------------
  # Dependency check
  # -----------------------------------------------------------------------
  if (!requireNamespace("sensobol", quietly = TRUE)) {
    PEcAn.logger::logger.severe("Package 'sensobol' is required. Install with: install.packages('sensobol')")
  }

  # -----------------------------------------------------------------------
  # Input validation
  # -----------------------------------------------------------------------
  if (!is.list(params) || length(params) == 0) {
    PEcAn.logger::logger.severe("'params' must be a non-empty named list")
  }

  if (N < 1 || N != floor(N)) {
    PEcAn.logger::logger.severe("'N' must be a positive integer")
  }

  if (length(ic_range) == 0 || length(met_range) == 0) {
    PEcAn.logger::logger.severe("'ic_range' and 'met_range' must be non-empty vectors")
  }

  # -----------------------------------------------------------------------
  # Setup
  # -----------------------------------------------------------------------
  set.seed(42)

  # We treat IC and Met as parameters so sensobol can calculate their indices.
  pft_param_names <- names(params)
  
  # Add IC and Met to the parameter list for matrix generation
  all_param_names <- c(pft_param_names, "ic_ensemble", "met_ensemble")
  k <- length(all_param_names)
  # Saltelli sampling = N * (k + 2)
  total_runs <- N * (k + 2)

  # -----------------------------------------------------------------------
  # Generate Sobol matrices for ALL parameters (continuous + discrete)
  # -----------------------------------------------------------------------
  # creates A, B, and AB_i matrices following Saltelli, required for variance decomposition
  # Output: matrix with N*(k+2) rows, k columns, values in [0, 1]

  mat <- sensobol::sobol_matrices(
    N = N,
    params = all_param_names,
    type = "QRN",        # Quasi-random Sobol sequence (space-filling)
    order = "first",     # Compute first-order + total-order indices
    matrices = c("A", "B", "AB") # Saltelli design
  )

  design <- as.data.frame(mat)

  # -----------------------------------------------------------------------
  # Scale parameters from [0,1] to prior distributions
  # -----------------------------------------------------------------------

  for (param_name in pft_param_names) {
    prior <- params[[param_name]]
    x <- design[[param_name]]  # Values in [0, 1]

    # Validate prior structure
    if (is.null(prior$distn) || is.null(prior$parama)) {
      PEcAn.logger::logger.severe(sprintf("Parameter '%s' missing 'distn' or 'parama'", param_name))
    }

    # Apply quantile transformation
    design[[param_name]] <- switch(
      prior$distn,
      "norm"    = qnorm(x, mean = prior$parama, sd = prior$paramb),
      "lnorm"   = qlnorm(x, meanlog = prior$parama, sdlog = prior$paramb),
      "unif"    = qunif(x, min = prior$parama, max = prior$paramb),
      "exp"     = qexp(x, rate = prior$parama),
      "gamma"   = qgamma(x, shape = prior$parama, rate = prior$paramb),
      "beta"    = qbeta(x, shape1 = prior$parama, shape2 = prior$paramb),
      "weibull" = qweibull(x, shape = prior$parama, scale = prior$paramb),
      {
        # Fallback
        PEcAn.logger::logger.warn(sprintf("Unknown dist '%s' for '%s'. Using unif.", prior$distn, param_name))
        paramb <- if (is.null(prior$paramb)) prior$parama + 1 else prior$paramb
        qunif(x, min = prior$parama, max = paramb)
      }
    )
  }

  # -----------------------------------------------------------------------
  # Transform IC and Met (Discrete Uniform)
  # -----------------------------------------------------------------------
  # This follows the method in sensobol documentation for discrete uniform.
  # We map the continuous [0,1] Sobol sample to the integer indices.
  # Example: If met_range is 1:10, we sample uniform(1, 11) and floor it.
  
  ic_min <- min(ic_range)
  ic_max <- max(ic_range)
  # We add +1 to max inside qunif because floor() truncates. 
  # floor(qunif(0.99, 1, 11)) -> floor(10.9) -> 10.
  design$ic_ensemble <- floor(stats::qunif(design$ic_ensemble, min = ic_min, max = ic_max + 1))

  met_min <- min(met_range)
  met_max <- max(met_range)
  design$met_ensemble <- floor(stats::qunif(design$met_ensemble, min = met_min, max = met_max + 1))

  # Ensure we didn't go out of bounds
  design$ic_ensemble[design$ic_ensemble > ic_max] <- ic_max
  design$met_ensemble[design$met_ensemble > met_max] <- met_max
  
  # -----------------------------------------------------------------------
  # Add Metadata columns
  # -----------------------------------------------------------------------
  # sample_id is strictly necessary to map results back to rows later
  design$sample_id <- seq_len(nrow(design))
  
  # Reorder columns: ID, Params, IC, Met
  design <- design[, c("sample_id", pft_param_names, "ic_ensemble", "met_ensemble")]

  return(design)
}
