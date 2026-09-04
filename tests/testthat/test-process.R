
test_data <- "data/Test_2022/data.csv"

schema <- get_schema()
resource_metadata <- get_schema("config/metadata.yml", "metadata")
traits_definitions <- get_schema("config/traits.yml", "traits")
unit_conversions <- get_unit_conversions("config/unit_conversions.csv")
test_config <- dataset_configure("data/Test_2022/test-metadata.yml",
                                  traits_definitions)


test_that("`dataset_configure` is working", {
  expect_no_error(
    test_config <- dataset_configure("data/Test_2022/test-metadata.yml",
                                      traits_definitions))
  expect_type(test_config, "list")
  expect_length(test_config, 3)
  expect_named(test_config,
               c("dataset_id", "metadata", "definitions"))
})


test_that("`dataset_process` is working", {
  expect_no_error(austraits_names <- schema$austraits$elements %>% names())
  expect_no_error(x <- dataset_process(test_data, test_config, schema, resource_metadata, unit_conversions))
  expect_type(x, "list")
  # A database built here is a `responses.build` database. This emitted
  # `traits.build` until the austraits linkage was severed; pinned so a rename
  # cannot happen by accident.
  expect_equal(class(x), c("list", "responses.build"))
  expect_length(x, 17)   # + growth_conditions, provenance, data_types
  expect_named(x, austraits_names)
  expect_equal(nrow(x$excluded_data), 0)
  # Test to see if `filter_missing_values` argument works
  expect_equal(
    nrow(
      dataset_process(test_data, test_config, schema, resource_metadata, unit_conversions,
                      filter_missing_values = TRUE)$excluded_data
    ),
  0)
  expect_equal(
    nrow(
      dataset_process(test_data, test_config, schema, resource_metadata, unit_conversions,
      filter_missing_values = FALSE)$excluded_data
    ),
  44)
})


test_that("`process_custom_code` is working", {
  expect_no_error(metadata <- test_config$metadata)
  expect_no_error(data <- readr::read_csv(test_data, col_types = cols(), guess_max = 100000, progress = FALSE))
  expect_equal(ncol(data), 13)
  expect_equal(ncol(process_custom_code(metadata[["dataset"]][["custom_R_code"]])(data)), 16)
  expect_silent(process_custom_code(NA))
})


test_that("`process_format_identifiers` is working", {
  # The third argument is the schema, not the trait data, and `my_list` is the
  # identifiers list itself rather than something wrapping it. Getting either
  # wrong made every call fail with "object 'schema' not found", or silently
  # return no rows.
  identifiers <- read_metadata("examples/Test_2023_1/metadata.yml")$identifiers
  expected_cols <-
    names(schema[["austraits"]][["elements"]][["identifiers"]][["elements"]])

  out <- process_format_identifiers(identifiers, "Test_2023_1", schema)

  expect_named(out, expected_cols)
  expect_equal(nrow(out), length(identifiers))
  expect_equal(out$dataset_id, rep("Test_2023_1", length(identifiers)))
  expect_equal(out$identifier_type, purrr::map_chr(identifiers, "identifier_type"))

  # A dataset that declares no identifiers still gets the full set of columns
  empty <- process_format_identifiers(list(), "Test_2023_1", schema)
  expect_named(empty, expected_cols)
  expect_equal(nrow(empty), 0)
})


test_that("a `var_in` naming a column that does not exist is rejected", {
  # This used to pass silently: `process_add_all_columns()` creates the missing
  # column as all-NA and the `!is.na(identifier_value)` filter then drops every
  # row, so the dataset lost its identifiers with no error and an empty table
  # (#232).
  metadata_path <- file.path(withr::local_tempdir(), "metadata.yml")
  metadata <- readLines("examples/Test_2023_1/metadata.yml")
  metadata[grepl("^- var_in: herbarium_voucher$", metadata)] <-
    "- var_in: herbarium_vouchers"
  writeLines(metadata, metadata_path)

  expect_error(
    dataset_process(
      "examples/Test_2023_1/data.csv",
      dataset_configure(metadata_path, traits_definitions),
      schema, resource_metadata, unit_conversions
    ),
    "herbarium_vouchers"
  )
})


test_that("a `var_in` created by `custom_R_code` is still accepted", {
  # The check has to run against the data as it stands after `custom_R_code`,
  # not against the raw csv header. Every dataset in the three downstream
  # repositories that uses identifiers creates its `var_in` column this way, so
  # validating the raw header would reject all of them (#232).
  metadata_path <- file.path(withr::local_tempdir(), "metadata.yml")
  metadata <- readLines("examples/Test_2023_1/metadata.yml")

  # Point `var_in` at a column absent from data.csv, then add it to the
  # existing `custom_R_code` mutate so it exists by the time identifiers load
  metadata[grepl("^- var_in: herbarium_voucher$", metadata)] <-
    "- var_in: voucher_made_by_custom_code"
  metadata[grepl("^\\s+LASA1000_dupe = LASA1000$", metadata)] <-
    "        LASA1000_dupe = LASA1000,\n        voucher_made_by_custom_code = herbarium_voucher"
  writeLines(metadata, metadata_path)

  # Guard the premise: the column really is absent from the raw csv
  expect_false(
    "voucher_made_by_custom_code" %in% names(read_csv_char("examples/Test_2023_1/data.csv"))
  )

  expect_no_error(
    built <- dataset_process(
      "examples/Test_2023_1/data.csv",
      dataset_configure(metadata_path, traits_definitions),
      schema, resource_metadata, unit_conversions
    )
  )
  expect_gt(nrow(built$identifiers), 0)
})


test_that("`write_plaintext` exports every table in the database", {
  # The table list used to be hardcoded and had `identifiers` missing from it
  # for the whole of 2.1.0, so exports silently dropped the release's headline
  # table. Nothing caught that, because nothing tested this function at all.
  #
  # Test_2023_1 is used because it is the example with a populated identifiers
  # table, so the round-trip below actually carries rows.
  built <-
    dataset_process(
      "examples/Test_2023_1/data.csv",
      dataset_configure("examples/Test_2023_1/metadata.yml",
                        traits_definitions),
      schema, resource_metadata, unit_conversions
    ) %>%
    # Read the committed fixture rather than the `config/taxon_list.csv` build
    # artefact, so this assertion is pinned to a known taxon list
    dataset_update_taxonomy(read_csv_char("config/taxon_list-orig.csv"))

  path <- withr::local_tempdir()
  suppressMessages(write_plaintext(built, path))

  tables <- names(built)[purrr::map_lgl(built, is.data.frame)]
  expect_true("identifiers" %in% tables)
  expect_gt(nrow(built$identifiers), 0)

  expect_true(all(paste0(tables, ".csv") %in% list.files(path)))

  # Round-trip, not just presence: an exported table has to read back as what
  # the database held
  for (v in tables) {
    expect_equal(
      read_csv_char(file.path(path, paste0(v, ".csv"))),
      built[[v]],
      info = v
    )
  }

  # The non-tabular artefacts users also receive
  expect_true(all(
    c("definitions.yml", "metadata.yml", "schema.yml", "sources.bib",
      "build_info.md") %in% list.files(path)
  ))
})


test_that("the build pipeline runs end to end", {
  # This began as a test that the pipeline published in Wenk et al. 2024 Fig. 1
  # ran as drawn. That paper is `traits.build`'s public specification, not this
  # fork's, and the two functions it named that only existed here as
  # pass-throughs to `austraits` -- `database_create_combined_table()` and
  # `build_combine()` -- went with the severed dependency (PLAN.md, Stage 0).
  # The end-to-end walk is still worth having, so it stays, minus the joined
  # combined table. `curve_points` replaces that in Stage 2.
  taxon_list <- read_csv_char("config/taxon_list-orig.csv")

  build_config <- dataset_configure("examples/Test_2023_1/metadata.yml",
                                    traits_definitions)

  built <-
    dataset_process("examples/Test_2023_1/data.csv", build_config,
                    schema, resource_metadata, unit_conversions) %>%
    data_update_taxonomy(taxon_list)

  # The published name and the current one are the same function
  expect_equal(
    built,
    dataset_process("examples/Test_2023_1/data.csv", build_config,
                    schema, resource_metadata, unit_conversions) %>%
      dataset_update_taxonomy(taxon_list)
  )

  database <- bind_databases(databases = list(Test_2023_1 = built))

  expect_s3_class(database, "responses.build")
  expect_equal(nrow(database$measurements), nrow(built$measurements))
})


test_that("`individual_id` is one number per individual per dataset", {
  # It used to be numbered within each `taxon_name` and `population_id`, so the
  # same label recurred across taxa and populations and did not identify an
  # individual: across AusFizz's 35 datasets, 22,255 entities carried 3,844
  # labels. Two taxa each with plants labelled 1 and 2 must come out as four
  # individuals, not two.
  built <-
    dataset_process(
      "examples/Test_2023_5/data.csv",
      dataset_configure("examples/Test_2023_5/metadata.yml", traits_definitions),
      schema, resource_metadata, unit_conversions
    )

  ind <- built$measurements %>% dplyr::filter(!is.na(individual_id))

  # Guard the premise: this example really does span several taxa
  expect_gt(dplyr::n_distinct(ind$taxon_name), 1)

  expect_equal(
    dplyr::n_distinct(ind$individual_id),
    dplyr::n_distinct(paste(ind$taxon_name, ind$population_id, ind$individual_id))
  )
})


test_that("`individual_id` does not depend on the row order of `data.csv`", {
  # `process_generate_id()` numbers in first-appearance order unless asked to
  # sort, and this call did not ask, so the labels moved with incidental row
  # order -- the same defect fixed for the context ids. A build must not depend
  # on the order its input happened to be written in.
  # Test_2023_7 is used because one of its `(taxon_name, population_id)` groups
  # holds eight individuals. In a fixture where every group holds one, they are
  # all numbered "01" whatever the row order, and the test pins nothing.
  build_from <- function(path) {
    dataset_process(
      path,
      dataset_configure("examples/Test_2023_7/metadata.yml", traits_definitions),
      schema, resource_metadata, unit_conversions
    )$measurements
  }

  original <- build_from("examples/Test_2023_7/data.csv")

  shuffled_path <- file.path(withr::local_tempdir(), "data.csv")
  rows <- read_csv_char("examples/Test_2023_7/data.csv")
  withr::with_seed(42, readr::write_csv(rows[sample(nrow(rows)), ], shuffled_path))
  shuffled <- build_from(shuffled_path)

  # Identify each individual by the readings it carries, not by its label --
  # the label is what is under test, and the source label it came from is not
  # kept in the built table. Comparing the set of labels would pass a
  # permutation, since both builds hold "01" through "08" either way.
  signature_of <- function(d) {
    d %>%
      dplyr::filter(!is.na(individual_id)) %>%
      dplyr::group_by(taxon_name, population_id, individual_id) %>%
      dplyr::summarise(
        readings = paste(sort(paste(variable, value)), collapse = "|"),
        .groups = "drop"
      ) %>%
      dplyr::arrange(taxon_name, population_id, individual_id)
  }

  expect_equal(signature_of(original), signature_of(shuffled))
})


test_that("`process_format_contexts` keeps a time column's clock values", {
  # A context whose values are derived from the data used to lose them whenever
  # the column read as `hms`. `ifelse()` drops the class of its arguments, so
  # filling `find` from `value` demoted it to the underlying seconds: `find`
  # became "41400" where `value` stayed "11:30:00". Nothing matched afterwards,
  # because `process_create_context_ids()` reads the data column with
  # `as.character()` and looks the result up by `find`, and the whole context
  # was dropped from the build without a warning.
  # Built with `read_csv()` rather than `hms::as_hms()`, both so the column
  # arises the way it does in a build -- from readr's type guessing on a
  # `data.csv` -- and because `hms` is not a declared dependency.
  data <- readr::read_csv(
    I("Time,treatment\n11:30:00,wet\n10:00:00,wet\n11:30:00,dry\n17:40:00,dry\n"),
    col_types = readr::cols(), progress = FALSE
  )

  expect_s3_class(data$Time, "hms")

  contexts <- process_format_contexts(
    list(
      list(
        context_property = "time_of_day_approx",
        category = "temporal_context",
        var_in = "Time"
      )
    ),
    "Test_hms", data
  )

  expect_setequal(contexts$value, c("11:30:00", "10:00:00", "17:40:00"))
  expect_equal(contexts$find, contexts$value)

  # And the values reach the build, rather than looking up to nothing
  linked <- process_create_context_ids(data, contexts)

  expect_false(any(is.na(linked$contexts$link_id)))
  expect_equal(dplyr::n_distinct(linked$ids$temporal_context_id), 3)
})


test_that("`process_format_contexts` still fills an absent `find` from `value`", {
  # The `find` column is optional per value: a context that only ever names a
  # `value` relies on it being copied across, and the fix above must not stop
  # that. Here one value declares a `find` and the other does not.
  contexts <- process_format_contexts(
    list(
      list(
        context_property = "growth_water_treatment",
        category = "treatment_context",
        var_in = "opt",
        values = list(
          list(find = "drought", value = "water deficit"),
          list(value = "well-watered")
        )
      )
    ),
    "Test_find", tibble(opt = c("drought", "well-watered"))
  )

  expect_equal(contexts$find, c("drought", "well-watered"))
  expect_equal(contexts$value, c("water deficit", "well-watered"))
})


# The below functions are not working
#test_that("process_flag_unsupported_traits is working", {
#  process_flag_unsupported_traits(data, definitions)
#})

#test_that("process_flag_excluded_observations is working", {
#  process_flag_excluded_observations
#})
