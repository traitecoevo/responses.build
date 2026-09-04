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


#' Identify the responses in a processed readings table
#'
#' Builds `responses` -- one row per response, saying what it is, what it was measured
#' on, what it was measured across and how many points it holds -- and returns
#' the `response_id` / `point_id` keys to attach to each reading.
#'
#' # Why there is no stored wide table
#'
#' An earlier version also emitted `curve_points`: one row per point, one column
#' per variable. It was dropped, because a wide table cannot hold what a reading
#' carries besides its value. Measured on AusFizz: 17 `(dataset, variable,
#' method_id)` groups have more than one `value_type` *and* more than one
#' `replicates` -- some variables recorded as a mean of five, others raw. A wide
#' table has one cell per `(point, variable)`; there is nowhere to put that.
#'
#' So the long table is the lossless form and wide is a view, not the other way
#' round. [response_pivot_wider()] makes the view on demand, and it is one line
#' with nothing to re-derive now that `response_id` exists -- which was the actual
#' missing thing all along.
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
#' Most responses are not curves: 22,680 of 25,699 in the 2026-08 AusFizz build in the 2026-08
#' are single points -- survey, Amax, Rd. A *curve* is a response measured
#' across a driver with more than one point; the rest are responses too, which
#' is why the table is not called `curves`.
#'
#' @param traits The processed traits table
#' @param contexts The processed contexts table, used to read `data_type` and
#'   `instrument` off the method context
#' @param data_types Data type definitions, as returned by [get_data_types()]
#'
#' @return A tibble with one row per reading: `response_id`, `point_id`,
#'   `data_type`, `point_order`
#' @importFrom rlang .data
#' @noRd
process_create_responses <- function(traits, contexts, data_types = list()) {

  empty <- tibble::tibble(
    response_id = character(0), point_id = character(0),
    data_type = character(0), point_order = character(0)
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

  # ---- one row per response ----------------------------------------------

  # Which data type each reading belongs to, needed *before* the responses are
  # formed because it decides how they are formed -- see `spans_time` below.
  traits <- traits %>% join_context("data_type", ".data_type")

  spans_time <- names(data_types)[vapply(
    data_types, function(x) isTRUE(x[["spans_time"]]), logical(1)
  )]

  # A response is one entity measured one way, and normally that is one
  # occasion: `observation_id` includes `collection_date`, so a new day is a
  # new response.
  #
  # For a data type measured *across* days that is wrong. A dry-down is one
  # plant measured repeatedly as it dries, and dating it apart shatters the
  # curve: `gs_drydown` came out as 1,378 responses of a single point each
  # where it is 196 plants measured a median of 7 times. The driver varies
  # between days, which is the whole design of the measurement.
  #
  # So a data type may declare `spans_time: yes`, and its responses group
  # across `collection_date` and `temporal_context_id` -- the two components of
  # `observation_id` that separate occasions.
  traits <- traits %>%
    dplyr::mutate(
      .response_key = dplyr::if_else(
        !is.na(.data$.data_type) & .data$.data_type %in% spans_time,
        paste(.data$taxon_name, .data$population_id, .data$individual_id,
              .data$entity_context_id, .data$method_context_id, sep = "-"),
        paste(.data$observation_id, .data$method_context_id, sep = "-")
      )
    )

  keys <- c("dataset_id", ".response_key")

  responses <-
    traits %>%
    dplyr::group_by(.data$dataset_id, .data$.response_key) %>%
    dplyr::summarise(
      dplyr::across(
        dplyr::all_of(c("observation_id", "method_context_id", "taxon_name",
                        "individual_id", "population_id", "location_id",
                        "treatment_context_id", "entity_context_id",
                        "temporal_context_id")),
        ~ .x[[1]]
      ),
      # A response spanning days has no single date; report the range it covers
      collection_date = if (dplyr::n_distinct(.data$collection_date) == 1) {
        .data$collection_date[[1]]
      } else {
        paste(range(util_sort_locale_independent(unique(.data$collection_date))),
              collapse = "/")
      },
      .groups = "drop"
    ) %>%
    dplyr::arrange(.data$dataset_id, .data$.response_key)

  responses <- responses %>%
    dplyr::group_by(.data$dataset_id) %>%
    dplyr::mutate(
      response_id = process_generate_id(.data$.response_key, "", sort = TRUE)
    ) %>%
    dplyr::ungroup()

  responses <- responses %>%
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

  responses$driver <- unname(driver_of(responses$data_type, "driver"))
  responses$driver_outer <- unname(driver_of(responses$data_type, "driver_outer"))

  # ---- one row per point, one column per variable -------------------------

  points <-
    traits %>%
    dplyr::left_join(
      responses %>% dplyr::select(dplyr::all_of(c(keys, "response_id"))),
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

  # A response that spans days is ordered *by day*: each occasion is one point,
  # and `repeat_measurements_id` -- numbered within an occasion -- says nothing
  # about which came first. The date does, and it is recorded, so the order is
  # `recorded` rather than file order.
  if (length(spans_time) > 0) {
    spanning <- points$.data_type %in% spans_time & !is.na(points$.data_type)

    if (any(spanning)) {
      points[spanning, ] <- points[spanning, ] %>%
        dplyr::group_by(.data$dataset_id, .data$response_id) %>%
        dplyr::mutate(
          point_id = paste(.data$collection_date, .data$point_id) %>%
            process_generate_id("", sort = TRUE),
          point_order = "recorded"
        ) %>%
        dplyr::ungroup()
    }
  }

  # `point_order` is a property of the whole response, not of one reading: if
  # any reading in it carries a recorded order, the response has one.
  order_of <-
    points %>%
    dplyr::group_by(.data$dataset_id, .data$response_id) %>%
    dplyr::summarise(
      .order = if (any(.data$point_order == "recorded")) "recorded" else "file order",
      .groups = "drop"
    )

  points %>%
    dplyr::select(-dplyr::all_of("point_order")) %>%
    dplyr::left_join(order_of, by = c("dataset_id", "response_id")) %>%
    dplyr::transmute(
      response_id = .data$response_id,
      point_id = .data$point_id,
      data_type = .data$.data_type,
      point_order = .data$.order
    )
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
#' @param database A built database
#'
#' @return A tibble of curves with more than one point and more than one
#'   variable but no recorded point order. Empty if there are none.
#' @section Note:
#' `n_points` is character, like every other column of every other table in
#' this data model, so that a written CSV reads back as what the database held.
#' @importFrom rlang .data
#' @export
check_curve_pairing <- function(database) {

  points <- database[["measurements"]]

  if (is.null(points) || nrow(points) == 0) {
    return(tibble::tibble(
      dataset_id = character(0), response_id = character(0),
      n_points = integer(0), n_variables = integer(0)
    ))
  }

  responses <-
    points %>%
    dplyr::group_by(.data$dataset_id, .data$response_id) %>%
    dplyr::summarise(
      point_order = .data$point_order[[1]],
      n_points = dplyr::n_distinct(.data$point_id),
      .groups = "drop"
    )

  n_vars <-
    points %>%
    dplyr::filter(!is.na(.data$value)) %>%
    dplyr::group_by(.data$dataset_id, .data$response_id) %>%
    dplyr::summarise(n_variables = dplyr::n_distinct(.data$variable), .groups = "drop")

  responses %>%
    dplyr::left_join(n_vars, by = c("dataset_id", "response_id")) %>%
    dplyr::filter(
      .data$point_order == "file order",
      .data$n_points > 1,
      .data$n_variables > 1
    ) %>%
    dplyr::select(dplyr::all_of(c(
      "dataset_id", "response_id", "n_points", "n_variables"
    )))
}


#' Report variables with more than one value at the same point of a curve
#'
#' A curve holds one value per variable per point. Where the source measured the
#' same variable twice within one curve -- under different `method_id`s -- a
#' wide view of it can only show one. This finds those, so anyone pivoting with
#' [response_pivot_wider()] knows what the pivot had to choose between.
#'
#' It is not warned about at build time. For curve data a conflict is rare and
#' worth looking at; for trait-style data, where one variable routinely carries
#' several methods, it is the normal case and would fire on every build.
#'
#' @param database A built database
#'
#' @return A tibble of conflicting variable-point combinations, with the value
#'   and `method_id` each came from, and `used` marking the one a pivot keeps.
#'   Empty if there are none.
#' @importFrom rlang .data
#' @export
check_curve_points_conflicts <- function(database) {

  empty <- tibble::tibble(
    dataset_id = character(0), response_id = character(0), point_id = character(0),
    variable = character(0), method_id = character(0), value = character(0),
    used = logical(0)
  )

  measurements <- database[["measurements"]]

  if (is.null(measurements) || nrow(measurements) == 0) return(empty)

  measurements %>%
    dplyr::group_by(
      .data$dataset_id, .data$response_id, .data$point_id, .data$variable
    ) %>%
    dplyr::filter(dplyr::n() > 1) %>%
    dplyr::arrange(.data$method_id, .by_group = TRUE) %>%
    dplyr::mutate(used = dplyr::row_number() == 1) %>%
    dplyr::ungroup() %>%
    dplyr::select(dplyr::all_of(c(
      "dataset_id", "response_id", "point_id", "variable", "method_id",
      "value", "used"
    ))) %>%
    dplyr::arrange(
      .data$dataset_id, .data$response_id, .data$point_id, .data$variable,
      .data$method_id
    )
}


#' Pivot a database's measurements to one row per point
#'
#' Returns the wide view: one row per point of a curve, one column per variable.
#' This is the shape readings were taken in and the shape they are analysed in.
#'
#' # Why this is a function and not a table
#'
#' A wide table can hold a reading's value and nothing else. Measured on
#' AusFizz, 17 `(dataset, variable, method_id)` groups carry more than one
#' `value_type` *and* more than one `replicates` -- some variables recorded as a
#' mean of five, others raw -- and a single cell per `(point, variable)` has
#' nowhere to put that. Storing both forms would either lose it or duplicate
#' 147 Mb of readings to keep it.
#'
#' So `measurements` is the lossless form and this is a view of it. It is one
#' `pivot_wider()` with nothing to re-derive, because `response_id` and `point_id`
#' are already columns -- which was the thing actually missing before responses
#' were first-class.
#'
#' Where a variable has two values at one point, the pivot keeps the one from
#' the lowest `method_id`; [check_curve_points_conflicts()] reports what it
#' chose between.
#'
# What a caller does next, every time, is filter to one kind of measurement,
# coerce the values to numbers, and drop the columns that dataset never
# measured. The database knows how to do all three -- `data_type` is on the
# response, `type` is in the definitions, and emptiness is visible -- so doing
# them here saves every user the same three lines and the chance of getting the
# numeric coercion wrong.
#'
#' @param database A built database
#' @param data_type Keep only responses of these kinds, e.g. `"ACi"` or
#'   `c("ACi", "ACi-T")`. Defaults to all of them.
#' @param vars Variables to include. Defaults to all of them.
#' @param numeric Coerce variables the definitions call numeric to `numeric`.
#'   `TRUE` by default: values are stored as text, and every caller converts
#'   them.
#' @param drop_empty Drop variable columns that are entirely `NA` after
#'   filtering. `TRUE` by default, since a compilation-wide pivot of a dataset
#'   that measured nine variables is otherwise mostly empty columns.
#' @param with_curves Attach the response's `data_type`, `driver` and
#'   `taxon_name` to each row. `TRUE` by default, since a point is rarely
#'   useful without knowing what it belongs to.
#'
#' @return A tibble, one row per point
#' @importFrom rlang .data
#' @export
#' @examples \dontrun{
#' # every A-Ci curve, wide, numeric, without the columns this study never used
#' response_pivot_wider(database, data_type = c("ACi", "ACi-T"))
#' }
response_pivot_wider <- function(database, data_type = NULL, vars = NULL,
                                 numeric = TRUE, drop_empty = TRUE,
                                 with_curves = TRUE) {

  measurements <- database[["measurements"]]

  if (is.null(measurements)) {
    stop("`database` has no `measurements` table.", call. = FALSE)
  }

  if (!is.null(data_type)) {
    known <- unique(stats::na.omit(measurements$data_type))
    unknown <- setdiff(data_type, known)
    if (length(unknown) > 0) {
      stop("No such data_type: ", paste(unknown, collapse = ", "),
           ". This database has: ", paste(sort(known), collapse = ", "),
           call. = FALSE)
    }
    measurements <- measurements %>%
      dplyr::filter(.data$data_type %in% .env$data_type)
  }

  if (!is.null(vars)) {
    unknown <- setdiff(vars, unique(measurements$variable))
    if (length(unknown) > 0) {
      stop("No such variable: ", paste(unknown, collapse = ", "), call. = FALSE)
    }
    measurements <- measurements %>% dplyr::filter(.data$variable %in% vars)
  }

  out <-
    measurements %>%
    dplyr::arrange(.data$method_id) %>%
    dplyr::select(dplyr::all_of(c(
      "dataset_id", "response_id", "point_id", "variable", "value"
    ))) %>%
    tidyr::pivot_wider(
      names_from = "variable", values_from = "value",
      values_fn = function(x) x[[1]]
    ) %>%
    dplyr::arrange(.data$dataset_id, .data$response_id, .data$point_id)

  id_cols <- c("dataset_id", "response_id", "point_id")
  value_cols <- setdiff(names(out), id_cols)

  if (drop_empty && length(value_cols) > 0) {
    empty <- value_cols[vapply(out[value_cols], function(x) all(is.na(x)), logical(1))]
    out <- out %>% dplyr::select(-dplyr::all_of(empty))
    value_cols <- setdiff(value_cols, empty)
  }

  if (numeric && length(value_cols) > 0) {
    defs <- database[["definitions"]]
    num <- value_cols[vapply(
      value_cols,
      function(v) identical(defs[[v]][["type"]], "numeric"),
      logical(1)
    )]
    # A value the definitions call numeric but that will not parse is a real
    # problem, not something to convert to NA in silence.
    for (v in num) {
      converted <- suppressWarnings(as.numeric(out[[v]]))
      lost <- is.na(converted) & !is.na(out[[v]])
      if (any(lost)) {
        warning(
          sum(lost), " value", if (sum(lost) > 1) "s" else "", " of `", v,
          "` could not be read as a number and became NA, e.g. ",
          paste(utils::head(unique(out[[v]][lost]), 3), collapse = ", "),
          call. = FALSE
        )
      }
      out[[v]] <- converted
    }
  }

  if (!with_curves) return(out)

  # `driver` is a property of the `data_type`, so it is looked up rather than
  # stored on every reading.
  dts <- database[["data_types"]]
  driver_of <- function(dt) {
    vapply(dt, function(x) {
      if (is.na(x) || is.null(dts[[x]])) return(NA_character_)
      v <- dts[[x]][["driver"]]
      if (is.null(v) || identical(v, ".na") || is.na(v)) return(NA_character_)
      as.character(v)
    }, character(1), USE.NAMES = FALSE)
  }

  attrs <-
    measurements %>%
    dplyr::distinct(.data$dataset_id, .data$response_id, .data$data_type,
                    .data$taxon_name)

  out <- out %>%
    dplyr::left_join(attrs, by = c("dataset_id", "response_id"))

  if (!is.null(dts) && length(dts) > 0) {
    out$driver <- driver_of(out$data_type)
  }

  out %>%
    dplyr::relocate(dplyr::any_of(c("data_type", "driver", "taxon_name")),
                    .after = "point_id")
}
