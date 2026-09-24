#' Build one multi-site PEcAn settings object from a run table
#'
#' @description
#' Expands a template into one run block per row of the run table. Only `id`,
#' the location and the two PFTs are required; a pass whose sites share a run
#' window or follow a path convention supplies neither per-row windows nor
#' per-row input directories and gets them from `window` and `dirs` instead.
#' Every other column of the table is carried into `run$site` untouched, so a
#' pass can keep whatever grouping columns its analysis needs without those
#' becoming part of this contract.
#'
#' `id` is the run key. Each block writes its analysis output to a directory
#' named by it, which is what lets [aggregate_sa()] recover the run from the
#' path rather than from an ensemble-id lookup.
#'
#' @param sites Data frame, one row per run. Required: `id`, `lat`, `lon`,
#'   `veg_pft`, `soil_pft`. Optional: `run_start` and `run_end` (else `window`),
#'   and `met_src`, `ic_src`, `events_src` giving each input directory relative
#'   to `input_root` (else `dirs`).
#' @param template Path to the template XML.
#' @param input_root Root the input directories resolve against. Must also hold
#'   `pfts/<name>/post.distns.Rdata` for every PFT named in the table.
#' @param binary Path to the model executable.
#' @param outdir Directory the run tree is written to.
#' @param ensemble_size Maximum ensemble members to use per input. Fewer are
#'   used when fewer exist, which is why the members are read from disk rather
#'   than generated: met replication differs between sites.
#' @param window `list(start, end)` used for rows with no `run_start`/`run_end`.
#' @param dirs Named list of [glue::glue()] templates, one per input type, used
#'   for inputs with no `<type>_src` column. Resolved against the whole row, so
#'   `"met/{met_grid}"` works as well as `"met/{id}"`.
#' @return A PEcAn MultiSettings object.
#' @export
build_settings <- function(sites, template, input_root, binary, outdir,
                           ensemble_size = 20, window = NULL, dirs = NULL) {
  required <- c("id", "lat", "lon", "veg_pft", "soil_pft")
  missing_cols <- setdiff(required, names(sites))
  if (length(missing_cols) > 0) {
    PEcAn.logger::logger.severe("run table is missing columns: ",
                                paste(missing_cols, collapse = ", "))
  }
  if (nrow(sites) == 0) PEcAn.logger::logger.severe("run table is empty")
  if (anyDuplicated(sites$id)) {
    PEcAn.logger::logger.severe(
      "id must be unique; it is the run key every later step joins on. ",
      "duplicated: ",
      paste(unique(sites$id[duplicated(sites$id)]), collapse = ", ")
    )
  }
  for (p in c(template, binary, input_root)) {
    if (!file.exists(p)) PEcAn.logger::logger.severe("not found: ", p)
  }
  if (is.null(sites$run_start) || is.null(sites$run_end)) {
    if (is.null(window$start) || is.null(window$end)) {
      PEcAn.logger::logger.severe(
        "the run table has no run_start/run_end, so a window with start and ",
        "end is required"
      )
    }
    sites$run_start <- sites$run_start %||% window$start
    sites$run_end <- sites$run_end %||% window$end
  }

  # the directory holding one input type for one run, named by the table or
  # derived from a template against that row
  input_dir <- function(row, type) {
    rel <- row[[paste0(type, "_src")]]
    if (is.null(rel) || is.na(rel)) {
      if (is.null(dirs[[type]])) {
        PEcAn.logger::logger.severe(
          "run ", row$id, " has no ", type, "_src column and no dirs$", type,
          " template to derive one from"
        )
      }
      rel <- as.character(glue::glue_data(row, dirs[[type]]))
    }
    file.path(input_root, rel)
  }

  # ensemble members are read from disk rather than generated from a count:
  # replication is not the same at every site, and a generated path that does
  # not exist fails inside the model array where the only symptom is an empty
  # output directory
  member_paths <- function(dir, type, id) {
    if (!dir.exists(dir)) {
      PEcAn.logger::logger.severe("run ", id, " ", type, " not found: ", dir)
    }
    files <- list.files(dir, MEMBER_EXT[[type]], full.names = TRUE,
                        recursive = TRUE)
    if (length(files) == 0) {
      PEcAn.logger::logger.severe("run ", id, " has no ", type,
                                  " members matching ", MEMBER_EXT[[type]],
                                  " in ", dir)
    }
    # order by the replicate number in the name so member 10 follows 9
    n <- as.integer(sub(".*?(\\d+)[^0-9]*$", "\\1", basename(files)))
    files <- files[order(ifelse(is.na(n), seq_along(files), n))]
    files <- files[seq_len(min(length(files), ensemble_size))]
    stats::setNames(as.list(files), paste0("path", seq_along(files)))
  }

  for (p in sort(unique(c(sites$veg_pft, sites$soil_pft)))) {
    f <- file.path(input_root, "pfts", p, "post.distns.Rdata")
    if (!file.exists(f)) {
      PEcAn.logger::logger.severe("pft posterior not found: ", f)
    }
  }

  # resolve every input before expanding anything. papply defaults to
  # stop.on.error = FALSE, which logs a failing block and drops it from the
  # result, so without this a run with a missing met file would quietly produce
  # a settings object with one fewer block than the table has rows.
  for (i in seq_len(nrow(sites))) {
    row <- as.list(sites[i, ])
    for (type in c("met", "ic", "events")) {
      member_paths(input_dir(row, type), type, row$id)
    }
  }

  # createMultiSiteSettings copies every non-id column into run$site, so the
  # per block pass below reads what it needs from there and any extra column
  # the table carries reaches the analysis untouched
  site_info <- as.data.frame(sites, stringsAsFactors = FALSE)
  site_info$name <- sites$id

  # shared directories are set before the per block pass, because assigning
  # them on a MultiSettings afterwards would overwrite the per block outdir
  settings <- PEcAn.settings::read.settings(template)
  settings$model$binary <- normalizePath(binary)
  settings$outdir <- outdir
  settings$modeloutdir <- file.path(outdir, "out")
  settings$rundir <- file.path(outdir, "run")
  settings$host$outdir <- file.path(outdir, "out")
  settings$host$rundir <- file.path(outdir, "run")

  set_block <- function(s) {
    site <- s$run$site
    s$run$start.date <- site$run_start
    s$run$end.date <- site$run_end
    s$run$site$met.start <- site$run_start
    s$run$site$met.end <- site$run_end
    s$run$site$site.pft <- list(veg = site$veg_pft, soil = site$soil_pft)

    # one plant and one soil PFT per block. write.config.SIPNET applies them in
    # order and warns on a duplicated trait name, so the two posteriors must
    # not overlap; keeping them separate is what makes the soil traits reachable
    pft_block <- function(name) {
      list(name = name,
           posterior.files = file.path(input_root, "pfts", name,
                                       "post.distns.Rdata"),
           outdir = file.path(input_root, "pfts", name))
    }
    s$pfts <- list(pft = pft_block(site$veg_pft), pft = pft_block(site$soil_pft))

    y0 <- as.integer(format(as.Date(site$run_start), "%Y"))
    y1 <- as.integer(format(as.Date(site$run_end), "%Y"))
    s$sensitivity.analysis$start.year <- y0
    s$sensitivity.analysis$end.year <- y1
    s$ensemble$start.year <- y0
    s$ensemble$end.year <- y1
    s$ensemble$size <- ensemble_size

    # analysis artifacts go to a directory named by the run key. PEcAn names
    # sensitivity files by ensemble id only, so a shared outdir would push the
    # block identity into a lookup instead of the data. model runs still share
    # one rundir so the whole matrix submits as a single array.
    s$outdir <- file.path(outdir, "blocks", site$id)

    met <- member_paths(input_dir(site, "met"), "met", site$id)
    ic <- member_paths(input_dir(site, "ic"), "ic", site$id)
    events <- member_paths(input_dir(site, "events"), "events", site$id)
    s$run$inputs$met$path <- met
    s$run$inputs$poolinitcond$path <- ic
    s$run$inputs$poolinitcond$ensemble <- length(ic)
    s$run$inputs$events$path <- events
    s
  }

  out <- settings |>
    PEcAn.settings::createMultiSiteSettings(site_info) |>
    PEcAn.settings::papply(set_block, stop.on.error = TRUE)

  if (length(out) != nrow(sites)) {
    PEcAn.logger::logger.severe(
      "built ", length(out), " blocks from ", nrow(sites),
      " rows; every row must produce a block"
    )
  }
  out
}

# SIPNET reads its climate from .clim, its initial pools from a netCDF and its
# management from .in
MEMBER_EXT <- list(met = "\\.clim$", ic = "\\.nc$", events = "\\.in$")

`%||%` <- function(x, y) if (is.null(x)) y else x
