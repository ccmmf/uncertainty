#' Load a curated cal/val workbook
#'
#' Reads the managements, treatments, and sites tabs from an Excel workbook
#' produced by the CCMMF cal/val curation pipeline (e.g.
#' `White_Salinas_2020_filled.xlsx`). Returns them as a named list of tibbles
#' so downstream functions can work with tidy data without re-opening the file.
#'
#' @param path Path to the .xlsx file.
#' @return A list with elements `managements`, `treatments`, `sites`.
#' @export
read_calval_workbook <- function(path) {
  if (!file.exists(path)) {
    stop("workbook not found: ", path, call. = FALSE)
  }

  required_tabs <- c("managements", "treatments", "sites")
  available <- readxl::excel_sheets(path)
  missing <- setdiff(required_tabs, available)
  if (length(missing) > 0) {
    stop("workbook is missing required tab(s): ",
         paste(missing, collapse = ", "), call. = FALSE)
  }

  list(
    managements = readxl::read_excel(path, sheet = "managements", col_types = "text"),
    treatments  = readxl::read_excel(path, sheet = "treatments",  col_types = "text"),
    sites       = readxl::read_excel(path, sheet = "sites",       col_types = "text")
  )
}
