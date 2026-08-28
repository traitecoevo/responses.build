#' Load the instrument column maps a compilation uses
#'
#' Reads every `config/instruments/*.yml`. Each maps the columns one instrument
#' writes onto variables, so a dataset can name the instrument instead of
#' restating twenty column mappings.
#'
#' @param path Directory of instrument profiles. Defaults to
#'   `config/instruments`, if it exists.
#'
#' @return A named list of profiles, keyed by both file stem and every value in
#'   the profile's `matches`, so `instrument: Li6400 IRGA` and
#'   `instrument: licor_6400` both resolve. Empty if there is no directory.
#' @export
get_instruments <- function(path = NULL) {

  if (is.null(path)) {
    if (!dir.exists("config/instruments")) return(list())
    path <- "config/instruments"
  }

  if (!dir.exists(path)) {
    stop("No instrument profiles at ", path, call. = FALSE)
  }

  files <- list.files(path, pattern = "\\.yml$", full.names = TRUE)
  out <- list()

  for (f in files) {
    profile <- yaml::read_yaml(f)[["instrument"]]

    if (is.null(profile[["columns"]])) {
      stop(f, " has no `instrument: columns:` block.", call. = FALSE)
    }

    stem <- tools::file_path_sans_ext(basename(f))
    profile[["name"]] <- stem

    # A dataset may name the instrument as the profile's file stem or as any of
    # the instrument strings it covers -- `licor_6400`, `Li6400 IRGA` and
    # `Li6400XT IRGA` are the same column map.
    for (key in unique(c(stem, unlist(profile[["matches"]])))) {
      out[[key]] <- profile
    }
  }

  out
}


#' Expand a `measurements:` block into the internal trait mapping
#'
#' `measurements:` is how a dataset says what it measured, from Stage 3 onward.
#' One block per data file:
#'
#' ```yaml
#' measurements:
#' - file: data.csv
#'   data_type: ACi-T
#'   instrument: licor_6400
#'   curve_id: Curve_Id
#'   methods: |
#'     Each Anet-Ci response curve started with ...
#'   variables_extra:
#'   - var_in: temp
#'     variable: leaf_temperature_setpoint
#'     unit_in: C
#' ```
#'
#' A second block covers a second data type in the same file. Where that file
#' distinguishes them by suffixing every column, `column_suffix` says so once
#' instead of restating the map:
#'
#' ```yaml
#' - file: data.csv
#'   data_type: survey
#'   instrument: licor_6400
#'   column_suffix: _survey_Amax
#'   methods: |
#'     Survey measurements were taken ...
#' ```
#'
#' This desugars it into the `traits:` list the rest of the build already
#' understands: one entry per variable, each carrying the block's `methods`.
#' Three things follow from doing it that way.
#'
#' The build is unchanged. Stage 3 changes how metadata is *written*, not what
#' the build *produces* -- which is not a shortcut, it is the migration
#' invariant. `curves` and `curve_points` are gated on being identical before
#' and after, and they would not be if `data_type` stopped being a method
#' context, because `method_context_id` is part of a curve's identity. Moving
#' the descriptors out of `contexts` in the *output* is a separate change with
#' its own gate.
#'
#' A dataset keeping a hand-written `traits:` block still builds. Both forms are
#' read; `measurements:` wins if both are present.
#'
#' The instrument profile supplies `var_in` and `unit_in` for each variable it
#' knows. `variables_extra` adds or overrides, and a dataset whose file
#' disagrees with the profile says so there rather than restating the whole map.
#'
#' @param metadata A dataset's metadata, as read from `metadata.yml`
#' @param instruments Instrument profiles, from [get_instruments()]
#' @param data_types Data type definitions, from [get_data_types()]
#' @param dataset_id The dataset, used only in error messages
#'
#' @return The metadata, with `traits` populated from `measurements`
#' @noRd
metadata_expand_measurements <- function(metadata, instruments = list(),
                                         data_types = list(),
                                         dataset_id = "this dataset") {

  blocks <- metadata[["measurements"]]

  if (is.null(blocks) || length(blocks) == 0) return(metadata)

  # Defaults for a variable entry. These were written out per trait in every
  # dataset, identically, in all 369 mappings of the 2026-08 corpus.
  defaults <- list(
    entity_type = "individual",
    value_type = "raw",
    basis_of_value = "measurement",
    replicates = 1
  )

  traits <- list()

  for (i in seq_along(blocks)) {
    block <- blocks[[i]]
    where <- sprintf("%s, measurements block %d", dataset_id, i)

    if (is.null(block[["methods"]])) {
      stop(where, ": no `methods`. Every measurement needs to say how it was ",
           "made.", call. = FALSE)
    }

    if (!is.null(block[["data_type"]]) && length(data_types) > 0 &&
        is.null(data_types[[block[["data_type"]]]])) {
      stop(where, ": data_type '", block[["data_type"]], "' is not defined in ",
           "config/data_types.yml. Known: ",
           paste(names(data_types), collapse = ", "), call. = FALSE)
    }

    columns <- list()

    if (!is.null(block[["instrument"]])) {
      profile <- instruments[[block[["instrument"]]]]
      if (is.null(profile)) {
        stop(where, ": no profile for instrument '", block[["instrument"]],
             "'. Known: ", paste(sort(unique(names(instruments))), collapse = ", "),
             call. = FALSE)
      }
      columns <- profile[["columns"]]
    }

    # `column_suffix` is how one file carries two data types. A study that
    # measured both A-Ci curves and survey points in one spreadsheet writes
    # `Photo` and `Photo_survey_Amax`, `Ci` and `Ci_survey_Amax`, and so on for
    # every column. Encoded as a second full mapping that costs 19 duplicated
    # entries; encoded here as one line on a second block. This is board issue
    # #3: the duplication is not in the data, it is in having only one place to
    # describe a file.
    if (!is.null(block[["column_suffix"]])) {
      columns <- lapply(columns, function(spec) {
        spec[["var_in"]] <- paste0(spec[["var_in"]], block[["column_suffix"]])
        spec[["aliases"]] <- NULL
        spec
      })
    }

    # `use` restricts a block to some of the instrument's columns, for a file
    # that carries only part of what the instrument can write.
    if (!is.null(block[["use"]])) {
      unknown <- setdiff(unlist(block[["use"]]), names(columns))
      if (length(unknown) > 0) {
        stop(where, ": `use` names variables the instrument profile does not ",
             "map: ", paste(unknown, collapse = ", "), call. = FALSE)
      }
      columns <- columns[unlist(block[["use"]])]
    }

    # `variables_extra` adds to, or overrides, the profile. It comes *after*
    # `column_suffix` and `use`, which describe the profile only: an extra is
    # written out in full, suffix included, and filtering it by `use` would
    # silently drop every variable the profile does not cover.
    for (extra in block[["variables_extra"]]) {
      name <- extra[["variable"]]
      if (is.null(name)) {
        stop(where, ": a `variables_extra` entry has no `variable`.", call. = FALSE)
      }
      columns[[name]] <- extra[names(extra) != "variable"]
    }

    if (length(columns) == 0) {
      stop(where, ": names neither an `instrument` nor any `variables_extra`, ",
           "so it maps no columns.", call. = FALSE)
    }

    for (variable in names(columns)) {
      spec <- columns[[variable]]
      entry <- defaults
      # A block may set any default for all its variables
      for (f in names(defaults)) {
        if (!is.null(block[[f]])) entry[[f]] <- block[[f]]
      }
      entry[["var_in"]] <- spec[["var_in"]]
      entry[["unit_in"]] <- spec[["unit_in"]]
      entry[["trait_name"]] <- variable
      entry[["methods"]] <- block[["methods"]]
      # Per-variable overrides beat the block's defaults
      for (f in intersect(names(spec), names(defaults))) {
        entry[[f]] <- spec[[f]]
      }
      traits[[length(traits) + 1]] <-
        entry[c("var_in", "unit_in", "trait_name", "entity_type", "value_type",
                "basis_of_value", "replicates", "methods")]
    }
  }

  metadata[["traits"]] <- traits
  metadata
}
