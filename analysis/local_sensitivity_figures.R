#!/usr/bin/env Rscript

# Figures and table for analysis/local_sensitivity.qmd.
#
# Shares are taken on one denominator per site and output: each parameter's
# variance over the sum across the plant and soil PFTs at that site. PEcAn's
# partial_variance normalizes within each PFT, so it cannot say whether plant or
# soil parameters dominate an output.
#
#   Rscript analysis/local_sensitivity_figures.R

library(PEcAn.logger)
library(ggplot2)
library(patchwork)

source("000-config.R")

options <- list(
  optparse::make_option("--table",
    default = file.path(run_dir, "statewide_sensitivity.csv"),
    help = "aggregated table written by 013_aggregate_sensitivity.R"
  ),
  optparse::make_option("--sa_dir",
    default = file.path(run_dir, "output"),
    help = "OAT run output directory"
  ),
  optparse::make_option("--climregions",
    default = climregions_file,
    help = "Cal-Adapt climate regions, drawn under the site map"
  ),
  optparse::make_option("--example_site",
    default = "284301",
    help = "site for the response curve figure"
  ),
  optparse::make_option("--outdir",
    default = "analysis/figures",
    help = "where figures and the table go"
  )
) |>
  purrr::modify(\(x) {
    x@help <- paste(x@help, "[default: %default]")
    x
  })

args <- optparse::OptionParser(option_list = options) |>
  optparse::parse_args()

source("R/plot_sensitivities_multi.R")

OUTPUTS <- c(TotSoilCarb = "Soil carbon", N2O_flux = "Nitrous oxide flux",
             CH4_flux = "Methane flux")
THRESHOLD <- 0.05

# traits missing from PEcAn's trait dictionary, plus turn_over_time, which the
# dictionary calls a turnover time but SIPNET uses as litterBreakdownRate (yr-1);
# units from the SIPNET source (baseSoilResp is read in as a per-year rate)
EXTRA_LABELS <- c(
  soil_respiration_Q10 = "Soil Resp. Q10",
  som_respiration_rate = "SOM Respiration Rate",
  leafOnReallocFrac = "Leaf-on Realloc. Fraction",
  leafNResorptionFrac = "Leaf N Resorption Fraction",
  turn_over_time = "Litter Breakdown Rate"
)
EXTRA_UNITS <- c(soil_respiration_Q10 = "unitless", som_respiration_rate = "yr-1",
                 leafOnReallocFrac = "unitless")

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

label_param <- function(x) {
  y <- as.character(suppressWarnings(PEcAn.utils::trait.lookup(x)$figid))
  unname(dplyr::coalesce(EXTRA_LABELS[x], y, gsub("_", " ", x)))
}

label_units <- function(x) {
  y <- as.character(suppressWarnings(PEcAn.utils::trait.lookup(x)$units))
  ifelse(is.na(y), EXTRA_UNITS[x], y)
}

tab <- utils::read.csv(args$table, colClasses = c(site_id = "character")) |>
  dplyr::filter(.data$variable %in% names(OUTPUTS),
                .data$pft == .data$veg_pft | .data$pft == "soil") |>
  dplyr::mutate(kind = ifelse(.data$pft == "soil", "soil", "plant")) |>
  dplyr::mutate(share = .data$variance / sum(.data$variance, na.rm = TRUE),
                .by = c("site_id", "variable"))

# table: parameters above the threshold at any site
keep <- tab |>
  dplyr::summarise(
    median = stats::median(.data$share, na.rm = TRUE),
    low = min(.data$share, na.rm = TRUE),
    high = max(.data$share, na.rm = TRUE),
    sites_over = sum(.data$share > THRESHOLD, na.rm = TRUE),
    sites = dplyr::n(),
    negative = sum(.data$elasticity < 0, na.rm = TRUE),
    .by = c("variable", "kind", "parameter")
  ) |>
  dplyr::filter(.data$sites_over > 0) |>
  dplyr::arrange(.data$variable, dplyr::desc(.data$median))
utils::write.csv(keep, file.path(args$outdir, "parameter_shares.csv"), row.names = FALSE)

# figure: response curves at one site, soil PFT
settings <- PEcAn.settings::read.settings(file.path(args$sa_dir, "pecan.CONFIGS.xml"))
ids <- vapply(settings, function(s) as.character(s$run$site$id), character(1))
if (!args$example_site %in% ids) logger.severe("site", args$example_site, "not in the run")
eid <- settings[[match(args$example_site, ids)]]$sensitivity.analysis$ensemble.id
results <- lapply(stats::setNames(nm = names(OUTPUTS)), function(v) {
  f <- file.path(args$sa_dir, sprintf("sensitivity.results.%s.%s.2016.2023.Rdata", eid, v))
  PEcAn.utils::load_local(f)$sensitivity.results$soil
})
samples <- PEcAn.utils::load_local(file.path(args$sa_dir, "samples.Rdata"))$trait.samples$soil
ggsave(file.path(args$outdir, "response_curves_soil.png"),
       plot_sensitivities_multi(results, samples, threshold = THRESHOLD),
       width = 7.5, height = 7, dpi = 300)

# parameters carried into the figures below
# soil parameters over the threshold at any site; plant parameters only where they
# pass it at five or more sites, the rest are single-site exceptions
fig_rows <- keep |>
  dplyr::filter(.data$kind == "soil" | .data$sites_over >= 5) |>
  dplyr::select("variable", "kind", "parameter", "median")
fig_params <- fig_rows |>
  dplyr::summarise(m = max(.data$median), .by = "parameter") |>
  dplyr::arrange(dplyr::desc(.data$m)) |>
  dplyr::pull("parameter")

# strip labels carry units, since the response curves are drawn on parameter scale
prior_lab <- stats::setNames(sprintf("%s\n(%s)", label_param(fig_params), label_units(fig_params)),
                             fig_params)

# figure: site map, as the downscaling design point map
sites <- dplyr::distinct(tab, .data$site_id, .data$lat, .data$lon, .data$veg_pft) |>
  dplyr::mutate(pft = label_pft(.data$veg_pft))
n_pft <- table(sites$pft)
regions <- sf::st_read(args$climregions, quiet = TRUE) |> sf::st_transform(4326)
p <- ggplot() +
  geom_sf(data = regions, fill = "white", color = "grey70") +
  geom_point(data = sites, aes(.data$lon, .data$lat, fill = .data$pft),
             shape = 21, size = 2.2, color = "grey20", stroke = 0.3) +
  scale_fill_manual(values = PFT_COLORS, drop = TRUE, name = NULL,
                    labels = function(x) sprintf("%s (%d)", x, n_pft[x])) +
  labs(x = NULL, y = NULL) +
  theme(legend.position = "right")
ggsave(file.path(args$outdir, "site_map.png"), p, width = 6.5, height = 6, dpi = 300)

# figure: share across sites and by PFT, Dietze et al. 2014 fig 2
# methane has no variance to share at design points where it is zero under every run,
# so those design points drop out of its panel
dietze2 <- function(v) {
  d <- tab |>
    dplyr::semi_join(dplyr::filter(fig_rows, .data$variable == v), by = c("variable", "parameter")) |>
    dplyr::filter(.data$variable == v, !is.na(.data$share)) |>
    dplyr::mutate(share = 100 * .data$share, pft = label_pft(.data$veg_pft))
  ord <- d |>
    dplyr::summarise(m = mean(.data$share), .by = "parameter") |>
    dplyr::arrange(.data$m) |>
    dplyr::pull("parameter")
  d$param_f <- factor(d$parameter, levels = ord, labels = label_param(ord))
  by_pft <- dplyr::summarise(d, share = mean(.data$share), .by = c("param_f", "pft"))
  x_axis <- scale_x_continuous(limits = c(0, 100), expand = expansion(c(0, 0.02)))
  a <- ggplot(d, aes(.data$share, .data$param_f)) +
    geom_boxplot(outlier.shape = 1, outlier.size = 1, width = 0.6) +
    stat_summary(fun = mean, geom = "point", shape = 124, size = 6, color = "#009E73") +
    x_axis +
    labs(x = NULL, y = NULL, title = sprintf("%s (%d)", OUTPUTS[[v]], length(unique(d$site_id)))) +
    theme(plot.title = element_text(size = 11, face = "bold"))
  b <- ggplot(by_pft, aes(.data$share, .data$param_f, fill = .data$pft)) +
    geom_col(position = position_dodge2(reverse = TRUE, preserve = "single"), width = 0.85) +
    scale_fill_manual(values = PFT_COLORS, name = NULL, drop = FALSE) +
    x_axis +
    labs(x = "share of parameter variance (%)", y = NULL)
  a / b + patchwork::plot_layout(heights = c(1, 1.6))
}
p <- (dietze2("TotSoilCarb") | dietze2("N2O_flux") | dietze2("CH4_flux")) +
  patchwork::plot_layout(guides = "collect")
ggsave(file.path(args$outdir, "share_by_pft.png"), p, width = 13, height = 8, dpi = 300)

# figure: CV, elasticity and share across sites, LeBauer et al. 2013 fig 7
metric_levels <- c("CV (%)", "elasticity", "share of parameter\nvariance (%)")
# elasticity divides by the median output, so it is undefined for methane at sites
# whose median run produces none; PEcAn returns 0 or NaN there
ch4_median <- vapply(ids, function(site) {
  eid <- settings[[match(site, ids)]]$sensitivity.analysis$ensemble.id
  f <- file.path(args$sa_dir, sprintf("sensitivity.output.%s.CH4_flux.2016.2023.Rdata", eid))
  PEcAn.utils::load_local(f)$sensitivity.output$soil["50", 1]
}, numeric(1))
no_ch4 <- ids[ch4_median == 0]
comp <- tab |>
  dplyr::mutate(elasticity = ifelse(.data$variable == "CH4_flux" & .data$site_id %in% no_ch4,
                                    NA, .data$elasticity)) |>
  dplyr::semi_join(fig_rows, by = c("variable", "parameter")) |>
  dplyr::mutate(share = 100 * .data$share, coef_var = 100 * .data$coef_var) |>
  tidyr::pivot_longer(c("coef_var", "elasticity", "share"), names_to = "metric") |>
  dplyr::summarise(
    med = stats::median(.data$value, na.rm = TRUE),
    lo = stats::quantile(.data$value, 0.25, na.rm = TRUE),
    hi = stats::quantile(.data$value, 0.75, na.rm = TRUE),
    .by = c("variable", "parameter", "metric")
  ) |>
  dplyr::left_join(dplyr::select(fig_rows, "variable", "parameter", order = "median"),
                   by = c("variable", "parameter")) |>
  dplyr::mutate(
    metric = factor(c(coef_var = "CV (%)", elasticity = "elasticity",
                      share = "share of parameter\nvariance (%)")[.data$metric],
                    levels = metric_levels),
    output = factor(OUTPUTS[.data$variable], levels = OUTPUTS),
    # one row per output and parameter, ordered by median share within the output
    row = paste(.data$variable, .data$parameter, sep = ":")
  )
row_levels <- comp |>
  dplyr::distinct(.data$row, .data$output, .data$order) |>
  dplyr::arrange(.data$output, .data$order) |>
  dplyr::pull("row")
comp$row <- factor(comp$row, levels = row_levels)
zero <- tibble::tibble(metric = factor(metric_levels, levels = metric_levels), x = 0)

p <- ggplot(comp, aes(y = .data$row)) +
  geom_vline(data = zero, aes(xintercept = .data$x), color = "grey40", linewidth = 0.3) +
  geom_linerange(aes(xmin = .data$lo, xmax = .data$hi), color = "grey50") +
  geom_point(aes(x = .data$med), size = 2) +
  facet_grid(output ~ metric, scales = "free", space = "free_y") +
  scale_y_discrete(labels = function(x) label_param(sub("^[^:]+:", "", x))) +
  labs(x = NULL, y = NULL) +
  theme(strip.text.y = element_text(angle = 0, hjust = 0))
ggsave(file.path(args$outdir, "variance_components.png"), p, width = 9, height = 5.5, dpi = 300)

# figure: response curves at every site, LeBauer et al. 2013 fig 6
# each site's output is divided by its own median run, so sites whose soil carbon
# differs by an order of magnitude share one axis
# methane's median run is zero at many sites, so a ratio to it is undefined there
CURVE_OUTPUTS <- setdiff(names(OUTPUTS), "CH4_flux")
curves <- purrr::map(ids, function(site) {
  s <- settings[[match(site, ids)]]
  veg <- unique(tab$veg_pft[tab$site_id == site])
  eid <- s$sensitivity.analysis$ensemble.id
  purrr::map(CURVE_OUTPUTS, function(v) {
    f <- file.path(args$sa_dir, sprintf("sensitivity.results.%s.%s.2016.2023.Rdata", eid, v))
    res <- PEcAn.utils::load_local(f)$sensitivity.results
    wanted <- fig_rows$parameter[fig_rows$variable == v]
    purrr::map(wanted, function(p) {
      pft <- if (p %in% names(res$soil$sensitivity.output$sa.splines)) "soil" else veg
      spline <- res[[pft]]$sensitivity.output$sa.splines[[p]]
      if (is.null(spline)) return(NULL)
      sa <- res[[pft]]$sensitivity.output$sa.samples
      x <- sa[, p]
      median_run <- spline(x[rownames(sa) == "50"])
      grid <- seq(min(x), max(x), length.out = 101)
      tibble::tibble(site_id = site, veg_pft = veg, variable = v, parameter = p,
                     x = grid, y = spline(grid) / median_run)
    }) |> purrr::list_rbind()
  }) |> purrr::list_rbind()
}) |> purrr::list_rbind()
curves$pft_f <- label_pft(curves$veg_pft)
# woody sites are two thirds of the design; draw them first so the rest stay visible
curves <- curves[order(curves$veg_pft != "woody_perennial"), ]
curves$site_f <- factor(curves$site_id, levels = unique(curves$site_id))

for (v in CURVE_OUTPUTS) {
  d <- curves[curves$variable == v, ]
  d$lab <- factor(prior_lab[d$parameter], levels = prior_lab[fig_params])
  p <- ggplot(d, aes(.data$x, .data$y, group = .data$site_f, color = .data$pft_f)) +
    geom_hline(yintercept = 1, color = "grey70") +
    geom_line(linewidth = 0.3, alpha = 0.6) +
    facet_wrap(~lab, scales = "free_x", ncol = 4) +
    scale_color_manual(values = PFT_COLORS, name = NULL, drop = TRUE) +
    scale_x_continuous(n.breaks = 3, guide = guide_axis(check.overlap = TRUE),
                       labels = function(x) format(x, digits = 2, trim = TRUE)) +
    labs(x = NULL, y = "output / median run") +
    theme(strip.text = element_text(size = 8, face = "bold"),
          panel.spacing.x = unit(1.5, "lines"))
  n_panel <- length(unique(d$parameter))
  ggsave(file.path(args$outdir, sprintf("response_curves_%s.png", v)), p,
         width = 9, height = 1.2 + 2.2 * ceiling(n_panel / 4), dpi = 300)
}

logger.info("wrote figures and parameter_shares.csv to", args$outdir)
