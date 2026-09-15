#' Inject irrigation events for irrigated cropping systems that lack them
#'
#' Some cal/val datasets (notably White/Salinas 2020) record plantings,
#' harvests, tillage and fertilization but never write a row for
#' irrigation, even though the crops involved are clearly irrigated.
#' Per David's plan: detect those gaps and inject placeholder
#' `irrigation` events into the per-treatment events list before the
#' priors stage fills in `amount_mm` and `method`.
#'
#' MVP heuristic — for each treatment:
#'   1. If it already has any `irrigation` events, leave it alone.
#'   2. Otherwise, find pairs of cash-crop plantings and harvests
#'      (`cover_crop` not set / FALSE) and inject one placeholder
#'      irrigation event at the midpoint of each window.
#'   3. The placeholder carries a `prior_filled` tag so consumers can
#'      see the field came from gap-filling, not source data.
#'
#' Distributing the right *count* of irrigation events across the
#' planting/harvest window (using the `n_events` prior) is left for a
#' follow-up that will also consume `seasonal_total_mm / n_events` for
#' the per-event amount. For MVP, one placeholder per window is enough
#' to make the events.json schema-valid; the priors stage fills
#' `amount_mm` from `seasonal_total_mm` directly.
#'
#' @param events List of events for one treatment (from
#'   [map_events_for_treatment()]).
#' @return The events list, possibly with new `irrigation` entries.
#' @export
inject_missing_irrigations <- function(events) {
  if (length(events) == 0) return(events)

  has_irrigation <- any(vapply(events, function(e) identical(e$event_type, "irrigation"),
                               logical(1)))
  if (has_irrigation) return(events)

  is_planting <- vapply(events, function(e) identical(e$event_type, "planting"),
                        logical(1))
  is_harvest  <- vapply(events, function(e) identical(e$event_type, "harvest"),
                        logical(1))
  is_cover    <- vapply(events, function(e) isTRUE(e$cover_crop), logical(1))

  cash_plantings <- which(is_planting & !is_cover)
  cash_harvests  <- which(is_harvest  & !is_cover)
  if (length(cash_plantings) == 0 || length(cash_harvests) == 0) return(events)

  # Pair each planting with the next harvest of the same crop, where
  # "next" means earliest harvest after the planting date with a
  # matching crop_display (best-effort; falls back to date order).
  injected <- list()
  for (pi in cash_plantings) {
    p <- events[[pi]]
    p_date <- as.Date(p$date)
    p_crop <- p$crop_display %||% p$crop_code

    after <- cash_harvests[vapply(cash_harvests, function(hi) {
      h <- events[[hi]]
      h_crop <- h$crop_display %||% h$crop_code
      isTRUE(as.Date(h$date) > p_date) &&
        (is.null(p_crop) || is.null(h_crop) || p_crop == h_crop)
    }, logical(1))]
    if (length(after) == 0) next

    h <- events[[after[which.min(as.Date(vapply(after, function(i) events[[i]]$date,
                                                character(1))))]]]
    mid <- as.Date(floor((as.numeric(as.Date(p$date)) +
                          as.numeric(as.Date(h$date))) / 2),
                   origin = "1970-01-01")

    injected[[length(injected) + 1L]] <- list(
      event_type = "irrigation",
      date       = format(mid, "%Y-%m-%d"),
      source     = p$source %||% h$source,
      injected_by = "detect_missing_events:cash_crop_window_midpoint",
      cover_crop_window = FALSE
    )
  }

  if (length(injected) == 0) return(events)

  # Append in chronological order with the rest. Stable sort by date.
  combined <- c(events, injected)
  ord <- order(vapply(combined, function(e) as.Date(e$date), as.Date(NA)))
  combined[ord]
}

`%||%` <- function(a, b) if (is.null(a) || (is.character(a) && !nzchar(a))) b else a
