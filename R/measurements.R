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


#' Load the controlled vocabularies for measurement descriptors
#'
#' Reads `config/vocabularies.yml`. Each entry gives a descriptor's context
#' `category` and the values it may take.
#'
#' @param path Path to the vocabularies. Defaults to `config/vocabularies.yml`,
#'   if it exists.
#'
#' @return A named list of vocabularies, empty if there is no file
#' @export
get_vocabularies <- function(path = NULL) {

  if (is.null(path)) {
    if (!file.exists("config/vocabularies.yml")) return(list())
    path <- "config/vocabularies.yml"
  }

  if (!file.exists(path)) {
    stop("No vocabularies at ", path, call. = FALSE)
  }

  out <- yaml::read_yaml(path)

  if (is.null(out[["vocabularies"]][["elements"]])) {
    stop(path, " has no `vocabularies: elements:` block.", call. = FALSE)
  }

  out[["vocabularies"]][["elements"]]
}


#' Expand dataset-level descriptors into data columns and contexts
#'
#' A descriptor is a property that is constant for a whole dataset: which
#' instrument was used, whether the plant was potted or in the ground, whether
#' the leaf was attached. Measured across the 2026-08 AusFizz corpus, twelve of
#' them appear in 24 to 30 of the 31 datasets, and each was written **twice** --
#' once as a literal inside `custom_R_code`, creating a column of one repeated
#' value, and again as a `contexts` entry naming the column just created.
#'
#' Written once now, in a `descriptors:` block of its own:
#'
#' ```yaml
#' descriptors:
#'   instrument: Li6400 IRGA
#'   growth_environment: controlled environment chamber
#'   leaf_status: attached leaf
#' ```
#'
#' Not in `dataset:`, deliberately. A `dataset:` field is "a column name, or the
#' value itself", so `plant_organ: leaf` in a file that has a column called
#' `leaf` is read as a column reference and renames it. Descriptors are always
#' values, so they need somewhere that means only that.
#'
#' This puts back what the two hand-written halves used to: the constant column
#' and the context entry, with the category taken from `config/vocabularies.yml`
#' so it cannot be got wrong per dataset. The built database is unchanged.
#'
#' It is safe to append these to the end of the contexts list only because
#' context ids no longer depend on the order properties are listed in. Before
#' that fix, appending would have silently relabelled `treatment_context_id`.
#'
#' @param data The dataset's data, after `custom_R_code` has run
#' @param metadata The dataset's metadata
#' @param vocabularies Descriptor vocabularies, from [get_vocabularies()]
#' @param dataset_id The dataset, used in error messages
#'
#' @return A list with the augmented `data` and `metadata`
#' @noRd
process_expand_descriptors <- function(data, metadata, vocabularies = list(),
                                       dataset_id = "this dataset") {

  if (length(vocabularies) == 0) return(list(data = data, metadata = metadata))

  present <- intersect(names(vocabularies), names(metadata[["descriptors"]]))

  if (length(present) == 0) return(list(data = data, metadata = metadata))

  # A dataset with no contexts has `contexts: .na`, which reads back as a bare
  # NA rather than an empty list.
  existing <- metadata[["contexts"]]
  if (!is.list(existing)) existing <- list()

  already <- vapply(
    existing,
    function(x) if (is.list(x) && !is.null(x[["context_property"]])) {
      as.character(x[["context_property"]])
    } else "",
    character(1)
  )

  for (name in present) {
    value <- metadata[["descriptors"]][[name]]

    if (is.null(value) || all(is.na(value))) next

    if (name %in% names(data)) {
      stop(dataset_id, ": `", name, "` is declared as a dataset descriptor but ",
           "is also a column in the data. It has to be one or the other.",
           call. = FALSE)
    }

    category <- vocabularies[[name]][["category"]]
    if (is.null(category)) {
      stop(dataset_id, ": descriptor `", name, "` has no `category` in ",
           "config/vocabularies.yml, so there is nowhere to put it.",
           call. = FALSE)
    }

    data[[name]] <- as.character(value)

    if (!name %in% already) {
      existing <- c(
        existing,
        list(list(context_property = name, category = category, var_in = name))
      )
      already <- c(already, name)
    }
  }

  if (length(existing) > 0) metadata[["contexts"]] <- existing

  list(data = data, metadata = metadata)
}


#' Report descriptor values that are not in their controlled vocabulary
#'
#' The vocabularies are documentation of what a value may be, drawn mostly from
#' the ESS-DIVE leaf gas exchange standard and the Prometheus protocols. They
#' are not enforced at build time: measured across AusFizz, 73 of 315 declared
#' values sit outside their vocabulary, and most of those are real questions
#' about the data rather than typos -- `plant_age` holds actual ages where
#' ESS-DIVE expects a life stage, and `upper canopy` and `upper_canopy` both
#' appear for the same thing.
#'
#' Failing a build on those would block work on a documentation question. This
#' reports them instead.
#'
#' @param path Directory of dataset folders, default `data`
#' @param vocabularies Descriptor vocabularies, from [get_vocabularies()]
#'
#' @return A tibble of dataset, descriptor and off-vocabulary value
#' @importFrom rlang .data
#' @export
check_vocabularies <- function(path = "data", vocabularies = get_vocabularies()) {

  out <- list()

  for (id in list.dirs(path, recursive = FALSE, full.names = FALSE)) {
    f <- file.path(path, id, "metadata.yml")
    if (!file.exists(f)) next
    metadata <- read_metadata(f)

    for (name in intersect(names(vocabularies), names(metadata[["descriptors"]]))) {
      allowed <- unlist(vocabularies[[name]][["values"]])
      if (is.null(allowed)) next
      value <- as.character(metadata[["descriptors"]][[name]])
      if (is.null(value) || is.na(value)) next
      # A field marked `multiple` composes several values with "; "
      parts <- if (isTRUE(vocabularies[[name]][["multiple"]])) {
        trimws(strsplit(value, ";")[[1]])
      } else value
      bad <- setdiff(parts, allowed)
      if (length(bad) > 0) {
        out[[length(out) + 1]] <- tibble::tibble(
          dataset_id = id, descriptor = name, value = bad
        )
      }
    }
  }

  if (length(out) == 0) {
    return(tibble::tibble(dataset_id = character(0), descriptor = character(0),
                          value = character(0)))
  }

  dplyr::bind_rows(out)
}


#' Check that dataset-level descriptors really are constant
#'
#' A descriptor declared in `dataset:` says the property is the same for every
#' row. `custom_R_code` runs after it is set, and can overwrite it with a
#' computed column -- six AusFizz datasets compute `data_type` with an `ifelse`
#' while also assigning it a literal elsewhere in the same block. A migration
#' reading only the literal would promote it and quietly flatten a column that
#' varies.
#'
#' Failing here is right: the alternative is a database that looks fine and has
#' lost a distinction it used to record.
#'
#' @param data The dataset's data, after `custom_R_code` has run
#' @param metadata The dataset's metadata
#' @param vocabularies Descriptor vocabularies
#' @param dataset_id The dataset, used in the error message
#'
#' @return Invisibly TRUE, or an error
#' @noRd
util_check_descriptors_constant <- function(data, metadata, vocabularies = list(),
                                            dataset_id = "this dataset") {

  if (length(vocabularies) == 0) return(invisible(TRUE))

  for (name in intersect(names(vocabularies), names(metadata[["descriptors"]]))) {
    if (!name %in% names(data)) next

    values <- unique(stats::na.omit(as.character(data[[name]])))

    if (length(values) > 1) {
      stop(
        dataset_id, ": `", name, "` is declared as a dataset descriptor, which ",
        "means it is the same for every row, but after `custom_R_code` it holds ",
        length(values), " values: ",
        paste(utils::head(sort(values), 5), collapse = ", "),
        ".\nIt varies within the dataset, so it is a context, not a descriptor. ",
        "Move it back to `contexts:`.",
        call. = FALSE
      )
    }
  }

  invisible(TRUE)
}


#' Put back descriptor columns that custom code dropped
#'
#' Descriptors are added before `custom_R_code` runs, because eight AusFizz
#' datasets have code that reads one -- joining on `data_type`, filtering on
#' `leaf_status`. But code that does `select(Date:Press, Species, Site)` keeps a
#' range of columns and discards the rest, descriptors included.
#'
#' Adding them only afterwards breaks the readers; adding them only before
#' breaks the selectors. So: before, and again after for anything that went
#' missing.
#'
#' @param data The dataset's data, after `custom_R_code` has run
#' @param metadata The dataset's metadata
#' @param vocabularies Descriptor vocabularies
#'
#' @return The data, with every declared descriptor present
#' @noRd
util_restore_descriptors <- function(data, metadata, vocabularies = list()) {

  if (length(vocabularies) == 0) return(data)

  for (name in intersect(names(vocabularies), names(metadata[["descriptors"]]))) {
    value <- metadata[["descriptors"]][[name]]
    if (is.null(value) || all(is.na(value))) next

    if (!name %in% names(data)) {
      data[[name]] <- as.character(value)
      next
    }

    # The column survived, but a join in the custom code can leave it NA on
    # rows the join added -- `Bloomfield_2014_a` full-joins two halves of its
    # file. A descriptor is constant by declaration, so an NA in it is a gap
    # the join made, not a value. Filling it is what "constant" means; leaving
    # it drops those rows out of their context, which is how 14 rows lost their
    # entity and treatment ids.
    data[[name]][is.na(data[[name]])] <- as.character(value)
  }

  data
}
