#' Bind several built databases into one
#'
#' Combines the relational tables of two or more databases built by this
#' package into a single database object. `AusFizz` and `ausfizz-private` are
#' built separately and merged this way, so that restricted datasets can move
#' through the same pipeline without being published.
#'
#' # Licensing
#'
#' Merging databases merges data held under different licences. The version of
#' this function inherited from `austraits` took the metadata block of its
#' *first* argument and discarded the rest, so merging a public compilation
#' with a restricted one silently stamped the result with the public licence
#' while it held all-rights-reserved data. Nothing warned.
#'
#' This version refuses. If the databases declare different `rights`, you must
#' say what the merged object is licensed under by passing `rights`. There is
#' no default, because there is no safe default: the correct answer depends on
#' agreements this function cannot see.
#'
#' @param ... Databases to combine
#' @param databases A list of databases, as an alternative to `...`
#' @param rights The `rights` string for the merged database. Required when the
#'   inputs disagree. The rest of the licence block (holder, URI, description)
#'   is taken from whichever input declares this `rights` value; if none does,
#'   supply `license` instead.
#' @param license A complete licence block (`rights`, `rights_holder`,
#'   `rights_URI`, `description`) for the merged database, overriding `rights`.
#'
#' @return A combined database object of class `responses.build`
#' @importFrom rlang .data
#' @export
bind_databases <- function(..., databases = list(...), rights = NULL,
                           license = NULL) {

  databases <- databases[!vapply(databases, is.null, logical(1))]

  if (length(databases) == 0) {
    stop("`bind_databases()` needs at least one database.", call. = FALSE)
  }

  combine <- function(name) {
    out <- databases %>% lapply("[[", name)
    if (length(out) == 0) return(NULL)
    out %>% dplyr::bind_rows() %>% dplyr::distinct()
  }

  # `arrange()` on a column that is not there is an error, and a table can
  # legitimately be absent or empty -- a database built before the curve tables
  # existed, or one whose every row was excluded.
  arrange_if <- function(name, ...) {
    out <- combine(name)
    cols <- c(...)
    if (is.null(out) || nrow(out) == 0 || !all(cols %in% names(out))) return(out)
    dplyr::arrange(out, dplyr::across(dplyr::all_of(cols)))
  }

  # Sources and definitions are named lists, not tables
  sources <- databases %>% lapply("[[", "sources")
  keys <- sources %>% lapply(names) %>% unlist() %>% unique() %>% sort()
  sources <- sources %>% purrr::reduce(c)
  sources <- sources[keys]

  definitions <- databases %>% lapply("[[", "definitions") %>% purrr::reduce(c)
  definitions <- definitions[!duplicated(names(definitions))]
  definitions <- definitions[sort(names(definitions))]

  # Compilation-level vocabulary, same shape as `definitions`
  data_types <- databases %>% lapply("[[", "data_types") %>% purrr::reduce(c)
  data_types <- data_types[!duplicated(names(data_types))]
  data_types <- data_types[sort(names(data_types))]

  taxonomic_updates <-
    combine("taxonomic_updates") %>%
    dplyr::distinct() %>%
    dplyr::arrange(
      .data$original_name, .data$aligned_name,
      .data$taxon_name, .data$taxonomic_resolution
    )

  contributors <- combine("contributors")

  metadata <- util_resolve_merged_license(databases, rights, license)

  metadata[["contributors"]] <-
    contributors %>%
    dplyr::select(-dplyr::any_of(c("dataset_id", "additional_role"))) %>%
    dplyr::distinct() %>%
    dplyr::arrange(.data$last_name, .data$given_name) %>%
    convert_df_to_list()

  ret <-
    list(
      measurements = arrange_if("measurements", "dataset_id", "response_id",
                                "point_id", "variable"),
      locations = arrange_if("locations", "dataset_id", "location_id"),
      growth_conditions = arrange_if("growth_conditions", "dataset_id",
                                     "treatment_context_id", "condition"),
      # A total order: `dataset_id` and `category` alone leave rows within a
      # category free to move, so the published row order wobbled whenever a
      # context was added or removed.
      contexts = arrange_if("contexts", "dataset_id", "category",
                            "context_property", "value"),
      methods = arrange_if("methods", "dataset_id", "variable"),
      excluded_data = arrange_if("excluded_data", "dataset_id", "observation_id", "variable"),
      taxonomic_updates = taxonomic_updates,
      taxa = arrange_if("taxa", "taxon_name"),
      identifiers = combine("identifiers"),
      contributors = contributors,
      sources = sources,
      data_types = data_types,
      definitions = definitions,
      schema = databases[[1]][["schema"]],
      metadata = metadata,
      build_info = list(session_info = utils::sessionInfo())
    )

  class(ret) <- c("list", "responses.build")

  ret
}


#' Decide the licence of a merged database
#'
#' Returns the metadata block for the merged object. Errors rather than guess
#' when the inputs disagree and the caller has not said what the result is.
#'
#' @param databases List of databases being merged
#' @param rights A `rights` string supplied by the caller, or NULL
#' @param license A complete licence block supplied by the caller, or NULL
#'
#' @return A metadata list
#' @noRd
util_resolve_merged_license <- function(databases, rights = NULL, license = NULL) {

  metadata <- databases[[1]][["metadata"]]

  declared <-
    databases %>%
    lapply(function(d) d[["metadata"]][["license"]][["rights"]]) %>%
    unlist() %>%
    unique()

  if (!is.null(license)) {
    metadata[["license"]] <- license
    return(metadata)
  }

  if (!is.null(rights)) {
    # Take the full block from whichever input declares this `rights` value, so
    # the holder, URI and description stay consistent with the string.
    match <- Filter(
      function(d) identical(d[["metadata"]][["license"]][["rights"]], rights),
      databases
    )
    if (length(match) > 0) {
      metadata[["license"]] <- match[[1]][["metadata"]][["license"]]
    } else {
      metadata[["license"]][["rights"]] <- rights
      metadata[["license"]][["description"]] <- NULL
      metadata[["license"]][["rights_URI"]] <- NULL
    }
    return(metadata)
  }

  if (length(declared) > 1) {
    stop(
      "The databases being merged declare different licences:\n  ",
      paste(declared, collapse = "\n  "), "\n",
      "Merging them produces an object whose licence this function cannot ",
      "infer -- the previous behaviour was to keep the first argument's and ",
      "silently discard the rest.\n",
      "Pass `rights = ` (or a full `license = ` block) to state what the ",
      "merged database is licensed under.",
      call. = FALSE
    )
  }

  metadata
}
