# Taken unchanged from dlebauer's new_sensitivity_plot_function branch
# (876ef8942fe4d46e129e0fe423ae5a33cb80626c) so this pass has one plot
# implementation rather than two. ccmmf/uncertainty#9 can close once this
# lands.

#' Plot parameter densities and multi-output PEcAn sensitivities
#'
#' @param sensitivity.results Named list by output of PEcAn sensitivity.analysis
#'   results, containing sensitivity.output and variance.decomposition.output.
#'   Assumes aligned results for one site, treatment, PFT, and time window.
#' @param trait.samples Named trait sample vectors from PEcAn's sample object.
#' @param threshold Minimum partial variance in any output to retain a trait.
#'   Labels and native output units come from PEcAn's metadata tables.
#' @return A patchwork plot: labels, density, then one column per output.
#' @export
plot_sensitivities_multi <- function(sensitivity.results, trait.samples, threshold = 0.05) {
  if (!length(sensitivity.results)) stop("Supply at least one output.", call. = FALSE)
  if (length(threshold) != 1L || !is.finite(threshold) || threshold < 0 || threshold > 1) {
    stop("threshold must be a finite number between zero and one.", call. = FALSE)
  }
  sensitivity.plot.inputs <- lapply(sensitivity.results, `[[`, "sensitivity.output")
  samples <- sensitivity.plot.inputs[[1]]$sa.samples
  if (!all(vapply(sensitivity.plot.inputs, function(x) isTRUE(all.equal(x$sa.samples, samples)), logical(1)))) {
    stop("Outputs must have aligned parameter samples for one site, treatment, PFT, and window.", call. = FALSE)
  }
  outputs <- names(sensitivity.results)
  contributions <- do.call(cbind, lapply(sensitivity.results, function(x) {
    x$variance.decomposition.output$partial.variances[colnames(samples)]
  }))
  peak <- apply(contributions, 1, function(x) if (any(is.finite(x))) max(x[is.finite(x)]) else NA_real_)
  traits <- colnames(samples)[is.finite(peak) & peak >= threshold]
  if (!length(traits)) stop("No traits meet the partial variance threshold.", call. = FALSE)
  if (!all(traits %in% names(trait.samples))) stop("Missing saved trait samples for retained traits.", call. = FALSE)
  probabilities <- as.numeric(rownames(samples))
  points <- curves <- list()
  for (output in outputs) {
    for (trait in traits) {
      x <- samples[, trait]
      spline <- sensitivity.plot.inputs[[output]]$sa.splines[[trait]]
      points[[length(points) + 1]] <- data.frame(
        trait, output, x, y = spline(x), median = probabilities == 50)
      x <- sort(unique(c(x, seq(min(x), max(x), length.out = 201))))
      curves[[length(curves) + 1]] <- data.frame(trait, output, x, y = spline(x))
    }
  }
  points <- dplyr::bind_rows(points)
  curves <- dplyr::bind_rows(curves)
  theme <- ggplot2::theme_minimal(base_size = 8) + ggplot2::theme(
    panel.grid = ggplot2::element_blank(),
    axis.text = ggplot2::element_text(color = "grey45", size = 7),
    plot.title = ggplot2::element_text(size = 8),
    plot.margin = ggplot2::margin(1, 5, 1, 5))
  density.plot.inputs <- lapply(trait.samples[traits], function(x) {
    PEcAn.priors::create.density.df(samps = x)
  })
  trait_info <- PEcAn.utils::trait.lookup(traits)
  trait.labels <- stats::setNames(paste(
    vapply(dplyr::coalesce(trait_info$figid, gsub("_", " ", traits)), function(x) {
      paste(strwrap(x, width = 23), collapse = "\n")
    }, character(1)), dplyr::coalesce(trait_info$units, ""), sep = "\n"), traits)
  variables <- PEcAn.utils::standard_vars
  variables <- variables[match(outputs, variables$Variable.Name), ]
  output.labels <- stats::setNames(paste(vapply(variables$Long.name, function(x) {
    paste(strwrap(x, width = 16), collapse = "\n")
  }, character(1)), variables$Units, sep = "\n"), outputs)
  panels <- list()
  for (trait in traits) {
    limits <- range(samples[, trait], density.plot.inputs[[trait]]$x)
    x_axis <- ggplot2::scale_x_continuous(limits = limits, n.breaks = 3,
      guide = ggplot2::guide_axis(check.overlap = TRUE),
      labels = function(x) format(x, digits = 2, trim = TRUE))
    panels[[length(panels) + 1]] <- patchwork::wrap_elements(full = grid::textGrob(
      trait.labels[[trait]], x = 0, hjust = 0,
      gp = grid::gpar(fontsize = 8, col = "grey25", lineheight = 1.1)))
    quantiles <- stats::quantile(trait.samples[[trait]], c(.05, .25, .5, .75, .95))
    panels[[length(panels) + 1]] <- plot_density_quantiles(density.plot.inputs[[trait]], quantiles) +
      x_axis + theme + ggplot2::theme(axis.text.y = ggplot2::element_blank()) +
      ggplot2::labs(x = NULL, y = NULL, title = if (trait == traits[1]) "Parameter density" else NULL)
    for (output in outputs) {
      d <- curves[curves$trait == trait & curves$output == output, ]
      p <- points[points$trait == trait & points$output == output, ]
      y_limits <- range(curves$y[curves$output == output])
      panels[[length(panels) + 1]] <- ggplot2::ggplot(d, ggplot2::aes(x, y)) +
        ggplot2::geom_line(linewidth = .39, color = "grey25") +
        ggplot2::geom_point(data = p, size = .77, color = "grey25") +
        ggplot2::geom_point(data = p[p$median, ], size = 1.375, color = "grey25") +
        x_axis + ggplot2::scale_y_continuous(limits = y_limits, breaks = unique(y_limits),
          labels = function(x) format(signif(x, 2), trim = TRUE)) +
        theme + ggplot2::theme(axis.text.x = ggplot2::element_blank()) +
        ggplot2::labs(x = NULL, y = NULL, title = if (trait == traits[1]) output.labels[[output]] else "")
    }
  }
  patchwork::wrap_plots(panels, ncol = length(outputs) + 2,
    widths = grid::unit.c(grid::unit(1.45, "inches"), grid::unit(rep(1, length(outputs) + 1), "null")))
}

# Density intervals describe the supplied trait sample distribution.
plot_density_quantiles <- function(density, quantiles) {
  x <- sort(unique(c(density$x, quantiles)))
  d <- data.frame(x, y = stats::approx(density$x, density$y, xout = x)$y)
  ggplot2::ggplot(d, ggplot2::aes(x, y)) +
    ggplot2::geom_area(data = d[d$x >= quantiles[1] & d$x <= quantiles[5], ], fill = "grey96") +
    ggplot2::geom_area(data = d[d$x >= quantiles[2] & d$x <= quantiles[4], ], fill = "grey85") +
    ggplot2::geom_line(linewidth = .35, color = "grey25") +
    ggplot2::annotate("segment", x = quantiles[3], xend = quantiles[3], y = 0,
      yend = stats::approx(d$x, d$y, xout = quantiles[3])$y, linewidth = .35, color = "grey25")
}
