# Map design-point sites to crop-specific N and compost ranges.
#
# Bridges LandIQ v3 parquet + CARB PFT table + crop crosswalk +
# PEcAn.data.land lookup functions to produce a per-site tibble
# consumed by 023_generate_management_events.R.

#' Resolve per-site crop identity with N and compost ranges
#'
#' @param design_points_csv Path to design_points_198.csv
#' @param landiq_parquet Path to LandIQ crops_all_years.parq
#' @param pft_table_csv Path to CARB_PFTs_table.csv
#' @param crosswalk_csv Path to crop_type_crosswalk.csv
#' @param year LandIQ survey year (default 2023, most recent).
#'   NB crop identity assumed constant - simplification for rotations.
#'   TODO use per-year LandIQ when rotation data is available.
#' @param season LandIQ season (default 2 = summer crop).
#' @param compost_material Compost type for look_up_ca_compost_amendment().
#'   Default "Cow manure" - most common amendment in CA row crop ag.
#'   TODO make per crop when crop specific compost data is available.
#' @return Tibble with N rate + compost columns per site.
get_site_crop_info <- function(design_points_csv,
                               landiq_parquet,
                               pft_table_csv,
                               crosswalk_csv,
                               year = 2023L,
                               season = 2L,
                               compost_material = "Cow manure") {

  dp <- readr::read_csv(design_points_csv, show_col_types = FALSE)
  dp$uid_padded <- sprintf("%07d", as.integer(dp$UniqueID))

  if (!requireNamespace("arrow", quietly = TRUE)) {
    PEcAn.logger::logger.severe(
      "Package 'arrow' is required to read LandIQ parquet files. ",
      "Install with: install.packages('arrow')"
    )
  }

  crops <- arrow::read_parquet(landiq_parquet) |>
    dplyr::filter(.data$year == .env$year, .data$season == .env$season) |>
    dplyr::select("UniqueID", "CLASS", "SUBCLASS")

  crops <- dplyr::distinct(crops, .data$UniqueID, .keep_all = TRUE)

  pft_tbl <- readr::read_csv(pft_table_csv, show_col_types = FALSE) |>
    dplyr::select("crop_type", "crop_code", "crop_desc", "pft_group") |>
    dplyr::mutate(crop_code = as.character(.data$crop_code))

  crosswalk <- readr::read_csv(crosswalk_csv, show_col_types = FALSE)

  matched <- dplyr::left_join(dp, crops, by = c("uid_padded" = "UniqueID"))
  matched <- dplyr::left_join(
    matched, pft_tbl,
    by = c("CLASS" = "crop_type", "SUBCLASS" = "crop_code")
  )
  matched <- dplyr::left_join(
    matched, crosswalk,
    by = c("crop_desc" = "landiq"),
    suffix = c("", "_xwalk")
  )
  matched$lookup_name <- dplyr::coalesce(
    matched$uc_anr, matched$frep, matched$crop_desc
  )

  # compost ranges from look_up_ca_compost_amendment()
  compost_dat <- PEcAn.data.land::look_up_ca_compost_amendment(compost_material)
  if (nrow(compost_dat) == 0) {
    PEcAn.logger::logger.severe(
      "No compost data for '", compost_material, "'"
    )
  }
  # select widest C:N range row for the material
  compost_row <- compost_dat[which.max(compost_dat$cn_max - compost_dat$cn_min), ]

  # N rate per site
  result <- purrr::pmap_dfr(
    list(
      site_id   = matched$site_id,
      uid       = matched$uid_padded,
      pft_orig  = matched$pft,
      crop_name = matched$lookup_name,
      pft_grp   = matched$pft_group
    ),
    function(site_id, uid, pft_orig, crop_name, pft_grp) {
      empty_row <- tibble::tibble(
        site_id = site_id, UniqueID = uid, pft = pft_orig,
        crop_name = crop_name,
        pft_group = pft_grp %||% NA_character_,
        min_n_g_m2 = NA_real_, max_n_g_m2 = NA_real_,
        lookup_source = "unmatched"
      )
      if (is.na(crop_name)) return(empty_row)

      rate <- suppressWarnings(
        PEcAn.data.land::look_up_ca_n_rate(crop_name, unit = "g_m2")
      )
      if (nrow(rate) == 0) {
        empty_row$lookup_source <- "no_rate"
        return(empty_row)
      }

      tibble::tibble(
        site_id = site_id, UniqueID = uid, pft = pft_orig,
        crop_name = crop_name, pft_group = rate$pft_group[1],
        min_n_g_m2 = rate$min_n[1], max_n_g_m2 = rate$max_n[1],
        lookup_source = "crop_specific"
      )
    }
  )

  # fallback: pft-level medians, then global median
  needs_fallback <- is.na(result$min_n_g_m2)
  if (any(needs_fallback)) {
    pft_medians <- result |>
      dplyr::filter(!is.na(.data$min_n_g_m2)) |>
      dplyr::summarize(
        med_min = median(.data$min_n_g_m2),
        med_max = median(.data$max_n_g_m2),
        .by = "pft"
      )
    global_min <- median(result$min_n_g_m2, na.rm = TRUE)
    global_max <- median(result$max_n_g_m2, na.rm = TRUE)

    for (i in which(needs_fallback)) {
      pft_match <- pft_medians[pft_medians$pft == result$pft[i], ]
      if (nrow(pft_match) > 0) {
        result$min_n_g_m2[i] <- pft_match$med_min[1]
        result$max_n_g_m2[i] <- pft_match$med_max[1]
        result$lookup_source[i] <- "pft_fallback"
      } else {
        result$min_n_g_m2[i] <- global_min
        result$max_n_g_m2[i] <- global_max
        result$lookup_source[i] <- "global_fallback"
      }
    }
    PEcAn.logger::logger.warn(
      sum(needs_fallback), " of ", nrow(result),
      " sites used fallback N rates"
    )
  }

  # attach compost ranges
  result$compost_c_min_g_m2 <- compost_row$total_c_min_g_m2
  result$compost_c_max_g_m2 <- compost_row$total_c_max_g_m2
  result$compost_cn_min     <- compost_row$cn_min
  result$compost_cn_max     <- compost_row$cn_max
  result$compost_material   <- compost_material

  PEcAn.logger::logger.info(
    "Crop lookup: ", sum(result$lookup_source == "crop_specific"),
    " crop-specific, ",
    sum(result$lookup_source %in% c("pft_fallback", "global_fallback")),
    " fallback"
  )
  PEcAn.logger::logger.info(
    "Compost: ", compost_material,
    " (C: ", round(compost_row$total_c_min_g_m2, 1),
    "-", round(compost_row$total_c_max_g_m2, 1), " g/m2",
    ", C:N: ", compost_row$cn_min, "-", compost_row$cn_max, ")"
  )

  result
}
