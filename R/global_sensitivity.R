#' Generate Sobol design matrix for global sensitivity analysis
#'
#' Creates Saltelli-style sampling matrices for variance-based sensitivity
#' analysis using the sensobol package.
#'
#' This function generates a Sobol' quasi-random sequence for all uncertain
#' inputs, including continuous parameters (PFT traits, management rates),
#' discrete drivers (Initial Conditions and Meteorology), and a dummy
#' parameter for Sobol validation.
#'
#' Discrete inputs (IC, Met) are handled by sampling them continuously on
#' the interval [0, 1] within the Sobol design and then discretizing them
#' using the inverse transform method (floor + qunif). This allows their
#' variance contributions (Si, Ti) to be calculated alongside parameters.
#'
#' @param N Base sample size for Sobol matrices. Total runs = N * (k + 2)
#'   where k is the number of parameters. Recommended: 512-1024 for convergence
#' @param params Named list of parameter prior specifications. Each element
#'   should contain: `distn` (distribution name), `parama` (first parameter),
#'   `paramb` (second parameter). For truncnorm: also `paramc` (lower bound)
#'   and `paramd` (upper bound). Management parameters should be prefixed
#'   with "mgmt." to distinguish them from PFT parameters.
#' @param ic_size Integer, number of IC ensemble members (default 100).
#' @param met_size Integer, number of met ensemble members (default 10).
#'
#' @return tibble with N * (k + 2) rows and columns:
#'   - `sample_id`: unique integer per row
#'   - One column per entry in `params` (PFT traits, mgmt.*, dummy)
#'   - `ic_ensemble`: integer IC ensemble index
#'   - `met_ensemble`: integer met ensemble index
#'
#' @export
generate_sobol_design <- function(N = 512,
                                  params,
                                  ic_size = 100L,
                                  met_size = 10L) {

  if (!requireNamespace("sensobol", quietly = TRUE)) {
    PEcAn.logger::logger.severe(
      "Package 'sensobol' is required. Install with: install.packages('sensobol')"
    )
  }

  if (!is.list(params) || length(params) == 0) {
    PEcAn.logger::logger.severe("'params' must be a non-empty named list")
  }
  if (N < 1 || N != floor(N)) {
    PEcAn.logger::logger.severe("'N' must be a positive integer")
  }
  if (ic_size < 1 || met_size < 1) {
    PEcAn.logger::logger.severe("'ic_size' and 'met_size' must be >= 1")
  }

  set.seed(42)

  # ic and met are included in the sobol matrix so sensobol can compute
  # their first-order and total-order indices alongside continuous params
  continuous_params <- names(params)
  all_params <- c(continuous_params, "ic_ensemble", "met_ensemble")

  # saltelli design: A, B, and k AB_i matrices -> N * (k + 2) rows
  mat <- sensobol::sobol_matrices(
    N = N,
    params = all_params,
    type = "QRN", # quasi-random sobol sequence (space-filling)
    order = "first", # compute first-order + total-order indices
    matrices = c("A", "B", "AB") # saltelli design
  ) 

  design <- tibble::as_tibble(as.data.frame(mat))

  # scale continuous params from [0,1] to prior distributions
  for (param_name in continuous_params) {
    prior <- params[[param_name]]

    if (is.null(prior$distn) || is.null(prior$parama)) {
      PEcAn.logger::logger.severe(
        "Parameter '", param_name, "' missing 'distn' or 'parama'"
      )
    }

    x <- design[[param_name]]

    design[[param_name]] <- switch(
      prior$distn,
      "norm"      = stats::qnorm(x, mean = prior$parama, sd = prior$paramb),
      "lnorm"     = stats::qlnorm(x, meanlog = prior$parama, sdlog = prior$paramb),
      "unif"      = stats::qunif(x, min = prior$parama, max = prior$paramb),
      "exp"       = stats::qexp(x, rate = prior$parama),
      "gamma"     = stats::qgamma(x, shape = prior$parama, rate = prior$paramb),
      "beta"      = stats::qbeta(x, shape1 = prior$parama, shape2 = prior$paramb),
      "weibull"   = stats::qweibull(x, shape = prior$parama, scale = prior$paramb),
      "pois"      = stats::qpois(x, lambda = prior$parama),
      "truncnorm" = truncnorm::qtruncnorm(
        x,
        a = prior$paramc, b = prior$paramd,
        mean = prior$parama, sd = prior$paramb
      ),
      {
        PEcAn.logger::logger.warn(
          "Unknown distribution '", prior$distn, "' for '", param_name,
          "'. Falling back to uniform."
        )
        paramb <- if (is.null(prior$paramb)) prior$parama + 1 else prior$paramb
        stats::qunif(x, min = prior$parama, max = paramb)
      }
    )
  }

  # discretize ic and met from [0,1] to integer indices {1, ..., size}
  design[["ic_ensemble"]] <- floor(
    stats::qunif(design[["ic_ensemble"]], min = 1, max = ic_size + 1)
  )
  design[["ic_ensemble"]] <- pmin(design[["ic_ensemble"]], ic_size)

  design[["met_ensemble"]] <- floor(
    stats::qunif(design[["met_ensemble"]], min = 1, max = met_size + 1)
  )
  design[["met_ensemble"]] <- pmin(design[["met_ensemble"]], met_size)

  design[["sample_id"]] <- seq_len(nrow(design))

  # reorder: id first, then continuous params, then drivers
  design[, c("sample_id", continuous_params, "ic_ensemble", "met_ensemble")]
}


#' Compute Sobol sensitivity indices from ensemble output files
#'
#' Loads PEcAn ensemble output Rdata files for each site and variable,
#' then calls sensobol::sobol_indices() to compute first-order and
#' total-order indices with bootstrapped confidence intervals.
#'
#' @param output_dir Path to the directory containing ensemble.output.*.Rdata files.
#' @param run_ids Character vector of run IDs (site identifiers from the
#'   ensemble output filenames).
#' @param params Character vector of all parameter names (including
#'   ic_ensemble and met_ensemble) in the Sobol design.
#' @param N Integer base sample size used to generate the Sobol matrices.
#' @param R Integer number of bootstrap replicates for confidence intervals.
#'
#' @return tibble in wide format with columns: runid, variable,
#'   parameters, and pivoted Si/Ti estimates with confidence intervals.
compute_sobol_indices <- function(output_dir,
                                  run_ids,
                                  params,
                                  N,
                                  R = 500L) {

  expected_len <- N * (length(params) + 2L)
  all_files <- list.files(
    output_dir,
    "^ensemble\\.output.*\\.Rdata$",
    full.names = TRUE
  )

  if (length(all_files) == 0) {
    PEcAn.logger::logger.severe("No ensemble.output.*.Rdata found in ", output_dir)
  }

  results_all_sites <- list()

  for (rid in run_ids) {
    site_files <- grep(
      paste0("ensemble\\.output\\.", rid),
      all_files,
      value = TRUE
    )
    if (length(site_files) == 0) next

    # variable name is the 4th token in the dotted filename
    vars <- unique(vapply(
      strsplit(basename(site_files), "\\."),
      \(x) x[4],
      character(1)
    ))

    site_results <- list()

    for (v in vars) {
      vf <- site_files[
        vapply(strsplit(basename(site_files), "\\."), \(x) x[4] == v, logical(1))
      ]
      if (length(vf) != 1) {
        PEcAn.logger::logger.warn(sprintf(
          "variable %s for runid %s has %d files -- skipping", v, rid, length(vf)
        ))
        next
      }

      env <- new.env(parent = emptyenv())
      load(vf, envir = env)
      Y <- as.numeric(unlist(env$ensemble.output))

      if (length(Y) != expected_len) {
        PEcAn.logger::logger.severe(sprintf(
          "variable %s for runid %s has %d values (expected %d)",
          v, rid, length(Y), expected_len
        ))
      }

      idx <- sensobol::sobol_indices(
        Y = Y,
        N = N,
        params = params,
        boot = TRUE,
        R = R
      )

      df <- tibble::as_tibble(idx$results)
      df$variable <- v
      df$runid <- rid
      site_results[[v]] <- df
    }

    results_all_sites[[rid]] <- dplyr::bind_rows(site_results)
  }

  long <- dplyr::bind_rows(results_all_sites)

  # pivot to wide format (Si/Ti with confidence intervals)
  long |>
    dplyr::select(
      "runid", "variable", "parameters", "sensitivity",
      "original", "low.ci", "high.ci", "bias", "std.error"
    ) |>
    tidyr::pivot_wider(
      names_from = "sensitivity",
      values_from = c("original", "low.ci", "high.ci", "bias", "std.error"),
      names_glue = "{sensitivity}_{.value}"
    ) |>
    dplyr::arrange(.data$runid, .data$variable, .data$parameters)
}

.data <- rlang::.data