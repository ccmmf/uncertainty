fixture_root <- function(sites) {
  root <- withr::local_tempdir(.local_envir = parent.frame())
  for (i in seq_len(nrow(sites))) {
    for (rel in c(sites$met_src[i], sites$ic_src[i], sites$events_src[i])) {
      dir.create(file.path(root, rel), recursive = TRUE, showWarnings = FALSE)
    }
    # two ensemble members per input, named so the replicate number is last
    for (n in 1:2) {
      file.create(file.path(root, sites$met_src[i], sprintf("ERA5.%d.clim", n)))
      file.create(file.path(root, sites$ic_src[i], sprintf("IC_site_%d.nc", n)))
      file.create(file.path(root, sites$events_src[i], sprintf("events_%d.in", n)))
    }
  }
  for (p in unique(c(sites$veg_pft, sites$soil_pft))) {
    dir.create(file.path(root, "pfts", p), recursive = TRUE, showWarnings = FALSE)
    file.create(file.path(root, "pfts", p, "post.distns.Rdata"))
  }
  root
}

two_blocks <- data.frame(
  id = c("early.trtA", "late.trtB"),
  site = c("early", "late"),
  treatment = c("trtA", "trtB"),
  lat = c(36.6, 38.5), lon = c(-121.5, -121.9),
  veg_pft = c("annual_crop_row", "annual_crop_corn"),
  soil_pft = c("soil", "soil_rice"),
  run_start = c("2000-01-01", "2010-01-01"),
  run_end = c("2001-12-31", "2011-12-31"),
  met_src = c("met/a", "met/b"),
  ic_src = c("IC/early/x", "IC/late/y"),
  events_src = c("events/early/trtA", "events/late/trtB"),
  stringsAsFactors = FALSE
)

build <- function(sites, root) {
  binary <- file.path(root, "sipnet")
  file.create(binary)
  build_settings(sites, "../../examples/calval/template.xml", root,
                        binary, file.path(root, "out"))
}

test_that("each block keeps its own window, PFT pair and outdir", {
  root <- fixture_root(two_blocks)
  s <- build(two_blocks, root)

  expect_equal(length(s), 2)
  got <- lapply(seq_along(s), function(i) s[[i]])

  # the cal/val sites do not share a window; a shared start date would silently
  # run one site over the other's years
  expect_equal(vapply(got, function(x) x$run$start.date, ""),
               c("2000-01-01", "2010-01-01"))
  expect_equal(vapply(got, function(x) x$sensitivity.analysis$start.year, 0),
               c(2000, 2010))
  expect_equal(vapply(got, function(x) x$sensitivity.analysis$end.year, 0),
               c(2001, 2011))

  # one plant and one soil PFT per block, not a shared global list
  expect_equal(lapply(got, function(x) unname(vapply(x$pfts, `[[`, "", "name"))),
               list(c("annual_crop_row", "soil"),
                    c("annual_crop_corn", "soil_rice")))

  # run identity comes from the output path, so no later step needs an
  # ensemble-id-to-block lookup
  expect_equal(vapply(got, function(x) basename(x$outdir), ""),
               c("early.trtA", "late.trtB"))
})

test_that("a duplicated id is rejected", {
  dup <- two_blocks
  dup$id <- c("same", "same")
  root <- fixture_root(dup)
  expect_error(build(dup, root), "id must be unique")
})

test_that("a missing input is caught before any config is written", {
  root <- fixture_root(two_blocks)
  unlink(file.path(root, "events/late/trtB"), recursive = TRUE)
  expect_error(build(two_blocks, root), "events\\s+not found")
})

test_that("a missing PFT posterior is caught", {
  root <- fixture_root(two_blocks)
  unlink(file.path(root, "pfts", "soil_rice"), recursive = TRUE)
  expect_error(build(two_blocks, root), "pft posterior\\s+not found")
})

test_that("required columns are checked", {
  root <- fixture_root(two_blocks)
  expect_error(build(two_blocks[, setdiff(names(two_blocks), "soil_pft")], root),
               "missing columns:\\s+soil_pft")
})

test_that("a shared window is used when the table has no per-row dates", {
  sites <- two_blocks[, setdiff(names(two_blocks), c("run_start", "run_end"))]
  root <- fixture_root(sites)
  binary <- file.path(root, "sipnet"); file.create(binary)

  expect_error(
    build_settings(sites, "../../examples/calval/template.xml", root, binary,
                   file.path(root, "out")),
    "no run_start/run_end"
  )

  s <- build_settings(sites, "../../examples/calval/template.xml", root, binary,
                      file.path(root, "out"),
                      window = list(start = "2015-01-01", end = "2016-12-31"))
  expect_equal(vapply(seq_along(s), function(i) s[[i]]$run$start.date, ""),
               rep("2015-01-01", 2))
})

test_that("input directories can be derived from a template", {
  sites <- two_blocks[, setdiff(names(two_blocks), "met_src")]
  sites$met_grid <- c("a", "b")
  root <- fixture_root(two_blocks)
  binary <- file.path(root, "sipnet"); file.create(binary)

  s <- build_settings(sites, "../../examples/calval/template.xml", root, binary,
                      file.path(root, "out"),
                      dirs = list(met = "met/{met_grid}"))
  expect_match(s[[1]]$run$inputs$met$path$path1, "met/a/ERA5")
})

test_that("columns beyond the contract reach run$site", {
  root <- fixture_root(two_blocks)
  s <- build(two_blocks, root)
  expect_equal(s[[1]]$run$site$treatment, "trtA")
  expect_equal(s[[2]]$run$site$site, "late")
})

test_that("every row produces a block", {
  # papply defaults to stop.on.error = FALSE, which drops a failing element and
  # carries on. a build that silently returned fewer blocks than the table has
  # rows would look like a successful smaller run.
  root <- fixture_root(two_blocks)
  s <- build(two_blocks, root)
  expect_equal(length(s), nrow(two_blocks))
  expect_equal(vapply(seq_along(s), function(i) s[[i]]$run$site$id, ""),
               two_blocks$id)
})
