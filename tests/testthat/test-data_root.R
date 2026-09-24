test_that("an unset root is an error, not a relative path", {
  withr::local_envvar(UNCERTAINTY_DATA_ROOT = "")
  expect_error(data_root("a"), "UNCERTAINTY_DATA_ROOT is not set")
})

test_that("components are appended to the root", {
  withr::local_envvar(UNCERTAINTY_DATA_ROOT = "/tmp/artifacts")
  expect_equal(data_root("pkg", "v1.0"), "/tmp/artifacts/pkg/v1.0")
  expect_equal(data_root(), "/tmp/artifacts")
})
