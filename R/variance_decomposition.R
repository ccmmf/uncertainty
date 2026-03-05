#' Calculate total variance of ensemble outputs
#'
#' Reads the raw PEcAn ensemble output files (Rdata) and calculates the
#' scalar variance of the output variable Y for each runid.
#'
#' Uses the PEcAn settings object to map 'runid' (Ensemble ID) to 'site_id'
#' by parsing the <ensemble> block in the XML.
#'
#' @param output_dir Path to the 'output' directory containing ensemble.output.*.Rdata
#' @param run_ids Vector of run IDs (from sobol_indices or filenames)
#' @param settings PEcAn settings object (read from pecan.CONFIGS.xml).
#' @return Tibble with columns: runid, site_id, variable, ensemble_variance
calculate_ensemble_variance <- function(output_dir, run_ids, settings) {

  # Build runid -> siteid map from settings$ensemble
  site_keys <- grep("^site\\.", names(settings$ensemble), value = TRUE)

  workflow_site_map <- purrr::map_dfr(site_keys, \(key) {
    site_id <- sub("^site\\.", "", key)
    run_id <- settings$ensemble[[key]]$ensemble.id
    if (is.null(run_id)) return(NULL)
    tibble::tibble(site_id = site_id, runid = as.character(run_id))
  })

  if (nrow(workflow_site_map) == 0) {
    PEcAn.logger::logger.warn(
      "Could not parse Site IDs from settings$ensemble. 'site_id' will be NA."
    )
  }

  results <- list()
  target_run_ids <- as.character(run_ids)

  for (rid in target_run_ids) {
    pattern <- paste0("ensemble\\.output\\.", rid, "\\..*\\.Rdata$")
    files <- list.files(output_dir, pattern = pattern, full.names = TRUE)

    if (length(files) == 0) {
      PEcAn.logger::logger.warn(sprintf("No output found for Run ID %s", rid))
      next
    }

    curr_site_id <- workflow_site_map$site_id[workflow_site_map$runid == rid]
    if (length(curr_site_id) == 0) {
      PEcAn.logger::logger.warn(sprintf(
        "Run ID %s not found in settings$ensemble map.", rid
      ))
      curr_site_id <- NA_character_
    }

    for (f in files) {
      env <- new.env(parent = emptyenv())
      load(f, envir = env)

      # variable name is the 4th token in the dotted filename
      parts <- strsplit(basename(f), "\\.")[[1]]
      var_name <- parts[4]

      if (exists("ensemble.output", envir = env)) {
        Y <- unlist(env$ensemble.output)
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

  if (length(results) == 0) return(NULL)
  dplyr::bind_rows(results)
}


#' Build parameter category lookup from Sobol metadata
#'
#' Maps each parameter into a category:
#' - "parameter": all PFT parameters
#' - "management": management parameters (mgmt.* prefix)
#' - "IC": initial conditions (ic_ensemble)
#' - "driver": meteorological drivers (met_ensemble)
#' - "dummy": dummy parameter for numerical baseline
#'
#' @param sobol_metadata List read from sobol_design_metadata.rds
#' @return Tibble with columns: parameters, source_pft, category
build_param_category_lookup <- function(sobol_metadata) {
  param_names   <- sobol_metadata$param_names
  param_sources <- sobol_metadata$param_sources

  if (is.null(param_names) || length(param_names) == 0) {
    PEcAn.logger::logger.severe("sobol_metadata$param_names is missing/empty.")
  }

  lookup <- tibble::tibble(
    parameters = param_names,
    source_pft = if (is.null(param_sources)) NA_character_ else param_sources
  )

  # append driver entries (added in 024, not in metadata$param_names)
  drivers <- tibble::tibble(
    parameters = c("ic_ensemble", "met_ensemble"),
    source_pft = c(NA_character_, NA_character_)
  )

  lookup <- dplyr::bind_rows(lookup, drivers) |>
    dplyr::mutate(
      category = dplyr::case_when(
        parameters == "ic_ensemble"  ~ "IC",
        parameters == "met_ensemble" ~ "driver",
        parameters == "dummy"        ~ "dummy",
        grepl("^mgmt\\.", parameters) ~ "management",
        TRUE                         ~ "parameter"
      )
    )

  lookup
}


#' Partition ensemble variance among parameter / IC / driver / management / dummy
#'
#' Combines Sobol first-order sensitivity indices (S_i) with total ensemble
#' variance Var(Y_ens) to estimate the variance contribution of each category.
#'
#' For each runid * variable:
#'   Var_i       = S_i * Var_total
#'   Var_cat     = sum(Var_i) for parameters in that category
#'   Var_int     = max(Var_total - sum(all Var_i), 0)
#'
#' @param sobol_indices Data frame from data/sobol_indices.csv.
#'   must contain: runid, variable, parameters, Si_original, Ti_original.
#' @param ensemble_variance Data frame with: runid, site_id, variable,
#'   ensemble_variance.
#' @param sobol_metadata List from data/sobol_design_metadata.rds.
#'
#' @return Tibble with columns: runid, site_id, variable, category,
#'   Var_category, Var_total, Var_interaction, frac_of_total.
partition_variance_sources <- function(sobol_indices,
                                       ensemble_variance,
                                       sobol_metadata) {

  required_sobol_cols <- c("runid", "variable", "parameters",
                           "Si_original", "Ti_original")
  missing_sobol <- setdiff(required_sobol_cols, names(sobol_indices))
  if (length(missing_sobol) > 0) {
    PEcAn.logger::logger.severe(
      "sobol_indices missing columns: ", paste(missing_sobol, collapse = ", ")
    )
  }

  required_var_cols <- c("runid", "site_id", "variable", "ensemble_variance")
  missing_var <- setdiff(required_var_cols, names(ensemble_variance))
  if (length(missing_var) > 0) {
    PEcAn.logger::logger.severe(
      "ensemble_variance missing columns: ", paste(missing_var, collapse = ", ")
    )
  }

  param_lookup <- build_param_category_lookup(sobol_metadata)

  sobol_long <- sobol_indices |>
    dplyr::select("runid", "variable", "parameters",
                  "Si_original", "Ti_original") |>
    dplyr::rename(Si = "Si_original", STi = "Ti_original") |>
    dplyr::left_join(param_lookup, by = "parameters") |>
    dplyr::mutate(
      category = dplyr::if_else(is.na(.data$category), "parameter", .data$category)
    )

  sobol_joined <- sobol_long |>
    dplyr::left_join(ensemble_variance, by = c("runid", "variable")) |>
    dplyr::mutate(
      Var_total = .data$ensemble_variance,
      Var_i     = .data$Si * .data$Var_total
    )

  # summarize by category
  var_cat <- sobol_joined |>
    dplyr::summarize(
      Var_category = sum(.data$Var_i, na.rm = TRUE),
      .by = c("runid", "site_id", "variable", "category")
    )

  # join back Var_total
  var_total_lookup <- sobol_joined |>
    dplyr::distinct(.data$runid, .data$site_id, .data$variable, .data$Var_total)

  var_cat <- var_cat |>
    dplyr::left_join(var_total_lookup, by = c("runid", "site_id", "variable"))

  # compute interaction term per runid * variable
  var_cat <- var_cat |>
    dplyr::mutate(
      Var_first_sum   = sum(.data$Var_category, na.rm = TRUE),
      Var_interaction = pmax(.data$Var_total - .data$Var_first_sum, 0),
      .by = c("runid", "site_id", "variable")
    )

  # add interaction as its own category row
  interaction_rows <- var_cat |>
    dplyr::distinct(.data$runid, .data$site_id, .data$variable,
                    .data$Var_total, .data$Var_interaction) |>
    dplyr::mutate(
      category     = "interaction",
      Var_category = .data$Var_interaction
    )

  var_cat |>
    dplyr::select("runid", "site_id", "variable", "category",
                  "Var_category", "Var_total", "Var_interaction") |>
    dplyr::bind_rows(interaction_rows) |>
    dplyr::mutate(
      frac_of_total = dplyr::if_else(
        .data$Var_total > 0,
        .data$Var_category / .data$Var_total,
        NA_real_
      )
    ) |>
    dplyr::arrange(.data$runid, .data$variable, .data$category)
}


#' Partition parameter variance into individual parameters using local SA
#'
#' Uses partial_variance from local OAT sensitivity analysis to split
#' the global Var_parameter into individual parameter contributions.
#'
#' For each site_id * response_var:
#'   f_p         = partial_variance_p / sum(partial_variance)
#'   Var_param_p = f_p * Var_parameter
#'   frac_total  = Var_param_p / Var_total
#'
#' @param local_sa Data frame from aggregated_sensitivity.csv with:
#'   site_id, response_var, pft, parameter, partial_variance.
#' @param variance_partition_site Data frame from partition_variance_sources().
#' @param ensemble_variance Data frame mapping runid to site_id.
#'
#' @return Tibble with columns: site_id, runid, response_var, parameter,
#'   pft, local_param_frac, Var_parameter_param, Var_total, frac_of_total.
partition_parameter_variance_local <- function(local_sa,
                                               variance_partition_site,
                                               ensemble_variance) {

  required_local_cols <- c("site_id", "response_var",
                           "pft", "parameter", "partial_variance")
  missing_local <- setdiff(required_local_cols, names(local_sa))
  if (length(missing_local) > 0) {
    PEcAn.logger::logger.severe(
      "local_sa missing columns: ", paste(missing_local, collapse = ", ")
    )
  }

  if (!all(c("runid", "site_id", "variable") %in% names(ensemble_variance))) {
    PEcAn.logger::logger.severe(
      "ensemble_variance must contain 'runid', 'site_id', and 'variable'."
    )
  }

  # compute local parameter fractions
  local_param_frac <- local_sa |>
    dplyr::mutate(
      total_partial_var = sum(.data$partial_variance, na.rm = TRUE),
      local_param_frac = dplyr::if_else(
        .data$total_partial_var > 0,
        .data$partial_variance / .data$total_partial_var,
        NA_real_
      ),
      .by = c("site_id", "response_var")
    ) |>
    dplyr::select("site_id", "response_var", "pft",
                  "parameter", "local_param_frac")

  # extract Var_parameter per runid * variable
  var_param_run <- variance_partition_site |>
    dplyr::filter(.data$category == "parameter") |>
    dplyr::select(
      "runid", "variable",
      Var_parameter = "Var_category",
      "Var_total"
    )

  # map runid -> site_id
  runid_site_lookup <- ensemble_variance |>
    dplyr::distinct(.data$runid, .data$site_id, .data$variable) |>
    dplyr::rename(response_var = "variable")

  var_param_site <- var_param_run |>
    dplyr::left_join(
      runid_site_lookup,
      by = c("runid", "variable" = "response_var")
    )

  # join local SA fractions and scale
  var_param_site |>
    dplyr::rename(response_var = "variable") |>
    dplyr::left_join(
      local_param_frac,
      by = c("site_id", "response_var")
    ) |>
    dplyr::mutate(
      Var_parameter_param = .data$local_param_frac * .data$Var_parameter,
      frac_of_total = dplyr::if_else(
        .data$Var_total > 0,
        .data$Var_parameter_param / .data$Var_total,
        NA_real_
      )
    ) |>
    dplyr::arrange(.data$site_id, .data$response_var,
                    .data$parameter, .data$pft)
}


#' Read CSV with file-existence guard
#'
#' @param path Path to CSV file.
#' @param ... Additional arguments passed to [readr::read_csv()].
#' @return Tibble of CSV contents.
safe_read_csv <- function(path, ...) {
  if (!file.exists(path)) {
    PEcAn.logger::logger.severe("File not found: ", path)
  }
  readr::read_csv(path, show_col_types = FALSE, ...)
}


#' Generate variance partition plots
#'
#' Creates three types of plots for each output variable:
#' 1. Stacked bar chart of variance fractions by category per site
#' 2. Mean variance fractions across all sites
#' 3. Top 15 parameters contributing to parameter variance
#'
#' @param variance_partition_site Tibble from partition_variance_sources().
#' @param param_summary Tibble of parameter-level summary statistics.
#' @param plots_dir Directory to save PNG files.
#' @param category_levels Character vector of category factor levels for ordering.
create_variance_plots <- function(variance_partition_site,
                                  param_summary,
                                  plots_dir,
                                  category_levels = c("parameter", "IC", "driver",
                                                      "management", "dummy")) {
  if (!dir.exists(plots_dir)) {
    dir.create(plots_dir, recursive = TRUE)
  }

  variables <- unique(variance_partition_site$variable)

  for (var in variables) {
    # plot 1: Stacked bar chart per site
    plot_data <- variance_partition_site |>
      dplyr::filter(
        .data$variable == var,
        .data$category != "interaction"
      ) |>
      dplyr::mutate(
        category = factor(.data$category, levels = category_levels)
      )

    p1 <- ggplot2::ggplot(
      plot_data,
      ggplot2::aes(x = .data$runid, y = .data$frac_of_total, fill = .data$category)
    ) +
      ggplot2::geom_col(position = "stack") +
      ggplot2::scale_fill_brewer(palette = "Set2", name = "Uncertainty source") +
      ggplot2::labs(
        title = paste("Variance partition by category:", var),
        subtitle = "Stacked by runid (site)",
        x = "Run ID (Site)",
        y = "Fraction of total variance"
      ) +
      ggplot2::theme_minimal() +
      ggplot2::theme(
        axis.text.x = ggplot2::element_text(angle = 45, hjust = 1, size = 8),
        legend.position = "bottom"
      )

    ggplot2::ggsave(
      file.path(plots_dir, paste0("variance_partition_stacked_", var, ".png")),
      p1, width = 10, height = 6, dpi = 300
    )

    # plot 2: Mean fractions across all sites
    mean_fracs <- variance_partition_site |>
      dplyr::filter(
        .data$variable == var,
        .data$category != "interaction"
      ) |>
      dplyr::summarize(
        mean_frac = mean(.data$frac_of_total, na.rm = TRUE),
        sd_frac = sd(.data$frac_of_total, na.rm = TRUE),
        .by = "category"
      ) |>
      dplyr::mutate(
        category = factor(.data$category, levels = category_levels)
      )

    p2 <- ggplot2::ggplot(
      mean_fracs,
      ggplot2::aes(x = .data$category, y = .data$mean_frac, fill = .data$category)
    ) +
      ggplot2::geom_col() +
      ggplot2::geom_errorbar(
        ggplot2::aes(
          ymin = .data$mean_frac - .data$sd_frac,
          ymax = .data$mean_frac + .data$sd_frac
        ),
        width = 0.2
      ) +
      ggplot2::scale_fill_brewer(palette = "Set2", guide = "none") +
      ggplot2::labs(
        title = paste("Mean variance partition:", var),
        subtitle = "Averaged across all sites with +/-1 SD",
        x = "Uncertainty source",
        y = "Mean fraction of total variance"
      ) +
      ggplot2::theme_minimal() +
      ggplot2::theme(axis.text.x = ggplot2::element_text(angle = 45, hjust = 1))

    ggplot2::ggsave(
      file.path(plots_dir, paste0("variance_partition_mean_", var, ".png")),
      p2, width = 8, height = 6, dpi = 300
    )

    # plot 3: Top 15 parameters
    top_params <- param_summary |>
      dplyr::filter(.data$response_var == var) |>
      dplyr::slice_head(n = 15)

    if (nrow(top_params) > 0) {
      p3 <- ggplot2::ggplot(
        top_params,
        ggplot2::aes(
          x = reorder(.data$parameter, .data$mean_frac),
          y = .data$mean_frac
        )
      ) +
        ggplot2::geom_col(fill = "steelblue") +
        ggplot2::geom_errorbar(
          ggplot2::aes(
            ymin = .data$mean_frac - .data$sd_frac,
            ymax = .data$mean_frac + .data$sd_frac
          ),
          width = 0.2
        ) +
        ggplot2::coord_flip() +
        ggplot2::labs(
          title = paste("Top 15 Parameters contributing to", var, "variance"),
          subtitle = "Mean fraction of total variance +/-1 SD",
          x = "Parameter",
          y = "Mean fraction of total variance"
        ) +
        ggplot2::theme_minimal()

      ggplot2::ggsave(
        file.path(plots_dir, paste0("variance_partition_top_params_", var, ".png")),
        p3, width = 10, height = 8, dpi = 300
      )
    }
  }
}

.data <- rlang::.data
