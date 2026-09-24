fake_results <- function(params = c("psnTOpt", "SLA"), scale = 1) {
  vd <- list(
    coef.vars = stats::setNames(seq_along(params) * 0.1 * scale, params),
    elasticities = stats::setNames(seq_along(params) * 0.2 * scale, params),
    partial.variances = stats::setNames(c(0.7, 0.3), params),
    variances = stats::setNames(seq_along(params) * 1.0 * scale, params)
  )
  list(variance.decomposition.output = vd)
}

write_fixture <- function(dir, block, variable, y0, y1, pfts = "annual_crop_row",
                          scale = 1) {
  d <- file.path(dir, block)
  dir.create(d, recursive = TRUE, showWarnings = FALSE)
  sensitivity.results <- stats::setNames(
    lapply(pfts, function(p) fake_results(scale = scale)), pfts)
  f <- file.path(d, sprintf("sensitivity.results.NOENSEMBLEID.%s.%d.%d.Rdata",
                            variable, y0, y1))
  save(sensitivity.results, file = f)
  f
}

test_that("runs differing only in window stay separate rows", {
  # the defect this guards against: a loader that reads the variable out of the
  # file name but not the years collapses these two into one result
  dir <- withr::local_tempdir()
  write_fixture(dir, "salinas.socs_sys1", "TotSoilCarb", 2000, 2001)
  write_fixture(dir, "salinas.socs_sys1", "TotSoilCarb", 2010, 2011, scale = 2)

  out <- aggregate_sa(dir)

  expect_equal(nrow(out), 4)
  expect_setequal(unique(out$start_year), c(2000L, 2010L))
  expect_setequal(unique(out$end_year), c(2001L, 2011L))
  early <- out[out$start_year == 2000 & out$parameter == "psnTOpt", ]
  late <- out[out$start_year == 2010 & out$parameter == "psnTOpt", ]
  expect_false(isTRUE(all.equal(early$cv, late$cv)))
})

test_that("treatment identity survives as the block key", {
  dir <- withr::local_tempdir()
  write_fixture(dir, "salinas.socs_sys1", "TotSoilCarb", 2005, 2011)
  write_fixture(dir, "salinas.socs_sys2", "TotSoilCarb", 2005, 2011, scale = 3)

  out <- aggregate_sa(dir)

  expect_setequal(unique(out$id), c("salinas.socs_sys1", "salinas.socs_sys2"))
  expect_equal(nrow(out), 4)
})

test_that("both PFTs of a plant-plus-soil run are kept", {
  dir <- withr::local_tempdir()
  write_fixture(dir, "salinas.socs_sys1", "TotSoilCarb", 2005, 2011,
                pfts = c("annual_crop_row", "soil"))

  out <- aggregate_sa(dir)

  expect_setequal(unique(out$pft), c("annual_crop_row", "soil"))
  # PEcAn normalises within a PFT, so the per-PFT shares sum to one each
  per_pft <- tapply(out$partial_variance, out$pft, sum)
  expect_equal(as.numeric(per_pft), c(1, 1))
  # the joint share puts them on one denominator and sums to one overall
  expect_equal(sum(out$joint_share), 1)
})

test_that("a site table is joined and disagreements are caught", {
  dir <- withr::local_tempdir()
  write_fixture(dir, "salinas.socs_sys1", "TotSoilCarb", 2005, 2011)
  sites <- data.frame(id = "salinas.socs_sys1", site = "salinas",
                      treatment = "socs_sys1", stringsAsFactors = FALSE)

  out <- aggregate_sa(dir, sites)
  expect_equal(unique(out$treatment), "socs_sys1")

  expect_error(
    aggregate_sa(dir, data.frame(id = "somewhere_else")),
    "not in the site table"
  )
})

test_that("an unreadable window is an error, not a silent drop", {
  dir <- withr::local_tempdir()
  d <- file.path(dir, "salinas.socs_sys1")
  dir.create(d, recursive = TRUE)
  sensitivity.results <- list(annual_crop_row = fake_results())
  save(sensitivity.results,
       file = file.path(d, "sensitivity.results.NOENSEMBLEID.TotSoilCarb.Rdata"))

  expect_error(aggregate_sa(dir), "cannot read variable and window")
})
