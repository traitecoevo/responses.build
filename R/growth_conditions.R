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

  tc <- util_context_levels(contexts)

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


#' Context levels, with their ids split out
#'
#' `link_vals` holds a comma-separated *list* of ids -- one context value can
#' apply to several contexts -- so anything joining on it has to split first or
#' it silently matches nothing.
#'
#' Not filtered to `treatment_context`. A quantity can hang off any category:
#' `Aspinwall_2017` records seed provenance as a treatment context because the
#' provenances were the experiment, while `Drake_2017` records it as an entity
#' context because they were simply where its plants came from. Both are
#' provenance.
#'
#' @param contexts The processed contexts table
#'
#' @return A tibble of context_property, value, category and one id per row
#' @importFrom rlang .data
#' @noRd
util_context_levels <- function(contexts) {

  empty <- tibble::tibble(context_property = character(0), value = character(0),
                          category = character(0), link_id = character(0),
                          link_vals = character(0))

  if (is.null(contexts) || nrow(contexts) == 0) return(empty)

  contexts %>%
    dplyr::filter(!is.na(.data$link_vals)) %>%
    dplyr::select(dplyr::all_of(c("context_property", "value", "category",
                                  "link_id", "link_vals"))) %>%
    tidyr::separate_rows("link_vals", sep = ",\\s*") %>%
    dplyr::mutate(link_vals = trimws(.data$link_vals)) %>%
    dplyr::filter(.data$link_vals != "") %>%
    dplyr::distinct()
}


#' Load the vocabulary of provenance properties
#'
#' Reads `config/provenance.yml` -- what can be recorded about where the plant
#' material came from.
#'
#' @param path Path to the definitions. Defaults to `config/provenance.yml`.
#'
#' @return A named list, empty if there is no file
#' @export
get_provenance_properties <- function(path = NULL) {

  if (is.null(path)) {
    if (!file.exists("config/provenance.yml")) return(list())
    path <- "config/provenance.yml"
  }

  if (!file.exists(path)) {
    stop("No provenance definitions at ", path, call. = FALSE)
  }

  out <- yaml::read_yaml(path)

  if (is.null(out[["provenance"]][["elements"]])) {
    stop(path, " has no `provenance: elements:` block.", call. = FALSE)
  }

  out[["provenance"]][["elements"]]
}


#' Build the provenance table
#'
#' Where the plant material came from, as data rather than as a sentence.
#'
#' Provenance was previously split two ways and encoded differently in each
#' dataset that had it: `Aspinwall_2017` as a treatment context plus two
#' quantities filed under growth conditions -- which they are not, being
#' properties of a seed origin rather than of a growing environment -- and
#' `Drake_2017` as an entity context with coordinates in prose.
#'
#' The context it hangs off may be of any category, because whether a
#' provenance is a treatment depends on whether the study chose provenances
#' deliberately. That is a fact about the experiment, not about the provenance.
#'
#' @param metadata A dataset's metadata
#' @param contexts The processed contexts table
#' @param properties Definitions, from [get_provenance_properties()]
#' @param dataset_id The dataset, used in error messages
#'
#' @return A tibble with one row per property
#' @importFrom rlang .data
#' @noRd
process_create_provenance <- function(metadata, contexts, properties = list(),
                                      dataset_id = "this dataset") {

  empty <- tibble::tibble(
    dataset_id = character(0), context_id = character(0),
    context_property = character(0), label = character(0),
    property = character(0), value = character(0), unit = character(0)
  )

  blocks <- metadata[["provenance"]]

  if (is.null(blocks) || length(blocks) == 0) return(empty)

  levels <- util_context_levels(contexts)
  rows <- list()

  for (i in seq_along(blocks)) {
    b <- blocks[[i]]
    where <- sprintf("%s, provenance block %d", dataset_id, i)

    for (f in c("context_property", "value")) {
      if (is.null(b[[f]])) {
        stop(where, ": no `", f, "`. A provenance has to say which context ",
             "level it describes.", call. = FALSE)
      }
    }

    hit <- levels %>%
      dplyr::filter(.data$context_property == b[["context_property"]],
                    .data$value == b[["value"]])

    if (nrow(hit) == 0) {
      stop(where, ": no context has `", b[["context_property"]], "` = '",
           b[["value"]], "'.", call. = FALSE)
    }

    for (e in b[["properties"]]) {
      name <- e[["property"]]

      if (is.null(name)) {
        stop(where, ": an entry has no `property`.", call. = FALSE)
      }
      if (length(properties) > 0 && is.null(properties[[name]])) {
        stop(where, ": property '", name, "' is not defined in ",
             "config/provenance.yml. Known: ",
             paste(names(properties), collapse = ", "), call. = FALSE)
      }
      if (is.null(e[["value"]])) {
        stop(where, ", property '", name, "': no `value`.", call. = FALSE)
      }

      rows[[length(rows) + 1]] <- tibble::tibble(
        dataset_id = dataset_id, context_id = hit$link_vals,
        context_property = b[["context_property"]], label = b[["value"]],
        property = name, value = as.character(e[["value"]]),
        unit = as.character(properties[[name]][["unit"]] %||% NA_character_)
      )
    }
  }

  dplyr::bind_rows(rows) %>%
    dplyr::arrange(.data$dataset_id, .data$context_id, .data$property)
}
