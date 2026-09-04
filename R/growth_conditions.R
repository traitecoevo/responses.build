#' Load the vocabulary of growth conditions
#'
#' Reads `config/growth_conditions.yml` -- the quantities the conditions plants
#' were grown under can be described by, so `growth_air_temperature_day` means
#' the same thing in every study.
#'
#' @param path Path to the definitions. Defaults to
#'   `config/growth_conditions.yml`, if it exists.
#'
#' @return A named list of condition definitions, empty if there is no file
#' @export
get_growth_conditions <- function(path = NULL) {

  if (is.null(path)) {
    if (!file.exists("config/growth_conditions.yml")) return(list())
    path <- "config/growth_conditions.yml"
  }

  if (!file.exists(path)) {
    stop("No growth condition definitions at ", path, call. = FALSE)
  }

  out <- yaml::read_yaml(path)

  if (is.null(out[["growth_conditions"]][["elements"]])) {
    stop(path, " has no `growth_conditions: elements:` block.", call. = FALSE)
  }

  out[["growth_conditions"]][["elements"]]
}


#' Build the growth conditions table
#'
#' Turns a dataset's `growth_conditions:` block into one row per condition, and
#' links it to a `treatment_context_id` where the study manipulated that
#' condition.
#'
#' # Manipulated or not, it is still a growth condition
#'
#' The table this replaces recorded only what an experiment *changed*. A study
#' that grew everything at 26 C recorded nothing; one that grew plants at 26 and
#' 32 recorded both. So the constant-condition studies -- the majority -- told a
#' cross-study analysis nothing about the conditions their plants grew in, even
#' where the paper stated them.
#'
#' An entry that names a treatment level gets that level's
#' `treatment_context_id` and `manipulated = TRUE`. An entry that names none
#' applies to the whole dataset and is `manipulated = FALSE`.
#'
#' # A missing number is data
#'
#' Most water treatments in the AusFizz corpus report `well-watered` against
#' `water deficit` and no quantity at all. Those get a row with a `label` and no
#' condition. That is the honest record: the study did not say how much water.
#' Filling it in with a plausible number would make the table worse.
#'
#' @param metadata A dataset's metadata
#' @param contexts The processed contexts table, giving each treatment level
#'   its `treatment_context_id`
#' @param conditions Condition definitions, from [get_growth_conditions()]
#' @param dataset_id The dataset, used in error messages
#'
#' @return A tibble with one row per condition
#' @importFrom rlang .data
#' @noRd
process_create_growth_conditions <- function(metadata, contexts, conditions = list(),
                                             dataset_id = "this dataset") {

  empty <- tibble::tibble(
    dataset_id = character(0), treatment_context_id = character(0),
    context_property = character(0), label = character(0),
    condition = character(0), value = character(0), unit = character(0),
    manipulated = character(0)
  )

  blocks <- metadata[["growth_conditions"]]

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
    where <- sprintf("%s, growth_conditions block %d", dataset_id, i)

    # An entry either names a treatment level, or applies to the whole dataset.
    manipulated <- !is.null(b[["context_property"]])

    if (manipulated) {
      if (is.null(b[["value"]])) {
        stop(where, ": names `context_property` but no `value`, so it does not ",
             "say which treatment level it describes.", call. = FALSE)
      }
      ids <- tc$link_vals[tc$context_property == b[["context_property"]] &
                            tc$value == b[["value"]]]
      if (length(ids) == 0) {
        stop(where, ": no treatment context has `", b[["context_property"]],
             "` = \'", b[["value"]], "\'. A condition must describe a level ",
             "that exists, or it describes nothing.", call. = FALSE)
      }
      label <- b[["value"]]
      property <- b[["context_property"]]
    } else {
      ids <- NA_character_
      label <- NA_character_
      property <- NA_character_
    }

    entries <- b[["conditions"]]

    if (length(entries) == 0) {
      if (!manipulated) {
        stop(where, ": applies to the whole dataset but lists no conditions, ",
             "so it records nothing.", call. = FALSE)
      }
      # A treatment level with no stated quantity. Recorded, with its label.
      rows[[length(rows) + 1]] <- tibble::tibble(
        dataset_id = dataset_id, treatment_context_id = ids,
        context_property = property, label = label,
        condition = NA_character_, value = NA_character_, unit = NA_character_,
        manipulated = "TRUE"
      )
      next
    }

    for (e in entries) {
      name <- e[["condition"]]

      if (is.null(name)) {
        stop(where, ": an entry has no `condition`.", call. = FALSE)
      }
      if (length(conditions) > 0 && is.null(conditions[[name]])) {
        stop(where, ": condition \'", name, "\' is not defined in ",
             "config/growth_conditions.yml. Known: ",
             paste(names(conditions), collapse = ", "), call. = FALSE)
      }
      if (is.null(e[["value"]])) {
        stop(where, ", condition \'", name, "\': no `value`. A condition ",
             "without a number says less than no condition at all -- leave it ",
             "out.", call. = FALSE)
      }

      # The unit belongs to the condition, not to whoever wrote the dataset. A
      # dataset naming a different one is stating a disagreement, not a variant.
      declared <- e[["unit"]]
      canonical <- conditions[[name]][["unit"]]
      if (!is.null(declared) && !is.null(canonical) &&
          !identical(as.character(declared), as.character(canonical))) {
        stop(where, ", condition \'", name, "\': unit \'", declared,
             "\' but the condition is defined in \'", canonical, "\'.",
             call. = FALSE)
      }

      rows[[length(rows) + 1]] <- tibble::tibble(
        dataset_id = dataset_id, treatment_context_id = ids,
        context_property = property, label = label,
        condition = name, value = as.character(e[["value"]]),
        unit = as.character(canonical %||% declared %||% NA_character_),
        # Character, like every other column of every other table here, so a
        # written CSV reads back as what the database held. `as.logical()` on
        # it round-trips.
        manipulated = as.character(manipulated)
      )
    }
  }

  dplyr::bind_rows(rows) %>%
    dplyr::arrange(.data$dataset_id, .data$treatment_context_id, .data$condition)
}
