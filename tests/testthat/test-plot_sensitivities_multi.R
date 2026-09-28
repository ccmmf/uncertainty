# Run from the repository root after sourcing R/plot_sensitivities_multi.R.
make_inputs <- function() {
  samples <- data.frame(GDD = 1:5, leafC = 1:5,
                        flat = 1:5, boundary = 1:5)
  rownames(samples) <- c(5, 25, 50, 75, 95)
  inputs <- list(
    TotSoilCarb = list(sa.samples = samples, sa.splines = list(
      GDD = function(x) 8 - .5 * (x - 3),
      leafC = function(x) rep(8, length(x)),
      flat = function(x) rep(8, length(x)), boundary = function(x) 8 + .2 * (x - 3))),
    CH4_flux = list(sa.samples = samples, sa.splines = list(
      GDD = function(x) .1 + .01 * (x - 3),
      leafC = function(x) .1 + .5 * (x - 3),
      flat = function(x) rep(.1, length(x)), boundary = function(x) rep(.1, length(x))))
  )
  lapply(names(inputs), function(output) {
    partial <- if (output == "TotSoilCarb") c(.931, .02, 0, .049) else c(.01, .97, 0, .02)
    list(sensitivity.output = inputs[[output]],
      variance.decomposition.output = list(partial.variances = stats::setNames(partial, names(samples))))
  }) |> stats::setNames(names(inputs))
}
trait_draws <- function() {
  stats::setNames(rep(list(seq(1, 5, length.out = 101)), 4), c("GDD", "leafC", "flat", "boundary"))
}
draw <- function(inputs = make_inputs()) {
  plot_sensitivities_multi(inputs, trait_draws())
}

testthat::test_that("any-output screening preserves physical responses and median points", {
  inputs <- make_inputs()
  before <- inputs
  p <- draw(inputs)
  # Two retained rows, each containing a label, density, SOC, and CH4 panel.
  testthat::expect_equal(length(p), 8)
  testthat::expect_equal(p[[3]]$layers[[2]]$data$y, c(9, 8.5, 8, 7.5, 7))
  testthat::expect_equal(p[[7]]$layers[[2]]$data$y, rep(8, 5))
  testthat::expect_equal(p[[8]]$layers[[2]]$data$y, c(-.9, -.4, .1, .6, 1.1))
  testthat::expect_equal(p[[3]]$layers[[3]]$data$x, 3)
  testthat::expect_equal(p[[3]]$data$y, inputs$TotSoilCarb$sensitivity.output$sa.splines$GDD(p[[3]]$data$x))
  testthat::expect_identical(inputs, before)
})

testthat::test_that("the matrix renders with shared axes and density intervals", {
  withr::local_pdf(NULL)
  p <- draw()
  testthat::expect_error(patchwork::patchworkGrob(p), NA)
  density <- PEcAn.priors::create.density.df(samps = trait_draws()$GDD)
  testthat::expect_equal(p[[2]]$scales$get_scales("x")$limits, range(density$x, 1:5))
  testthat::expect_equal(p[[2]]$scales$get_scales("x")$limits, p[[3]]$scales$get_scales("x")$limits)
  testthat::expect_equal(p[[3]]$scales$get_scales("y")$limits, c(7, 9))
  testthat::expect_equal(p[[3]]$scales$get_scales("y")$limits, p[[7]]$scales$get_scales("y")$limits)
  testthat::expect_equal(range(p[[2]]$layers[[1]]$data$x), c(1.2, 4.8))
  testthat::expect_equal(range(p[[2]]$layers[[2]]$data$x), c(2, 4))
})

testthat::test_that("labels and units come from PEcAn tables", {
  p <- draw()
  variables <- PEcAn.utils::standard_vars
  row <- variables[variables$Variable.Name == "CH4_flux", ]
  testthat::expect_equal(p[[4]]$labels$title, paste(row$Long.name, row$Units, sep = "\n"))
  testthat::expect_match(attr(p[[1]], "grobs")$full$label, "Growing Degree Days", fixed = TRUE)
})


testthat::test_that("empty selections and incompatible samples fail explicitly", {
  testthat::expect_error(plot_sensitivities_multi(make_inputs(), trait_draws(), threshold=1), "No traits")
  inputs <- make_inputs()
  inputs$CH4_flux$sensitivity.output$sa.samples$GDD[1] <- 0
  testthat::expect_error(plot_sensitivities_multi(inputs, trait_draws()), "aligned parameter samples")
})
