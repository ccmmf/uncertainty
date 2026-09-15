test_that("midpoint of a 30-day range is the floor of the middle", {
  expect_equal(midpoint_date("2004-05-01", "2004-05-31"), "2004-05-16")
})

test_that("equal min/max returns the same date", {
  expect_equal(midpoint_date("2003-10-13", "2003-10-13"), "2003-10-13")
})

test_that("seasonal window collapses to midpoint per David's MVP rule", {
  # spring compost: April 1 - June 1
  expect_equal(midpoint_date("2004-04-01", "2004-06-01"), "2004-05-01")
})

test_that("vectorised input works element-wise", {
  result <- midpoint_date(
    c("2004-04-01", "2003-10-13"),
    c("2004-06-01", "2003-10-13")
  )
  expect_equal(result, c("2004-05-01", "2003-10-13"))
})

test_that("missing max_date falls back to min_date and vice versa", {
  expect_equal(midpoint_date("2004-05-01", NA), "2004-05-01")
  expect_equal(midpoint_date(NA, "2004-05-01"), "2004-05-01")
})

test_that("both NA returns NA", {
  expect_true(is.na(midpoint_date(NA, NA)))
})
