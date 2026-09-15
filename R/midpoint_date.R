#' Compute the midpoint of a date range
#'
#' Cal/val managements rows often record the date of an event as a
#' `min_date`/`max_date` window when only a seasonal estimate is known
#' (e.g. "spring compost" -> 2004-04-01..2004-06-01). Per David's MVP
#' rule, downstream pipelines should collapse such ranges to their
#' midpoint before emitting events.json.
#'
#' Vectorised over its inputs. If `min_date == max_date`, returns that
#' date unchanged (no rounding error). If either input is `NA`, returns
#' the non-`NA` one (or `NA` if both are missing).
#'
#' @param min_date Earliest plausible date (character ISO YYYY-MM-DD or Date).
#' @param max_date Latest plausible date (character ISO YYYY-MM-DD or Date).
#' @return A character vector of ISO YYYY-MM-DD midpoints (one per input pair).
#' @export
midpoint_date <- function(min_date, max_date) {
  min_d <- as.Date(min_date)
  max_d <- as.Date(max_date)

  out <- as.Date(rep(NA, length(min_d)))
  both_na  <- is.na(min_d) & is.na(max_d)
  only_min <- !is.na(min_d) & is.na(max_d)
  only_max <- is.na(min_d) & !is.na(max_d)
  both     <- !is.na(min_d) & !is.na(max_d)

  out[only_min] <- min_d[only_min]
  out[only_max] <- max_d[only_max]
  out[both] <- as.Date(
    floor((as.numeric(min_d[both]) + as.numeric(max_d[both])) / 2),
    origin = "1970-01-01"
  )
  out[both_na] <- NA

  format(out, "%Y-%m-%d")
}
