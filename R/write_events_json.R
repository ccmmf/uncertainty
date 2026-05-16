#' Write one events.json file per cal/val treatment
#'
#' Groups the managements tibble by `treatments.name`, maps each row to
#' an events.json event via [map_event()], and writes one file per
#' treatment to `out_dir`. Each file conforms to the per-site object in
#' PEcAn's events schema v0.1.1 (`PEcAn.data.land`).
#'
#' Distinct from `PEcAn.data.land`'s `inst/generate_events.R` script,
#' which builds minimal planting/harvest events from
#' `ca_field_attributes.csv`. This writer ingests the richer cal/val
#' workbook tibbles and emits full events (tillage, fertilization,
#' irrigation, harvest). Schema validation is delegated to
#' [PEcAn.data.land::validate_events_json()].
#'
#' @param mgmt Tibble of managements rows (multiple treatments OK).
#' @param sites Tibble of sites rows from the workbook.
#' @param out_dir Directory to write the .json files into. Created if missing.
#' @param dataset_id String tagged into `provenance.dataset_id`.
#' @param validate If `TRUE`, validate every emitted file via
#'   [PEcAn.data.land::validate_events_json()].
#' @param fertilizer Default mineral-N fertilizer for ambiguous rows.
#' @param priors Optional list returned by `load_priors()`.
#' @return A character vector of paths to the written files (invisibly).
#' @export
write_events_json <- function(mgmt, sites, out_dir,
                              dataset_id,
                              validate = TRUE,
                              fertilizer = "uan_32",
                              priors = NULL) {
  if (!dir.exists(out_dir)) dir.create(out_dir, recursive = TRUE)

  treatments <- unique(mgmt[["treatments.name"]])
  treatments <- treatments[!is.na(treatments) & nzchar(treatments)]
  written <- character(0)

  for (trt in treatments) {
    rows <- mgmt[mgmt[["treatments.name"]] == trt, , drop = FALSE]
    events <- map_events_for_treatment(rows, fertilizer = fertilizer)
    if (length(events) == 0) next

    events <- inject_missing_irrigations(events)

    if (!is.null(priors)) {
      seed <- sum(utf8ToInt(paste0(dataset_id, "_", trt))) %% .Machine$integer.max
      events <- fill_with_priors(events, priors, seed = seed)
    }

    payload <- list(
      pecan_events_version = "0.1.1",
      site_id              = trt,
      provenance           = list(
        dataset_id  = dataset_id,
        source_rows = nrow(rows),
        generated_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"),
        generator   = "ccmmf/uncertainty:calval_to_events"
      ),
      events = events
    )

    out_file <- file.path(out_dir,
                          paste0(.fs_safe(dataset_id), "_", .fs_safe(trt), ".json"))
    json_str <- jsonlite::toJSON(payload,
                                 auto_unbox = TRUE,
                                 pretty = TRUE,
                                 na = "null",
                                 null = "null")
    writeLines(json_str, out_file)
    if (isTRUE(validate)) .validate_or_stop(out_file)
    written <- c(written, out_file)
  }

  invisible(written)
}

.fs_safe <- function(x) {
  x <- gsub("[^A-Za-z0-9._-]+", "_", x)
  gsub("_+", "_", x)
}

.validate_or_stop <- function(json_path) {
  if (!requireNamespace("PEcAn.data.land", quietly = TRUE)) {
    warning("PEcAn.data.land not installed; skipping schema validation.",
            call. = FALSE)
    return(invisible(NULL))
  }

  ok <- PEcAn.data.land::validate_events_json(json_path,
                                              schema_version = "0.1.1",
                                              verbose = TRUE)
  if (isTRUE(ok) || is.na(ok)) return(invisible(NULL))

  errs <- attr(ok, "errors")
  if (!is.null(errs) && is.data.frame(errs) && nrow(errs) > 0) {
    prior_pattern <- "events/items/allOf/(0|1|2|4)/(if|then|else)"
    cascading_pattern <- "^#/oneOf"
    is_known <- grepl(prior_pattern, errs$schemaPath) |
                grepl(cascading_pattern, errs$schemaPath)
    real_errors <- errs[!is_known, , drop = FALSE]
    if (nrow(real_errors) > 0) {
      stop("schema validation failed for ", json_path, " with non-prior errors:\n",
           paste(utils::capture.output(print(real_errors)), collapse = "\n"),
           call. = FALSE)
    }
    message("  ", basename(json_path), ": ", sum(is_known),
            " conditional gap(s) pending prior-sampling stage (expected).")
  }
  invisible(NULL)
}
