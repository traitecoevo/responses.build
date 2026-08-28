#' Extract one dataset from a built database
#'
#' Subsets every table of a database to a single `dataset_id`, and prunes the
#' list-shaped parts -- `sources`, `definitions`, `metadata$contributors` -- to
#' what that dataset actually uses.
#'
#' This replaces `austraits::extract_dataset()`, which cannot run on a database
#' built here since the compatibility handshake was severed. It is also what
#' the dataset report needs, and a report is the main reason to want one
#' dataset out of a compilation.
#'
#' @param database A built database
#' @param dataset_id The dataset to extract
#'
#' @return A database object holding only that dataset
#' @importFrom rlang .data
#' @export
extract_dataset <- function(database, dataset_id) {

  if (length(dataset_id) != 1) {
    stop("`extract_dataset()` takes one `dataset_id`; got ", length(dataset_id),
         call. = FALSE)
  }

  known <- unique(database[["traits"]][["dataset_id"]])

  if (!dataset_id %in% known) {
    # Naming near misses beats "0 rows", which is what a typo used to produce.
    close <- known[
      utils::adist(dataset_id, known, ignore.case = TRUE)[1, ] <=
        max(2, nchar(dataset_id) %/% 4)
    ]
    stop(
      "No dataset `", dataset_id, "` in this database.",
      if (length(close) > 0) paste0(" Did you mean: ", paste(close, collapse = ", "), "?"),
      call. = FALSE
    )
  }

  out <- database

  for (name in names(database)) {
    tbl <- database[[name]]
    if (is.data.frame(tbl) && "dataset_id" %in% names(tbl)) {
      out[[name]] <- tbl %>% dplyr::filter(.data$dataset_id == !!dataset_id)
    }
  }

  # `taxa` has no `dataset_id`; keep the taxa this dataset actually recorded
  if (!is.null(out[["taxa"]]) && "taxon_name" %in% names(out[["taxa"]])) {
    out[["taxa"]] <- out[["taxa"]] %>%
      dplyr::filter(.data$taxon_name %in% c(out[["traits"]][["taxon_name"]],
                                            out[["excluded_data"]][["taxon_name"]]))
  }

  # `sources` is a named list of citations, keyed by citation key
  keys <- unique(stats::na.omit(unlist(
    out[["methods"]][c("source_primary_key", "source_secondary_key",
                       "source_original_dataset_key")]
  )))
  if (!is.null(out[["sources"]]) && length(keys) > 0) {
    out[["sources"]] <- out[["sources"]][intersect(names(out[["sources"]]), keys)]
  }

  # `definitions` covers the whole compilation's vocabulary; a report on one
  # dataset wants the variables that dataset measured
  measured <- unique(c(out[["traits"]][["trait_name"]],
                       out[["excluded_data"]][["trait_name"]]))
  if (!is.null(out[["definitions"]]) && length(measured) > 0) {
    out[["definitions"]] <- out[["definitions"]][
      intersect(names(out[["definitions"]]), measured)
    ]
  }

  out
}


#' Add taxonomic rank columns to a database's tables
#'
#' Joins columns from the `taxa` table -- `family`, `genus`, `taxon_rank` --
#' onto `traits`, and onto `curves` where present.
#'
#' Replaces `austraits::join_taxa()` for databases built here.
#'
#' @param database A built database
#' @param vars Columns of `taxa` to join on
#'
#' @return The database, with those columns added
#' @importFrom rlang .data
#' @export
join_taxa <- function(database, vars = c("family", "genus", "taxon_rank")) {

  taxa <- database[["taxa"]]

  if (is.null(taxa) || nrow(taxa) == 0) return(database)

  vars <- intersect(vars, names(taxa))

  if (length(vars) == 0) {
    stop("`taxa` has none of: ", paste(vars, collapse = ", "), call. = FALSE)
  }

  lookup <- taxa %>%
    dplyr::select(dplyr::all_of(c("taxon_name", vars))) %>%
    dplyr::distinct(.data$taxon_name, .keep_all = TRUE)

  for (name in c("traits", "curves", "excluded_data")) {
    tbl <- database[[name]]
    if (is.null(tbl) || !"taxon_name" %in% names(tbl)) next
    database[[name]] <- tbl %>%
      dplyr::select(-dplyr::any_of(vars)) %>%
      dplyr::left_join(lookup, by = "taxon_name")
  }

  database
}
