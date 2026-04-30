#' Fill schema-required fields that the cal/val data does not specify.
#'
#' The cal/val workbook does not record values for a handful of fields
#' that the events.json schema requires for certain event types
#' (`leaf_c_kg_m2` for plantings, `frac_above_removed_0to1` for
#' harvests, `tillage_eff_0to1` for tillage, and `amount_mm` / `method`
#' for irrigations). Per David's MVP plan, this function samples those
#' fields from prior distributions defined in Akash's
#' `management_priors.yaml` (vendored at `inst/akash_priors/`).
#'
#' Sampling uses a per-treatment seed derived from the treatment name so
#' the same input always yields the same output (matters for diffing
#' and CI). When the priors are upgraded to ensembles, callers will
#' override `seed` to vary per ensemble member.
#'
#' @param events A list of event objects (already produced by
#'   [map_events_for_treatment()]).
#' @param priors The list returned by Akash's `load_priors()`.
#' @param seed Integer; seeds R's RNG before sampling so output is
#'   reproducible.
#' @return The events list with previously-missing required fields
#'   populated.
#' @export
fill_with_priors <- function(events, priors, seed = 0L) {
  set.seed(seed)
  for (i in seq_along(events)) {
    events[[i]] <- .fill_event(events[[i]], priors)
  }
  events
}

# Mapping from event_type to (practice_path, parameter_name).
# practice_path is a vector of keys to descend into the priors list.
.PRIOR_FIELD_MAP <- list(
  planting = list(
    field        = "leaf_c_kg_m2",
    practice_path = c("crop_baselines", "processing_tomato",
                      "events", "planting"),
    param_key    = "leaf_c_kg_m2"
  ),
  harvest = list(
    field        = "frac_above_removed_0to1",
    practice_path = c("practices", "harvest_grain", "parameters"),
    param_key    = "frac_above_removed_0to1"
  ),
  tillage = list(
    field        = "tillage_eff_0to1",
    practice_path = c("practices", "conventional_tillage", "parameters"),
    param_key    = "tillage_eff_0to1"
  ),
  irrigation = list(
    field        = "amount_mm",
    practice_path = c("practices", "irrigation_sprinkler", "parameters"),
    param_key    = "seasonal_total_mm"   # divided by n_events later
  )
)

.fill_event <- function(event, priors) {
  spec <- .PRIOR_FIELD_MAP[[event$event_type]]
  if (is.null(spec)) return(event)            # nothing to fill
  if (!is.null(event[[spec$field]])) return(event)   # already set

  dist_spec <- .descend(priors, c(spec$practice_path, spec$param_key))
  if (is.null(dist_spec)) return(event)

  sample <- sample_distribution(dist_spec, n = 1)
  event[[spec$field]] <- as.numeric(sample)

  # Tag the event so consumers can tell which fields came from priors.
  source_log <- if (!is.null(event$source)) event$source else ""
  prior_note <- paste0(spec$field, "<-prior:",
                       paste(spec$practice_path, collapse = "/"))
  event$prior_filled <- if (is.null(event$prior_filled)) prior_note
                        else paste(event$prior_filled, prior_note, sep = "; ")

  # Irrigation also needs `method`; pick canopy for sprinkler systems.
  if (event$event_type == "irrigation" && is.null(event$method)) {
    event$method <- "canopy"
  }
  event
}

# Walk a nested list along a key path, returning NULL if any step fails.
.descend <- function(x, keys) {
  for (k in keys) {
    if (is.null(x) || !k %in% names(x)) return(NULL)
    x <- x[[k]]
  }
  x
}
