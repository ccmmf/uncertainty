# Build per-sample management events from Sobol design.
#
# Translates sampled quantile values into PEcAn events JSON.
# JSON is then converted to SIPNET events.in by write.events.SIPNET().
#
# Current scope: N fertilizer + compost (NCC).
# Other events pass through from baseline unchanged.
# TODO activate tillage/planting/harvest/irrigation when MF delivers priors.

#' Build events list for one Sobol sample
#'
#' @param mgmt_row Named list of physical mgmt values (not quantiles).
#' @param baseline_events List of baseline event lists (from events.json).
#' @param years Integer vector of simulation years.
#' @param site_id Character site ID.
#' @param event_config List of event timing overrides.
#' @return List suitable for jsonlite::write_json() (PEcAn events schema).
build_sample_events <- function(mgmt_row,
                                baseline_events,
                                years,
                                site_id,
                                event_config = list()) {

  baseline_by_type <- split_events_by_type(baseline_events)
  all_events <- list()

  # fertilization -- active (priors from UC ANR Pub 3470 + CDFA HSP)
  has_fert <- all(
    c("mgmt.nh4_n_kg_m2", "mgmt.org_c_kg_m2", "mgmt.cn_ratio") %in% names(mgmt_row)
  )
  if (has_fert) {
    all_events <- c(all_events, build_fertilization_events(
      nh4_n_kg_m2 = mgmt_row[["mgmt.nh4_n_kg_m2"]],
      org_c_kg_m2 = mgmt_row[["mgmt.org_c_kg_m2"]],
      cn_ratio    = mgmt_row[["mgmt.cn_ratio"]],
      years       = years,
      compost_doy = event_config$compost_doy %||% 51L,
      synth_n_doy = event_config$synth_n_doy %||% 85L
    ))
  } else {
    all_events <- c(all_events,
      filter_events_to_years(baseline_by_type$fertilization, years))
  }

  # deferred event types -- pass through from baseline unchanged
  # TODO activate each when MF delivers the corresponding priors:
  #   tillage -> NDTI-based intensity
  #   planting -> EVI2 phenology dates
  #   harvest -> EVI2 harvest detection
  #   irrigation -> CIMIS/CHIRPS water balance
  deferred <- c("tillage", "planting", "harvest", "irrigation", "cover_crop")
  for (etype in deferred) {
    if (length(baseline_by_type[[etype]]) > 0) {
      all_events <- c(all_events,
        filter_events_to_years(baseline_by_type[[etype]], years))
    }
  }

  # pass through any other baseline event types unchanged
  known_types <- c("fertilization", deferred)
  for (otype in setdiff(names(baseline_by_type), known_types)) {
    all_events <- c(all_events,
      filter_events_to_years(baseline_by_type[[otype]], years))
  }

  # sort chronologically
  event_dates <- as.Date(vapply(all_events, `[[`, character(1), "date"))
  all_events <- all_events[order(event_dates)]

  list(site_id = site_id, events = all_events)
}


#' Split baseline events by event_type
#' @param events List of event lists.
#' @return Named list of lists, keyed by event_type.
split_events_by_type <- function(events) {
  if (length(events) == 0) return(list())
  types <- vapply(events, \(e) e$event_type, character(1))
  split(events, types)
}


#' Filter baseline events to simulation years
#'
#' If baseline spans multiple years, filters to keep only events in `years`.
#' If baseline is a single-year template, replicates across `years`.
#'
#' @param events List of event lists from baseline.
#' @param years Integer vector of simulation years.
#' @return Filtered/replicated event lists.
filter_events_to_years <- function(events, years) {
  if (length(events) == 0) return(list())

  event_years <- as.integer(
    vapply(events, \(e) format(as.Date(e$date), "%Y"), character(1))
  )

  if (length(unique(event_years)) > 1) {
    events[event_years %in% years]
  } else {
    replicate_events_across_years(events, years)
  }
}


#' Replicate single-year template events across simulation years
#' @param template_events List of events from one template year.
#' @param years Integer vector of simulation years.
#' @return Event lists spanning all years, chronologically ordered.
replicate_events_across_years <- function(template_events, years) {
  if (length(template_events) == 0) return(list())

  out <- vector("list", length(template_events) * length(years))
  idx <- 0L
  for (yr in years) {
    for (evt in template_events) {
      idx <- idx + 1L
      new_evt <- evt
      orig_date <- as.Date(evt$date)
      new_evt$date <- sprintf("%d-%s", yr, format(orig_date, "%m-%d"))
      out[[idx]] <- new_evt
    }
  }
  out[seq_len(idx)]
}


#' Build fertilization events for one sample
#'
#' Creates compost (organic C + N) and synthetic N events per year.
#' Field names follow PEcAn events schema v0.1.0:
#'   nh4_n_kg_m2 -> SIPNET minN (mineral nitrogen)
#'   org_c_kg_m2 -> SIPNET orgC (organic carbon to litter)
#'   org_n_kg_m2 -> SIPNET orgN (organic nitrogen to litter)
#'
#' @param nh4_n_kg_m2 Synthetic N rate (kg N / m2).
#' @param org_c_kg_m2 Compost organic C rate (kg C / m2).
#' @param cn_ratio Compost C:N ratio (dimensionless).
#' @param years Integer vector of simulation years.
#' @param compost_doy DOY for compost application (default 51 = Feb 20).
#' @param synth_n_doy DOY for synthetic N application (default 85 = Mar 26).
#' @return List of event lists (2 per year).
build_fertilization_events <- function(nh4_n_kg_m2,
                                       org_c_kg_m2,
                                       cn_ratio,
                                       years,
                                       compost_doy = 51L,
                                       synth_n_doy = 85L) {
  org_n_kg_m2 <- org_c_kg_m2 / cn_ratio
  out <- vector("list", 2L * length(years))
  idx <- 0L

  for (yr in years) {
    jan1 <- as.Date(sprintf("%d-01-01", yr))

    # compost -- organic C and N to surface litter pools
    idx <- idx + 1L
    out[[idx]] <- list(
      event_type  = "fertilization",
      date        = format(jan1 + (compost_doy - 1L), "%Y-%m-%d"),
      org_c_kg_m2 = round(org_c_kg_m2, 6),
      org_n_kg_m2 = round(org_n_kg_m2, 6),
      nh4_n_kg_m2 = 0.0
    )

    # synthetic N -- inorganic NH4 to mineral N pool
    idx <- idx + 1L
    out[[idx]] <- list(
      event_type  = "fertilization",
      date        = format(jan1 + (synth_n_doy - 1L), "%Y-%m-%d"),
      org_c_kg_m2 = 0.0,
      org_n_kg_m2 = 0.0,
      nh4_n_kg_m2 = round(nh4_n_kg_m2, 6)
    )
  }
  out[seq_len(idx)]
}


#' Build tillage events for one sample (stub)
#' @param tillage_doy DOY for tillage.
#' @param tillage_intensity NDTI-based intensity (0-1, from NRCS STIR / 200).
#' @param years Integer vector of simulation years.
#' @return List of event lists (1 per year).
build_tillage_events <- function(tillage_doy, tillage_intensity, years) {
  purrr::map(years, \(yr) {
    jan1 <- as.Date(sprintf("%d-01-01", yr))
    list(
      event_type       = "tillage",
      date             = format(jan1 + (as.integer(tillage_doy) - 1L), "%Y-%m-%d"),
      tillage_eff_0to1 = round(tillage_intensity, 4)
    )
  })
}


#' Build planting events for one sample (stub)
#' @param plant_doy DOY for planting (from EVI2 15% greenness).
#' @param plant_biomass Leaf biomass at planting (kg C / m2).
#' @param years Integer vector of simulation years.
#' @return List of event lists (1 per year).
build_planting_events <- function(plant_doy, plant_biomass, years) {
  purrr::map(years, \(yr) {
    jan1 <- as.Date(sprintf("%d-01-01", yr))
    list(
      event_type   = "planting",
      date         = format(jan1 + (as.integer(plant_doy) - 1L), "%Y-%m-%d"),
      leaf_c_kg_m2 = round(plant_biomass, 6)
    )
  })
}


#' Build harvest events for one sample (stub)
#' @param harvest_doy DOY for harvest (from EVI2 harvest detection).
#' @param harvest_fraction Fraction of aboveground biomass removed (0-1).
#' @param years Integer vector of simulation years.
#' @return List of event lists (1 per year).
build_harvest_events <- function(harvest_doy, harvest_fraction, years) {
  purrr::map(years, \(yr) {
    jan1 <- as.Date(sprintf("%d-01-01", yr))
    list(
      event_type              = "harvest",
      date                    = format(jan1 + (as.integer(harvest_doy) - 1L), "%Y-%m-%d"),
      frac_above_removed_0to1 = round(harvest_fraction, 4),
      frac_below_removed_0to1 = 0.0
    )
  })
}
