#' Load the data types a compilation measures
#'
#' Reads `config/data_types.yml`, which records what each `data_type` is and --
#' the part the build needs -- which variable each is measured *across*.
#'
#' A compilation without the file gets an empty list. Curves are still
#' identified; they just carry no `driver`, because nothing said what the driver
#' is. That is the honest result, and it keeps a repository that has not written
#' the file yet building.
#'
#' @param path Path to the data type definitions. Defaults to
#'   `config/data_types.yml`, if it exists.
#'
#' @return A named list of data type definitions, possibly empty
#' @export
get_data_types <- function(path = NULL) {

  if (is.null(path)) {
    if (!file.exists("config/data_types.yml")) return(list())
    path <- "config/data_types.yml"
  }

  if (!file.exists(path)) {
    stop("No data type definitions at ", path, call. = FALSE)
  }

  out <- yaml::read_yaml(path)

  if (is.null(out[["data_types"]][["elements"]])) {
    stop(path, " has no `data_types: elements:` block.", call. = FALSE)
  }

  out[["data_types"]][["elements"]]
}


#' Identify the curves in a processed traits table
#'
#' Builds the two tables that make a response curve addressable:
#'
#' \describe{
#'   \item{`curves`}{one row per curve -- what it is, what it was measured on,
#'     what it was measured across, and how many points it has}
#'   \item{`curve_points`}{one row per point, one column per variable. The shape
#'     a plant physiologist works in, without a pivot}
#' }
#'
#' # What identifies a curve
#'
#' `(dataset_id, observation_id, method_context_id)`. An `observation_id` is one
#' entity at one point in time; a `method_context_id` distinguishes measurements
#' of the same entity made under different method settings. For an A-Ci-T
#' dataset that is exactly one A-Ci curve per cuvette temperature.
#'
#' This is derivable today, and every notebook derives it -- but nothing names
#' it, so ten of the 30 AusFizz datasets smuggle a curve number through
#' `individual_id` instead, each with its own local convention.
#'
#' # Points, and why their order is load-bearing
#'
#' `point_id` comes from `repeat_measurements_id`, which the build generates as
#' the row number within
#' `(observation_id, trait_name, value_type, method_id, method_context_id)`.
#' Every variable of a curve is numbered in source-file order, so point 3 of `A`
#' and point 3 of `Ci` are the same row of the original CSV. That is what lets
#' the two be paired.
#'
#' It follows that a dataset which does not set `repeat_measurements_id` has no
#' point ordering at all, and its curve is a bag of values rather than a curve.
#' Those get `point_id` from row order here, and are reported by
#' [check_curve_pairing()].
#'
#' # A single point is a curve of length one
#'
#' Most observations are not curves: 22,673 of 25,547 groups in the 2026-08
#' AusFizz build are single points -- survey, Amax, Rd. They are curves with
#' `n_points = 1` and no driver, not a special case, and they appear in both
#' tables like anything else.
#'
#' @param traits The processed traits table
#' @param contexts The processed contexts table, used to read `data_type` and
#'   `instrument` off the method context
#' @param data_types Data type definitions, as returned by [get_data_types()]
#'
#' @return A list with elements `curves` and `curve_points`
#' @importFrom rlang .data
#' @noRd
process_create_curves <- function(traits, contexts, data_types = list()) {

  empty <- list(
    curves = tibble::tibble(
      dataset_id = character(0), curve_id = character(0),
      data_type = character(0), driver = character(0),
      driver_outer = character(0), taxon_name = character(0),
      observation_id = character(0), individual_id = character(0),
      population_id = character(0), collection_date = character(0),
      location_id = character(0), treatment_context_id = character(0),
      entity_context_id = character(0), temporal_context_id = character(0),
      method_context_id = character(0), instrument = character(0),
      n_points = character(0), point_order = character(0)
    ),
    curve_points = tibble::tibble(
      dataset_id = character(0), curve_id = character(0), point_id = character(0)
    )
  )

  if (is.null(traits) || nrow(traits) == 0) return(empty)

  # `data_type` and `instrument` are recorded as method contexts in every
  # dataset. Stage 3 promotes them to fields of their own; until then, read
  # them back off the context table so the curve tables are right now.
  from_context <- function(property) {
    if (is.null(contexts) || nrow(contexts) == 0) return(NULL)
    ctx <- contexts %>%
      dplyr::filter(.data$context_property == property) %>%
      dplyr::select(dplyr::all_of(c("dataset_id", "link_id", "link_vals", "value")))
    if (nrow(ctx) == 0) return(NULL)
    ctx
  }

  join_context <- function(data, property, into) {
    ctx <- from_context(property)
    if (is.null(ctx)) {
      data[[into]] <- NA_character_
      return(data)
    }

    # A context links through whichever id column `link_id` names, and
    # `link_vals` holds a comma-separated *list* of those ids -- one context
    # value can apply to several method contexts. Joining on the raw string
    # silently matches nothing whenever a value covers more than one id.
    link <- stats::na.omit(unique(ctx$link_id))
    if (length(link) == 0 || !link[[1]] %in% names(data)) {
      data[[into]] <- NA_character_
      return(data)
    }
    link <- link[[1]]

    ctx <-
      ctx %>%
      dplyr::filter(!is.na(.data$link_vals)) %>%
      dplyr::select(dplyr::all_of(c("dataset_id", "link_vals", "value"))) %>%
      tidyr::separate_rows("link_vals", sep = ",\\s*") %>%
      dplyr::mutate(link_vals = trimws(.data$link_vals)) %>%
      dplyr::filter(.data$link_vals != "") %>%
      dplyr::distinct()

    # One id must resolve to one value of one property. More than one means the
    # context table disagrees with itself, and picking one would hide it.
    clash <- ctx %>% dplyr::count(.data$dataset_id, .data$link_vals) %>%
      dplyr::filter(.data$n > 1)
    if (nrow(clash) > 0) {
      warning(
        "Context property '", property, "' gives more than one value for ",
        link, " ", paste(utils::head(clash$link_vals, 5), collapse = ", "),
        ". Taking the first; the context table needs fixing.",
        call. = FALSE
      )
      ctx <- ctx %>%
        dplyr::group_by(.data$dataset_id, .data$link_vals) %>%
        dplyr::slice(1) %>%
        dplyr::ungroup()
    }

    names(ctx) <- c("dataset_id", link, into)
    dplyr::left_join(data, ctx, by = c("dataset_id", link))
  }

  # ---- one row per curve -------------------------------------------------

  keys <- c("dataset_id", "observation_id", "method_context_id")

  curves <-
    traits %>%
    dplyr::distinct(dplyr::across(dplyr::all_of(c(
      keys, "taxon_name", "individual_id", "population_id", "collection_date",
      "location_id", "treatment_context_id", "entity_context_id",
      "temporal_context_id"
    )))) %>%
    dplyr::arrange(.data$dataset_id, .data$observation_id, .data$method_context_id)

  curves <- curves %>%
    dplyr::group_by(.data$dataset_id) %>%
    dplyr::mutate(
      curve_id = process_generate_id(
        paste(.data$observation_id, .data$method_context_id, sep = "-"), "",
        sort = TRUE
      )
    ) %>%
    dplyr::ungroup()

  curves <- curves %>%
    join_context("data_type", "data_type") %>%
    join_context("instrument", "instrument")

  # `driver` is a property of the data type, not of the dataset
  driver_of <- function(dt, field) {
    vapply(
      dt,
      function(x) {
        if (is.na(x) || is.null(data_types[[x]])) return(NA_character_)
        v <- data_types[[x]][[field]]
        if (is.null(v) || identical(v, ".na") || is.na(v)) return(NA_character_)
        as.character(v)
      },
      character(1)
    )
  }

  curves$driver <- unname(driver_of(curves$data_type, "driver"))
  curves$driver_outer <- unname(driver_of(curves$data_type, "driver_outer"))

  # ---- one row per point, one column per variable -------------------------

  points <-
    traits %>%
    dplyr::left_join(
      curves %>% dplyr::select(dplyr::all_of(c(keys, "curve_id"))),
      by = keys
    ) %>%
    dplyr::mutate(
      # Where `repeat_measurements_id` is absent there is no recorded order.
      # Substituting one would look like data; `point_order` says it is not.
      point_order = dplyr::if_else(
        is.na(.data$repeat_measurements_id), "file order", "recorded"
      ),
      point_id = dplyr::if_else(
        is.na(.data$repeat_measurements_id), "01", .data$repeat_measurements_id
      )
    )

  order_of <-
    points %>%
    dplyr::group_by(.data$dataset_id, .data$curve_id) %>%
    dplyr::summarise(
      point_order = if (any(.data$point_order == "recorded")) "recorded" else "file order",
      .groups = "drop"
    )

  # `curve_points` is wide, so it holds one value per variable per point. Where
  # the source has two -- the same variable measured under different
  # `method_id`s within one curve -- there is no cell for the second.
  #
  # `method_id` cannot simply join the curve key to separate them. Measured on
  # AusFizz: doing so would split 75 curves across two datasets, and in
  # Ghannoum_2010 it fragments a complete eight-variable curve into that curve
  # plus a one-variable remnant, because `Tleaf` alone was measured twice. In
  # Bloomfield_2014_a different variables use different methods, so splitting
  # would break the pairing outright.
  #
  # So: keep the curve whole, resolve deterministically by lowest `method_id`,
  # and report every conflict. Nothing is lost -- `traits` still holds both --
  # but the wide view has to pick one, and it says which.
  # This is not warned about at build time. For curve data a conflict is rare
  # and worth looking at; for trait-style data, where one trait routinely has
  # several methods, it is the normal case and fires on every build -- 45 times
  # on a single test fixture. A warning nobody can act on is a warning everybody
  # learns to ignore. `check_curve_points_conflicts()` reports them on demand,
  # the same way `check_pivot_wider()` already does for the traits table.
  curve_points <-
    points %>%
    dplyr::arrange(.data$method_id) %>%
    dplyr::select(dplyr::all_of(c(
      "dataset_id", "curve_id", "point_id", "trait_name", "value"
    ))) %>%
    tidyr::pivot_wider(
      names_from = "trait_name", values_from = "value",
      values_fn = function(x) x[[1]]
    ) %>%
    dplyr::arrange(.data$dataset_id, .data$curve_id, .data$point_id)

  n <- curve_points %>%
    dplyr::count(.data$dataset_id, .data$curve_id, name = "n_points")

  curves <-
    curves %>%
    dplyr::left_join(n, by = c("dataset_id", "curve_id")) %>%
    dplyr::left_join(order_of, by = c("dataset_id", "curve_id")) %>%
    dplyr::mutate(n_points = as.character(dplyr::coalesce(.data$n_points, 0L))) %>%
    dplyr::select(dplyr::all_of(c(
      "dataset_id", "curve_id", "data_type", "driver", "driver_outer",
      "taxon_name", "observation_id", "individual_id", "population_id",
      "collection_date", "location_id", "treatment_context_id",
      "entity_context_id", "temporal_context_id", "method_context_id",
      "instrument", "n_points", "point_order"
    )))

  list(curves = curves, curve_points = curve_points)
}


#' Report curves whose points cannot be paired
#'
#' Pairing `A` with `Ci` across a curve rests on both being numbered in
#' source-file order by `repeat_measurements_id`. A dataset that never sets it
#' has no ordering, so its variables cannot be matched point to point -- the
#' values are all present, but which `A` goes with which `Ci` is not recorded.
#'
#' This is not a build failure. A single-point observation needs no ordering,
#' and neither does a dataset holding one variable. It is a failure only where a
#' curve has several points *and* several variables, which is where the pairing
#' actually carries information.
#'
#' @param database A built database, or a list with `curves` and `curve_points`
#'
#' @return A tibble of curves with more than one point and more than one
#'   variable but no recorded point order. Empty if there are none.
#' @section Note:
#' `n_points` is character, like every other column of every other table in
#' this data model, so that a written CSV reads back as what the database held.
#' @importFrom rlang .data
#' @export
check_curve_pairing <- function(database) {

  curves <- database[["curves"]]
  points <- database[["curve_points"]]

  if (is.null(curves) || is.null(points) || nrow(curves) == 0) {
    return(tibble::tibble(
      dataset_id = character(0), curve_id = character(0),
      n_points = integer(0), n_variables = integer(0)
    ))
  }

  value_cols <- setdiff(names(points), c("dataset_id", "curve_id", "point_id"))

  n_vars <-
    points %>%
    dplyr::group_by(.data$dataset_id, .data$curve_id) %>%
    dplyr::summarise(
      n_variables = sum(vapply(
        dplyr::pick(dplyr::all_of(value_cols)),
        function(col) any(!is.na(col)), logical(1)
      )),
      .groups = "drop"
    )

  curves %>%
    dplyr::left_join(n_vars, by = c("dataset_id", "curve_id")) %>%
    dplyr::filter(
      .data$point_order == "file order",
      as.integer(.data$n_points) > 1,
      .data$n_variables > 1
    ) %>%
    dplyr::select(dplyr::all_of(c(
      "dataset_id", "curve_id", "n_points", "n_variables"
    )))
}


#' Report variables with more than one value at the same point of a curve
#'
#' `curve_points` is wide, so it has one cell per variable per point. Where the
#' source measured the same variable twice within one curve -- under different
#' `method_id`s -- only one value fits, and the lowest `method_id` wins.
#'
#' This finds those, so the choice is auditable. The `traits` table is
#' unaffected and still holds every value.
#'
#' It is not warned about at build time. For curve data a conflict is rare and
#' worth looking at; for trait-style data, where one trait routinely carries
#' several methods, it is the normal case and would fire on every build.
#'
#' @param database A built database
#'
#' @return A tibble of conflicting variable-point combinations, with the value
#'   and `method_id` each came from, and `used` marking the one that reached
#'   `curve_points`. Empty if there are none.
#' @importFrom rlang .data
#' @export
check_curve_points_conflicts <- function(database) {

  empty <- tibble::tibble(
    dataset_id = character(0), curve_id = character(0), point_id = character(0),
    trait_name = character(0), method_id = character(0), value = character(0),
    used = logical(0)
  )

  traits <- database[["traits"]]
  curves <- database[["curves"]]

  if (is.null(traits) || is.null(curves) || nrow(curves) == 0) return(empty)

  keys <- c("dataset_id", "observation_id", "method_context_id")

  traits %>%
    dplyr::left_join(
      curves %>% dplyr::select(dplyr::all_of(c(keys, "curve_id"))),
      by = keys
    ) %>%
    dplyr::mutate(
      point_id = dplyr::if_else(
        is.na(.data$repeat_measurements_id), "01", .data$repeat_measurements_id
      )
    ) %>%
    dplyr::group_by(
      .data$dataset_id, .data$curve_id, .data$point_id, .data$trait_name
    ) %>%
    dplyr::filter(dplyr::n() > 1) %>%
    dplyr::arrange(.data$method_id, .by_group = TRUE) %>%
    dplyr::mutate(used = dplyr::row_number() == 1) %>%
    dplyr::ungroup() %>%
    dplyr::select(dplyr::all_of(c(
      "dataset_id", "curve_id", "point_id", "trait_name", "method_id",
      "value", "used"
    ))) %>%
    dplyr::arrange(
      .data$dataset_id, .data$curve_id, .data$point_id, .data$trait_name,
      .data$method_id
    )
}
