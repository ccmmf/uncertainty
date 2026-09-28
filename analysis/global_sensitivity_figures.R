#!/usr/bin/env Rscript

# Figures and summary table for analysis/global_sensitivity.qmd.
#
# Indices and their intervals come from 023_aggregate_sobol.R. Model outputs come
# from the ensemble output get.results saved for each design point.
#
#   Rscript analysis/global_sensitivity_figures.R

library(PEcAn.logger)
library(ggplot2)

# no gridlines, as in plot_sensitivities_multi and PEcAn's variance decomposition plots
theme_set(
  theme_minimal(base_size = 11) +
    theme(
      panel.grid = element_blank(),
      axis.ticks = element_line(color = "grey60"),
      strip.text = element_text(size = 9, face = "bold"),
      legend.position = "bottom"
    )
)

# Okabe-Ito, so every figure reads under the common forms of color blindness
PFT_COLORS <- c(
  alfalfa = "#009E73", corn = "#56B4E9", grass = "#CC79A7", rice = "#0072B2",
  `row crop` = "#000000", `woody perennial` = "#E69F00", uncropped = "grey60"
)
label_pft <- function(x) {
  factor(dplyr::recode(x, soil = "uncropped", woody_perennial = "woody perennial",
                       row = "row crop"), levels = names(PFT_COLORS))
}

options <- list(
  optparse::make_option("--intervals",
    default = "global_sensitivity.csv",
    help = "indices with intervals written by 023_aggregate_sobol.R"
  ),
  optparse::make_option("--settings",
    default = "output/pecan.CONFIGS.xml",
    help = "settings written by 021_run_global_sensitivity.R"
  ),
  optparse::make_option("--site_file",
    default = "site_info.csv",
    help = "site table the design points were taken from"
  ),
  optparse::make_option("--climregions",
    default = "data_raw/caladapt_climregions.gpkg",
    help = "Cal-Adapt climate regions, drawn under the site map"
  ),
  optparse::make_option("--outdir",
    default = "figures",
    help = "where figures and the table go"
  )
) |>
  purrr::modify(\(x) {
    x@help <- paste(x@help, "[default: %default]")
    x
  })

args <- optparse::OptionParser(option_list = options) |>
  optparse::parse_args()

# methane is below the output file's precision in most runs, so indices are drawn for
# soil carbon and nitrous oxide only
INDEX_OUTPUTS <- c(TotSoilCarb = "Soil carbon", N2O_flux = "Nitrous oxide flux")
INPUTS <- c(param = "parameters", poolinitcond = "initial conditions",
            events = "management", met = "meteorology")
INDICES <- c(first_order = "first-order index", total_order = "total-order index")

# every output the run saved. PEcAn stores fluxes in kg m-2 s-1; reported per year
PER_YEAR <- 1000 * 365.25 * 86400
OUTPUTS <- tibble::tribble(
  ~variable,     ~label,                                    ~scale,   ~shown,
  "TotSoilCarb", "soil carbon (kg C m-2)",                  1,        TRUE,
  "N2O_flux",    "nitrous oxide flux (g N m-2 yr-1)",       PER_YEAR, TRUE,
  "CH4_flux",    "methane flux (g C m-2 yr-1)",             PER_YEAR, TRUE,
  "AbvGrndWood", "aboveground woody biomass (kg C m-2)",    1,        FALSE,
  "NEE",         "net ecosystem exchange (g C m-2 yr-1)",   PER_YEAR, FALSE
)

settings <- PEcAn.settings::read.settings(args$settings)
ids <- vapply(settings, function(s) as.character(s$run$site$id), character(1))

# design points have no names; label them by PFT, numbered in design order
sites <- utils::read.csv(args$site_file, colClasses = c(id = "character")) |>
  dplyr::filter(.data$id %in% ids) |>
  dplyr::mutate(pft = label_pft(.data$site.pft)) |>
  dplyr::mutate(n = dplyr::n(), k = dplyr::row_number(), .by = "pft") |>
  dplyr::mutate(label = ifelse(.data$n > 1, paste(.data$pft, .data$k), as.character(.data$pft))) |>
  dplyr::arrange(.data$pft, .data$k)
sites$label <- factor(sites$label, levels = rev(sites$label))

idx <- utils::read.csv(args$intervals, colClasses = c(site_id = "character")) |>
  dplyr::filter(.data$variable %in% names(INDEX_OUTPUTS)) |>
  dplyr::left_join(dplyr::select(sites, site_id = "id", "pft", "label"), by = "site_id") |>
  dplyr::mutate(
    output = factor(INDEX_OUTPUTS[.data$variable], levels = INDEX_OUTPUTS),
    input = factor(INPUTS[.data$factor], levels = rev(INPUTS)),
    index_f = factor(INDICES[.data$index], levels = INDICES)
  )
if (anyNA(idx$label) || anyNA(idx$input)) logger.severe("unknown site or input in", args$intervals)

# table: indices across design points
summ <- idx |>
  dplyr::summarise(
    sites = dplyr::n(),
    median = stats::median(.data$estimate),
    q25 = stats::quantile(.data$estimate, 0.25),
    q75 = stats::quantile(.data$estimate, 0.75),
    min = min(.data$estimate),
    max = max(.data$estimate),
    median_lower = stats::median(.data$lower),
    median_upper = stats::median(.data$upper),
    .by = c("variable", "output", "factor", "input", "index", "index_f")
  )
summ |>
  dplyr::select(-"output", -"input", -"index_f") |>
  dplyr::arrange(.data$variable, .data$index, dplyr::desc(.data$median)) |>
  utils::write.csv(file.path(args$outdir, "gsa_index_summary.csv"), row.names = FALSE)

# indices fall between 0 and 1; estimates outside that range are estimation error
bounds <- geom_vline(xintercept = c(0, 1), color = "grey60", linewidth = 0.3)
unit_axis <- scale_x_continuous(breaks = c(0, 0.5, 1), labels = c("0", "0.5", "1"))

# Okabe-Ito colors not already used for PFTs, so inputs and design points never share one
INPUT_COLORS <- c(parameters = "#D55E00", `initial conditions` = "#0072B2",
                  management = "#009E73", meteorology = "#F0E442", unresolved = "grey85")

# figure: share of variance by input at each design point, the partition by source of
# Dietze (2017). negative first-order estimates are sampling noise and set to 0
# (Saltelli et al. 2008). what the first-order indices leave unexplained, interactions
# plus estimation error, is drawn as its own segment instead of being rescaled away
part <- idx |>
  dplyr::filter(.data$index == "first_order") |>
  dplyr::mutate(share = pmax(.data$estimate, 0), input = as.character(.data$input)) |>
  dplyr::select("site_id", "label", "output", "input", "share")
part <- part |>
  dplyr::summarise(share = pmax(1 - sum(.data$share), 0), .by = c("site_id", "label", "output")) |>
  dplyr::mutate(input = "unresolved") |>
  dplyr::bind_rows(part) |>
  dplyr::mutate(input = factor(.data$input, levels = rev(names(INPUT_COLORS))))
utils::write.csv(dplyr::select(part, -"label"), file.path(args$outdir, "gsa_partition.csv"),
                 row.names = FALSE)

p <- ggplot(part, aes(x = .data$share, y = .data$label, fill = .data$input)) +
  geom_col(width = 0.75) +
  facet_wrap(~output) +
  scale_fill_manual(values = INPUT_COLORS, breaks = names(INPUT_COLORS), name = NULL) +
  scale_x_continuous(expand = c(0, 0), breaks = c(0, 0.5, 1), labels = c("0", "0.5", "1")) +
  labs(x = "share of output variance (first-order index)", y = NULL) +
  theme(panel.spacing.x = unit(1.5, "lines"))
ggsave(file.path(args$outdir, "gsa_partition.png"), p, width = 8, height = 3.8, dpi = 300)

# figure: indices at each design point with their bootstrap intervals
dodge <- position_dodge(width = 0.75)
p <- ggplot(idx, aes(x = .data$estimate, y = .data$input, color = .data$pft,
                     group = .data$label)) +
  bounds +
  geom_linerange(aes(xmin = .data$lower, xmax = .data$upper), position = dodge,
                 linewidth = 0.35) +
  geom_point(position = dodge, size = 1.5) +
  facet_grid(output ~ index_f) +
  scale_color_manual(values = PFT_COLORS, drop = TRUE, name = NULL) +
  unit_axis +
  labs(x = "Sobol index", y = NULL) +
  theme(strip.text.y = element_text(angle = 0, hjust = 0))
ggsave(file.path(args$outdir, "gsa_indices_by_site.png"), p, width = 8, height = 5, dpi = 300)

# model outputs of every run, by design point
sobol_obj <- readRDS(file.path(settings$outdir, "sobol_design.rds"))
n_base <- nrow(sobol_obj$X1)
n_inputs <- ncol(sobol_obj$X1)
read_output <- function(s, v) {
  f <- PEcAn.uncertainty::ensemble.filename(s, "ensemble.output", "Rdata",
                                            all.var.yr = FALSE, variable = v,
                                            start.year = s$ensemble$start.year,
                                            end.year = s$ensemble$end.year)
  y <- unlist(PEcAn.utils::load_local(f)$ensemble.output, use.names = FALSE)
  if (length(y) != nrow(sobol_obj$X)) {
    logger.severe(v, "at site", s$run$site$id, "has", length(y), "runs, design has",
                  nrow(sobol_obj$X))
  }
  y
}
# lapply, not purrr::map: names() of a MultiSettings are its settings keys, not
# one per site, and purrr >= 1.2.2 refuses the mismatch
runs <- lapply(settings, function(s) {
  purrr::map(OUTPUTS$variable, function(v) {
    tibble::tibble(site_id = as.character(s$run$site$id), variable = v,
                   row = seq_len(nrow(sobol_obj$X)), y = read_output(s, v))
  }) |>
    purrr::list_rbind()
}) |>
  purrr::list_rbind()

# table: spread of each output across runs, quoted in the report text
# the first 2N rows of the design are the two independent samples; the rest reuse
# their values, so only these rows are a random sample of the inputs
spread <- runs |>
  dplyr::filter(.data$row <= 2 * n_base) |>
  dplyr::left_join(OUTPUTS, by = "variable") |>
  dplyr::summarise(
    q025 = stats::quantile(.data$y * .data$scale, 0.025),
    q25 = stats::quantile(.data$y * .data$scale, 0.25),
    median = stats::median(.data$y * .data$scale),
    q75 = stats::quantile(.data$y * .data$scale, 0.75),
    q975 = stats::quantile(.data$y * .data$scale, 0.975),
    zero_runs = sum(.data$y == 0),
    runs = dplyr::n(),
    .by = c("site_id", "variable", "label", "shown")
  ) |>
  dplyr::rename(output = "label") |>
  dplyr::left_join(dplyr::select(sites, site_id = "id", "pft", "label"), by = "site_id") |>
  dplyr::mutate(output = factor(.data$output, levels = OUTPUTS$label))
utils::write.csv(dplyr::select(spread, -"shown"),
                 file.path(args$outdir, "gsa_output_spread.csv"), row.names = FALSE)

# figure: total-order index and the width of its interval against base sample size,
# the convergence checks of Nossent et al. (2011) and Sarrazin et al. (2016).
# the design holds k + 2 blocks of N rows; the first n rows of every block are the
# design a base sample of n would have given
# tenths of the base sample: 100 to 1,000 for N = 1000
sizes <- round(seq(n_base / 10, n_base, length.out = 10))
set.seed(1)
convergence <- runs |>
  dplyr::filter(.data$variable %in% names(INDEX_OUTPUTS)) |>
  dplyr::summarise(
    res = list(purrr::map(sizes, function(n) {
      rows <- unlist(lapply(0:(n_inputs + 1), function(j) j * n_base + seq_len(n)))
      obj <- sensitivity::soboljansen(model = NULL, X1 = sobol_obj$X1[seq_len(n), ],
                                      X2 = sobol_obj$X2[seq_len(n), ], nboot = 1000)
      told <- sensitivity::tell(obj, .data$y[rows])
      tibble::tibble(n = n, factor = rownames(told$T), estimate = told$T[, "original"],
                     width = told$T[, "max. c.i."] - told$T[, "min. c.i."])
    }) |> purrr::list_rbind()),
    .by = c("site_id", "variable")
  ) |>
  tidyr::unnest("res")

check <- convergence |>
  dplyr::filter(.data$n == n_base) |>
  dplyr::inner_join(dplyr::filter(idx, .data$index == "total_order"),
                    by = c("site_id", "variable", "factor"), suffix = c("", ".full"))
if (nrow(check) != sum(idx$index == "total_order") ||
      !isTRUE(all.equal(check$estimate, check$estimate.full))) {
  logger.severe("indices at the full sample size do not match", args$intervals)
}

utils::write.csv(convergence, file.path(args$outdir, "gsa_convergence.csv"), row.names = FALSE)

# meteorology and management stay below 0.08 at every size, so only the two inputs that
# carry variance are drawn; the csv keeps all four
convergence <- convergence |>
  dplyr::left_join(dplyr::select(sites, site_id = "id", "pft", "label"), by = "site_id") |>
  dplyr::mutate(output = factor(INDEX_OUTPUTS[.data$variable], levels = INDEX_OUTPUTS),
                input = factor(INPUTS[.data$factor], levels = INPUTS)) |>
  dplyr::filter(.data$factor %in% c("param", "poolinitcond"))
convergence_panel <- function(y, ylab, hlines) {
  ggplot(convergence, aes(.data$n, .data[[y]], group = .data$label, color = .data$pft)) +
    geom_hline(yintercept = hlines, color = "grey60", linewidth = 0.3, linetype = "dashed") +
    geom_line(linewidth = 0.4) +
    facet_grid(output ~ input) +
    scale_color_manual(values = PFT_COLORS, drop = TRUE, name = NULL) +
    scale_x_continuous(breaks = n_base * c(0.25, 0.5, 0.75, 1)) +
    labs(x = "base sample size", y = ylab) +
    theme(strip.text.y = element_text(angle = 0, hjust = 0))
}
# 0.05 is the interval width Sarrazin et al. (2016) take as converged; output names go
# on the right panel only so they appear once
p <- patchwork::wrap_plots(
  convergence_panel("estimate", "total-order index", c(0, 1)) +
    theme(strip.text.y = element_blank()),
  convergence_panel("width", "95% interval width", 0.05),
  ncol = 2, guides = "collect"
)
ggsave(file.path(args$outdir, "gsa_convergence.png"), p, width = 10, height = 4.6, dpi = 300)

# figure: site map
regions <- sf::st_read(args$climregions, quiet = TRUE) |> sf::st_transform(4326)
p <- ggplot() +
  geom_sf(data = regions, fill = "white", color = "grey70") +
  # PFTs with the most design points first, so a lone point is not drawn over
  geom_point(data = sites[order(-sites$n), ], aes(.data$lon, .data$lat, fill = .data$pft),
             shape = 21, size = 2.2, color = "grey20", stroke = 0.3) +
  ggrepel::geom_text_repel(data = sites, aes(.data$lon, .data$lat, label = .data$label),
                           size = 2.8, color = "grey20", seed = 1, max.overlaps = Inf,
                           min.segment.length = 0, segment.color = "grey60",
                           segment.size = 0.3, box.padding = 0.6) +
  scale_fill_manual(values = PFT_COLORS, drop = TRUE, name = NULL) +
  labs(x = NULL, y = NULL) +
  theme(legend.position = "right")
ggsave(file.path(args$outdir, "gsa_site_map.png"), p, width = 6.5, height = 6, dpi = 300)

logger.info("wrote figures and tables to", args$outdir)
