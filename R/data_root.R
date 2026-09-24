#' Resolve a path against the analysis data root
#'
#' @description
#' The repository holds configuration only. Input packages, model executables
#' and run trees live outside it, under one directory named by the
#' `UNCERTAINTY_DATA_ROOT` environment variable, so an example config carries
#' relative paths and no absolute path is committed.
#'
#' Fails rather than returning the bare path, because an unset root would
#' otherwise produce paths relative to the working directory and the run would
#' fail much later with a confusing message.
#'
#' @param ... Path components appended to the root, as in [file.path()].
#' @return Character path.
#' @examples
#' \dontrun{
#' Sys.setenv(UNCERTAINTY_DATA_ROOT = "/path/to/artifacts")
#' data_root("calval_sa_inputs", "v1.0")
#' }
#' @export
data_root <- function(...) {
  root <- Sys.getenv("UNCERTAINTY_DATA_ROOT")
  if (!nzchar(root)) {
    PEcAn.logger::logger.severe(
      "UNCERTAINTY_DATA_ROOT is not set. Point it at the directory holding the ",
      "input packages, model binaries and run trees, for example ",
      "export UNCERTAINTY_DATA_ROOT=/path/to/artifacts"
    )
  }
  file.path(root, ...)
}
