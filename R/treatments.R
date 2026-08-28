#' Load the vocabulary of treatment factors
#'
#' Reads `config/treatment_factors.yml` — the quantities a treatment can be
#' described by, so `growth_air_temperature_offset` means the same thing in
#' every study.
#'
#' @param path Path to the factor definitions. Defaults to
#'   `config/treatment_factors.yml`, if it exists.
#'
#' @return A named list of factor definitions, empty if there is no file
#' @export
get_treatment_factors <- function(path = NULL) {

  if (is.null(path)) {
    if (!file.exists("config/treatment_factors.yml")) return(list())
    path <- "config/treatment_factors.yml"
  }

  if (!file.exists(path)) {
    stop("No treatment factors at ", path, call. = FALSE)
  }

  out <- yaml::read_yaml(path)

  if (is.null(out[["treatment_factors"]][["elements"]])) {
    stop(path, " has no `treatment_factors: elements:` block.", call. = FALSE)
  }

  out[["treatment_factors"]][["elements"]]
}


#' Build the treatments table
#'
#' Turns a dataset's `treatments:` block into one row per treatment level per
#' factor, linked to the `treatment_context_id` the trait rows already carry.
#'
#' # Why this is additive rather than a replacement
#'
#' A treatment is recorded twice over: as a `treatment_context` -- which is what
#' gives it an id and links it to the measurements -- and, from here, as a set
#' of numeric factors saying what it actually did. The context stays exactly
#' where it was. Moving treatments out of `contexts` would relabel
#' `treatment_context_id`, and there is nothing to gain by it: the context
#' answers "which rows had this treatment", the factors answer "what was the
#' treatment", and those are different questions.
#'
#' # A missing factor is data
#'
#' Most water treatments in the 2026-08 AusFizz corpus report `well-watered`
#' against `water deficit` and no quantity at all. Those get a row with a
#' `label` and no factor. That is the honest record: the study did not say how
#' much water. Filling it in with a plausible number would make the table worse,
#' not more complete.
#'
#' @param metadata A dataset's metadata
#' @param contexts The processed contexts table, giving each treatment level
#'   its `treatment_context_id`
#' @param factors Factor definitions, from [get_treatment_factors()]
#' @param dataset_id The dataset, used in error messages
#'
#' @return A tibble with one row per treatment level per factor
#' @importFrom rlang .data
#' @noRd
process_create_treatments <- function(metadata, contexts, factors = list(),
                                      dataset_id = "this dataset") {

  empty <- tibble::tibble(
    dataset_id = character(0), treatment_context_id = character(0),
    context_property = character(0), label = character(0),
    factor = character(0), value = character(0), unit = character(0)
  )

  blocks <- metadata[["treatments"]]

  if (is.null(blocks) || length(blocks) == 0) return(empty)

  # `link_vals` is a comma-separated list of ids, so it has to be split before
  # anything can join on it.
  tc <- contexts

  if (!is.null(tc) && nrow(tc) > 0) {
    tc <- tc %>%
      dplyr::filter(.data$category == "treatment_context", !is.na(.data$link_vals)) %>%
      dplyr::select(dplyr::all_of(c("context_property", "value", "link_vals"))) %>%
      tidyr::separate_rows("link_vals", sep = ",\\s*") %>%
      dplyr::mutate(link_vals = trimws(.data$link_vals)) %>%
      dplyr::distinct()
  } else {
    tc <- tibble::tibble(context_property = character(0), value = character(0),
                         link_vals = character(0))
  }

  rows <- list()

  for (i in seq_along(blocks)) {
    b <- blocks[[i]]
    where <- sprintf("%s, treatments block %d", dataset_id, i)

    for (f in c("context_property", "value")) {
      if (is.null(b[[f]])) {
        stop(where, ": no `", f, "`. A treatment has to say which context ",
             "level it describes.", call. = FALSE)
      }
    }

    ids <- tc$link_vals[tc$context_property == b[["context_property"]] &
                          tc$value == b[["value"]]]

    if (length(ids) == 0) {
      stop(where, ": no treatment context has `", b[["context_property"]],
           "` = '", b[["value"]], "'. A treatment must describe a level that ",
           "exists, or it describes nothing.", call. = FALSE)
    }

    if (length(b[["factors"]]) == 0) {
      # A level with no stated quantity. Recorded, with its verbatim label.
      rows[[length(rows) + 1]] <- tibble::tibble(
        dataset_id = dataset_id, treatment_context_id = ids,
        context_property = b[["context_property"]],
        label = b[["value"]], factor = NA_character_,
        value = NA_character_, unit = NA_character_
      )
      next
    }

    for (fac in b[["factors"]]) {
      name <- fac[["factor"]]

      if (is.null(name)) {
        stop(where, ": a factor entry has no `factor`.", call. = FALSE)
      }
      if (length(factors) > 0 && is.null(factors[[name]])) {
        stop(where, ": factor '", name, "' is not defined in ",
             "config/treatment_factors.yml. Known: ",
             paste(names(factors), collapse = ", "), call. = FALSE)
      }
      if (is.null(fac[["value"]])) {
        stop(where, ", factor '", name, "': no `value`. A factor without a ",
             "number says less than no factor at all -- leave it out.",
             call. = FALSE)
      }

      # The unit belongs to the factor, not to whoever wrote the dataset. A
      # dataset naming a different one is stating a disagreement, not a variant.
      declared <- fac[["unit"]]
      canonical <- factors[[name]][["unit"]]
      if (!is.null(declared) && !is.null(canonical) &&
          !identical(as.character(declared), as.character(canonical))) {
        stop(where, ", factor '", name, "': unit '", declared,
             "' but the factor is defined in '", canonical, "'.", call. = FALSE)
      }

      rows[[length(rows) + 1]] <- tibble::tibble(
        dataset_id = dataset_id, treatment_context_id = ids,
        context_property = b[["context_property"]],
        label = b[["value"]], factor = name,
        value = as.character(fac[["value"]]),
        unit = as.character(canonical %||% declared %||% NA_character_)
      )
    }
  }

  dplyr::bind_rows(rows) %>%
    dplyr::arrange(.data$dataset_id, .data$treatment_context_id, .data$factor)
}
