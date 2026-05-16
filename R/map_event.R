#' Parse "key1=val1; key2=val2; ..." strings from attributes_keyvalue
#'
#' Returns a named character vector of values, or an empty named character
#' vector if the input is missing/empty.
#' @keywords internal
parse_kv <- function(s) {
  if (is.null(s) || length(s) == 0) return(stats::setNames(character(0), character(0)))
  if (is.na(s) || !nzchar(s)) return(stats::setNames(character(0), character(0)))
  pairs <- strsplit(s, "\\s*;\\s*")[[1]]
  pairs <- pairs[nzchar(pairs)]
  if (length(pairs) == 0) return(stats::setNames(character(0), character(0)))
  parts <- strsplit(pairs, "=", fixed = TRUE)
  has_eq <- vapply(parts, length, integer(1)) == 2
  parts <- parts[has_eq]
  if (length(parts) == 0) return(stats::setNames(character(0), character(0)))
  vals <- vapply(parts, function(p) trimws(p[[2]]), character(1))
  keys <- vapply(parts, function(p) trimws(p[[1]]), character(1))
  stats::setNames(vals, keys)
}

# UAN-32 / CAN-17 N speciation per Nichols 2024 (paper text).
# Fractions of *total N* (not mass fractions of solution).
.UAN32_FRAC <- c(nh4 = 7.75 / 32, no3 = 7.75 / 32, urea = 16.5 / 32)
.CAN17_FRAC <- c(nh4 = 5.4 / 17,  no3 = 11.6 / 17, urea = 0)

# Convert reported `level + units` to kg m^-2 for fertilization events.
# Returns NA if units are unrecognised.
.to_kg_per_m2 <- function(level, units) {
  if (is.na(level) || is.na(units)) return(NA_real_)
  level <- as.numeric(level)
  if (is.na(level)) return(NA_real_)
  u <- tolower(trimws(units))
  if (grepl("mg ha-1", u, fixed = TRUE) || grepl("dry t ha-1", u, fixed = TRUE)) {
    return(level * 0.1)
  }
  if (grepl("kg n ha-1", u, fixed = TRUE) || grepl("kg ha-1", u, fixed = TRUE)) {
    return(level * 1e-4)
  }
  NA_real_
}

# Map our internal mgmttype to the events_schema_v0.1.1 event_type enum.
.event_type_for <- function(mgmttype) {
  switch(
    as.character(mgmttype),
    planting             = "planting",
    harvest              = "harvest",
    tillage              = "tillage",
    fertilization        = "fertilization",
    compost_application  = "fertilization",
    cover_crop_planting  = "planting",
    NA_character_
  )
}

#' Map one managements row to one events.json event element
#'
#' Translates a single row from the cal/val managements tab into a list
#' that conforms to the per-event object in PEcAn's
#' `events_schema_v0.1.1.json`. Required fields the data does not yet
#' provide (`leaf_c_kg_m2`, `frac_above_removed_0to1`,
#' `tillage_eff_0to1`) are returned as `NA` so the prior-sampling stage
#' can fill them later.
#'
#' @param row Named list / single-row tibble from the managements tab.
#' @param fertilizer Default fertilizer formulation when N events do not
#'   specify; one of `"uan_32"` (default) or `"can_17"`. Used by the
#'   Nichols 2024 fertigation rows where the source data lumps
#'   "UAN_32 or CAN_17" without per-event resolution.
#' @return A list representing one event, or `NULL` if the row's
#'   `mgmttype` cannot be mapped.
#' @export
map_event <- function(row, fertilizer = c("uan_32", "can_17")) {
  fertilizer <- match.arg(fertilizer)
  row <- as.list(row)

  ev_type <- .event_type_for(row$mgmttype)
  if (is.na(ev_type)) return(NULL)

  date <- midpoint_date(row$min_date, row$max_date)
  attrs <- parse_kv(row$attributes_keyvalue)

  out <- list(
    event_type = ev_type,
    date       = date
  )
  if (!is.null(row$citation) && !is.na(row$citation) && nzchar(row$citation)) {
    out$source <- row$citation
  }

  # NOTE on missing required schema fields: the v0.1.1 schema requires
  # `leaf_c_kg_m2` for planting, `frac_above_removed_0to1` for harvest,
  # and `tillage_eff_0to1` for tillage. These are NOT in the cal/val
  # data and will be injected by the prior-sampling stage. We omit them
  # here entirely (rather than writing `null`) so the JSON is well-formed
  # and the priors stage can simply add the fields. Validation against
  # the schema will therefore surface a known set of gaps until the
  # priors layer is wired in.

  if (ev_type == "planting") {
    out$crop_code    <- row$crop_name
    out$crop_display <- row$crop_name
    if (!is.null(row$cover_crop) && !is.na(row$cover_crop) &&
        toupper(row$cover_crop) == "TRUE") {
      out$cover_crop <- TRUE        # extra metadata; schema allows additionalProperties
    }
    return(out)
  }

  if (ev_type == "harvest") {
    if (!is.null(row$crop_name) && !is.na(row$crop_name)) out$crop_display <- row$crop_name
    return(out)
  }

  if (ev_type == "tillage") {
    if ("implement" %in% names(attrs)) out$intensity_category <- attrs[["implement"]]
    if (!is.na(suppressWarnings(as.numeric(row$level)))) {
      val <- as.numeric(row$level)
      u <- tolower(trimws(if (is.null(row$units)) "" else as.character(row$units)))
      if (grepl("cm", u, fixed = TRUE))      out$depth_m <- val * 0.01
      else if (grepl("\\bm\\b", u))           out$depth_m <- val
    }
    return(out)
  }

  if (ev_type == "fertilization") {
    is_compost <- isTRUE(row$mgmttype == "compost_application") ||
      grepl("compost|manure|organic", as.character(row$units), ignore.case = TRUE) ||
      ("material" %in% names(attrs) && grepl("compost|manure",
                                             attrs[["material"]], ignore.case = TRUE))
    amount <- .to_kg_per_m2(row$level, row$units)

    if (is_compost && !is.na(amount)) {
      # Compost: derive C and N from attributes when present, else use
      # Akash's defaults (carbon_fraction = 0.35, cn_ratio inferred from
      # PEcAn fertilizer_composition_data later via priors stage).
      if ("compost_C_pct" %in% names(attrs)) {
        out$org_c_kg_m2 <- amount * as.numeric(attrs[["compost_C_pct"]]) / 100
      } else {
        out$org_c_kg_m2 <- amount * 0.35
      }
      if ("compost_N_pct" %in% names(attrs)) {
        out$org_n_kg_m2 <- amount * as.numeric(attrs[["compost_N_pct"]]) / 100
      } else if ("CN_ratio" %in% names(attrs) && !is.null(out$org_c_kg_m2)) {
        out$org_n_kg_m2 <- out$org_c_kg_m2 / as.numeric(attrs[["CN_ratio"]])
      } else if ("N_content_g_kg" %in% names(attrs)) {
        # 15 g N / kg compost = 1.5% N
        out$org_n_kg_m2 <- amount * as.numeric(attrs[["N_content_g_kg"]]) / 1000
      }
      return(out)
    }

    # Mineral N event. Look for explicit fertilizer_type, else fall back
    # to function default.
    n_total <- amount   # kg N m-2
    if (is.na(n_total)) return(out)   # no amount; let priors handle later

    fert_kind <- if ("fertilizer_type" %in% names(attrs)) attrs[["fertilizer_type"]]
                 else fertilizer
    fert_kind <- tolower(trimws(fert_kind))
    if (grepl("uan", fert_kind))      frac <- .UAN32_FRAC
    else if (grepl("can", fert_kind)) frac <- .CAN17_FRAC
    else                              frac <- .UAN32_FRAC   # safe default

    out$nh4_n_kg_m2 <- n_total * frac[["nh4"]]
    out$no3_n_kg_m2 <- n_total * frac[["no3"]]
    if (frac[["urea"]] > 0) out$org_n_kg_m2 <- n_total * frac[["urea"]]
    return(out)
  }

  out
}

#' Map all rows for a single treatment
#'
#' @param mgmt Tibble of managements rows (already filtered to one
#'   `treatments.name`).
#' @inheritParams map_event
#' @return A list of event lists, in the order the rows appeared.
#' @export
map_events_for_treatment <- function(mgmt, fertilizer = "uan_32") {
  events <- vector("list", nrow(mgmt))
  for (i in seq_len(nrow(mgmt))) {
    events[[i]] <- map_event(mgmt[i, , drop = FALSE], fertilizer = fertilizer)
  }
  Filter(Negate(is.null), events)
}
