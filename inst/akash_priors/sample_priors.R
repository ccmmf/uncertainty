#!/usr/bin/env Rscript
# Functions to sample from management priors
# See data/management_priors.yaml for distributions and sources

`%||%` <- rlang::`%||%`

#' Load management priors from YAML
#'
#' Reads the management_priors.yaml file containing prior distributions
#' for agricultural management parameters.
#
#' @param path Character. Path to management_priors.yaml. Defaults to
#'   `here::here("data", "management_priors.yaml")`.
#' @return Named list containing:
#'   - `practices`: Parameter distributions for each practice type
#'   - `adoption_rates`: Regional adoption rate priors
#'   - `crop_baselines`: Crop-specific default configurations
#'   - `compatibility`: Practice compatibility matrix
#'   - `metadata`: Source citations and version info
#'
#' @examples
#' \dontrun{
#' priors <- load_priors()
#' names(priors$practices)
#' # [1] "conventional_tillage" "reduced_tillage" "no_tillage" ...
#' }
#'
#' @export
load_priors <- function(path = here::here("data", "management_priors.yaml")) {
  if (!file.exists(path)) {
    PEcAn.logger::logger.severe("Priors file not found: ", path)
  }
  priors <- yaml::read_yaml(path)
  PEcAn.logger::logger.info(
    "Loaded priors v", priors$schema_version %||% "unknown",
    " (", length(priors$practices), " practices)"
  )
  priors
}

#' Sample from a distribution spec
#'
#' Generates random samples from a distribution defined in the priors YAML.
#' Supports: constant, normal, truncnorm, beta, lognormal, categorical, quantiles.
#'
#' @param dist_spec Named list with distribution parameters. Must include
#'   `distribution` key specifying the distribution type.
#' @param n Integer. Number of samples to generate. Default 1.
#'
#' @return Vector of sampled values (numeric or character for categorical).
#'
#' @details
#' Distribution types and required parameters:
#' - `constant`: `value`
#' - `normal`: `mean`, `sd`
#' - `truncnorm`: `mean`, `sd`, `lower`, `upper`
#' - `beta`: `a`, `b` (shape parameters)
#' - `lognormal`: `meanlog`, `sdlog`
#' - `categorical`: `choices`, `probabilities`
#' - `quantiles`: `q25`, `median`, `q75` (for dates)
#'
#' @examples
#' \dontrun{
#' # Sample from compost rate prior (lognormal)
#' dist_spec <- list(distribution = "lognormal", meanlog = -0.92, sdlog = 0.35)
#' samples <- sample_distribution(dist_spec, n = 1000)
#' hist(samples, main = "Compost C rate (kg C/m2)")
#' }
#'
#' @export
sample_distribution <- function(dist_spec, n = 1) {
  dist_type <- dist_spec$distribution

  if (is.null(dist_type)) {
    PEcAn.logger::logger.error("Missing 'distribution' key")
    return(NA)
  }

  switch(dist_type,
    constant = rep(dist_spec$value, n),
    normal = rnorm(n, mean = dist_spec$mean, sd = dist_spec$sd),
    truncnorm = truncnorm::rtruncnorm(
      n,
      a = dist_spec$lower %||% -Inf,
      b = dist_spec$upper %||% Inf,
      mean = dist_spec$mean,
      sd = dist_spec$sd
    ),
    beta = rbeta(n, shape1 = dist_spec$a, shape2 = dist_spec$b),
    lognormal = rlnorm(n, meanlog = dist_spec$meanlog, sdlog = dist_spec$sdlog),
    categorical = sample(
      dist_spec$choices,
      size = n,
      replace = TRUE,
      prob = dist_spec$probabilities
    ),
    quantiles = sample_from_quantiles(dist_spec, n),
    {
      PEcAn.logger::logger.error("Unknown distribution: ", dist_type)
      rep(NA, n)
    }
  )
}

#' Sample from quantile spec (for dates mostly)
#'
#' Generates samples from a distribution defined by quantiles, typically
#' used for date parameters. Uses linear interpolation between quantiles.
#'
#' @param dist_spec List with quantile keys: `q25`, `median`, `q75` (or similar).
#'   Values in MM-DD format for dates, or numeric for other quantities.
#' @param n Number of samples.
#'
#' @return Vector of sampled values. For dates, returns MM-DD format strings.
#'
#' @details
#' This function is used primarily for planting and termination dates where
#' regional variation is captured via quantiles rather than parametric
#' distributions.
#'
#' @keywords internal
sample_from_quantiles <- function(dist_spec, n = 1) {
  quantile_names <- grep("^q\\d+$|^median$", names(dist_spec), value = TRUE)
  if (length(quantile_names) < 2) {
    PEcAn.logger::logger.warn("Need at least 2 quantile points")
    return(rep(NA, n))
  }

  probs <- sapply(quantile_names, function(q) {
    if (q == "median") return(0.5)
    as.numeric(gsub("q", "", q)) / 100
  })
  values <- sapply(quantile_names, function(q) dist_spec[[q]])

  ord <- order(probs)
  probs <- probs[ord]
  values <- values[ord]

  is_date <- all(grepl("^\\d{2}-\\d{2}$", values))

  if (is_date) {
    # convert MM-DD to DOY, sample, convert back
    doy <- sapply(values, function(v) {
      as.numeric(format(as.Date(paste0("2024-", v)), "%j"))
    })
    sampled_doy <- sample_quantile_interpolate(probs, doy, n)
    sapply(sampled_doy, function(d) {
      d <- ((d - 1) %% 366) + 1
      format(as.Date(d - 1, origin = "2024-01-01"), "%m-%d")
    })
  } else {
    sample_quantile_interpolate(probs, as.numeric(values), n)
  }
}

#' Interpolate and sample from quantiles
#'
#' Uses linear interpolation on quantile points to generate random samples.
#' Draws uniform random variates and maps through empirical CDF.
#'
#' @param probs Numeric vector of probabilities (0 to 1).
#' @param values Numeric vector of quantile values.
#' @param n Number of samples.
#'
#' @return Numeric vector of sampled values.
#'
#' @details
#' This is a simple empirical quantile approach. For more sophisticated
#' fitting, consider using PEcAn.priors::fit.dist() to fit a parametric
#' distribution to the quantiles.
#'
#' @keywords internal
sample_quantile_interpolate <- function(probs, values, n) {
  # extend to 0 and 1 for extrapolation
  if (min(probs) > 0) {
    lower_ext <- values[1] - (values[2] - values[1]) * probs[1] / (probs[2] - probs[1])
    probs <- c(0, probs)
    values <- c(lower_ext, values)
  }
  if (max(probs) < 1) {
    n_p <- length(probs)
    upper_ext <- values[n_p] + (values[n_p] - values[n_p - 1]) * (1 - probs[n_p]) / (probs[n_p] - probs[n_p - 1])
    probs <- c(probs, 1)
    values <- c(values, upper_ext)
  }
  u <- runif(n)
  approx(probs, values, xout = u, rule = 2)$y
}

#' Sample a complete event configuration for a practice
#'
#' Generates n independent samples of all parameters defined for a
#' management practice. Returns a list of sampled configurations.
#'
#' @param practice_name Character. Name of practice from priors (e.g.
#'   "compost_application", "reduced_tillage").
#' @param priors List. Loaded priors from `load_priors()`.
#' @param n Integer. Number of ensemble members to generate.
#'
#' @return List of length n, each element containing sampled parameter values.
#'
#' @examples
#' \dontrun{
#' priors <- load_priors()
#' samples <- sample_practice("compost_application", priors, n = 100)
#' }
#'
#' @export
sample_practice <- function(practice_name, priors, n = 1) {
  practice <- priors$practices[[practice_name]]
  if (is.null(practice)) {
    PEcAn.logger::logger.error("Unknown practice: ", practice_name)
    return(NULL)
  }

  params <- practice$parameters
  if (is.null(params)) {
    PEcAn.logger::logger.warn("No params for ", practice_name)
    return(lapply(seq_len(n), function(i) list()))
  }

  lapply(seq_len(n), function(i) {
    lapply(params, function(p) {
      if (is.list(p) && !is.null(p$distribution)) {
        sample_distribution(p, n = 1)
      } else {
        p
      }
    })
  })
}

#' Sample regional practice adoption rates and assign to fields
#'
#' Given a region and plant functional type, samples adoption rates for
#' each practice and randomly assigns practices to fields based on those rates.
#'
#' @param region Character. Region name (e.g. "San Joaquin Valley").
#' @param pft Character. Plant functional type (e.g. "annual_row_crop").
#' @param priors List. Loaded priors from `load_priors()`.
#' @param n_fields Integer. Number of fields to assign practices to.
#'
#' @return Data frame with columns:
#'   - `field_idx`: Field identifier (1 to n_fields)
#'   - One column per practice: TRUE/FALSE indicating if practice is applied
#'
#' @details
#' Handles mutually exclusive practices (e.g. tillage types) by keeping
#' only one when multiple are assigned to a field.
#'
#' @examples
#' \dontrun{
#' priors <- load_priors()
#' assignments <- sample_adoption(
#'   region = "San Joaquin Valley",
#'   pft = "annual_row_crop",
#'   priors = priors,
#'   n_fields = 1000
#' )
#' }
#'
#' @export
sample_adoption <- function(region, pft, priors, n_fields) {
  rates <- priors$adoption_rates[[region]][[pft]]
  if (is.null(rates)) {
    PEcAn.logger::logger.warn("No rates for ", region, "/", pft)
    return(NULL)
  }

  # sample rate for each practice
  practice_rates <- lapply(names(rates), function(p) {
    list(practice = p, rate = sample_distribution(rates[[p]], n = 1))
  })

  assignments <- data.frame(field_idx = seq_len(n_fields))
  for (pr in practice_rates) {
    assignments[[pr$practice]] <- runif(n_fields) < pr$rate
  }

  # handle mutually exclusive tillage types
  tillage_cols <- intersect(
    c("conventional_tillage", "reduced_tillage", "no_tillage"),
    names(assignments)
  )
  if (length(tillage_cols) > 1) {
    for (i in seq_len(n_fields)) {
      active <- tillage_cols[as.logical(assignments[i, tillage_cols])]
      if (length(active) > 1) {
        active_rates <- sapply(practice_rates, function(pr) {
          if (pr$practice %in% active) pr$rate else 0
        })
        names(active_rates) <- sapply(practice_rates, `[[`, "practice")
        keep <- sample(active, 1, prob = active_rates[active] / sum(active_rates[active]))
        assignments[i, setdiff(tillage_cols, keep)] <- FALSE
      }
    }
  }

  assignments
}


#' Calculate org_n from org_c and C:N ratio
#' @export
calculate_org_n <- function(org_c_kg_m2, cn_ratio) {
  org_c_kg_m2 / cn_ratio
}

#' Convert compost dry tons/ac to kg C/m2
#'
#' @param tons_per_acre dry tons per acre
#' @param carbon_fraction C fraction of dry compost (default 0.35)
#' @return kg C/m2
#' @export
compost_tons_to_kg_c <- function(tons_per_acre, carbon_fraction = 0.35) {
  # convert tons/ac to kg/m2, then multiply by C fraction
  kg_per_m2 <- PEcAn.utils::ud_convert(tons_per_acre, "ton/acre", "kg/m^2")
  kg_per_m2 * carbon_fraction
}

#' Convert kg C/m2 back to dry tons/ac
#' @export
kg_c_to_compost_tons <- function(kg_c_per_m2, carbon_fraction = 0.35) {
  kg_per_m2 <- kg_c_per_m2 / carbon_fraction
  PEcAn.utils::ud_convert(kg_per_m2, "kg/m^2", "ton/acre")
}

#' Convert tillage_eff to approx STIR value
#' STIR scale is 0-200 per NRCS
#' @export
tillage_eff_to_stir <- function(tillage_eff_0to1) {
  tillage_eff_0to1 * 200
}

#' Convert STIR to tillage_eff
#' @export
stir_to_tillage_eff <- function(stir) {
  stir / 200
}