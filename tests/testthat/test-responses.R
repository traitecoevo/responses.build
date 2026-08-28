# A response curve is a set of measurements across a driver gradient whose
# points belong together. Nothing in the upstream data model said so, and every
# notebook re-derived it. These pin the derivation.

make_traits <- function(...) {
  base <- tibble::tibble(
    dataset_id = "Test", taxon_name = "Acacia aneura",
    observation_id = "001", trait_name = "A", value = "1",
    individual_id = "01", population_id = "01", collection_date = "2020-01-01",
    location_id = "01", treatment_context_id = NA_character_,
    entity_context_id = NA_character_, temporal_context_id = NA_character_,
    method_id = "01", method_context_id = "01",
    repeat_measurements_id = NA_character_
  )
  args <- list(...)
  n_rows <- max(1L, vapply(args, length, integer(1)), na.rm = TRUE)
  base <- base[rep(1L, n_rows), ]
  for (n in names(args)) base[[n]] <- args[[n]]
  base
}

# One A-Ci curve: four points, two variables, ordered.
aci <- make_traits(
  trait_name = rep(c("A", "Ci"), each = 4),
  value = as.character(c(5, 10, 15, 20, 100, 200, 300, 400)),
  repeat_measurements_id = rep(c("01", "02", "03", "04"), 2)
)

ctx <- tibble::tibble(
  dataset_id = "Test",
  context_property = c("data_type", "instrument"),
  category = "method_context",
  value = c("ACi", "Li6400 IRGA"),
  description = NA_character_,
  link_id = "method_context_id",
  link_vals = "01"
)

dts <- list(ACi = list(driver = "Ci"),
            `ACi-T` = list(driver = "Ci", driver_outer = "leaf_temperature_setpoint"),
            survey = list(driver = ".na"))


test_that("every reading is stamped with the curve and point it belongs to", {
  out <- process_create_responses(aci, ctx, dts)

  expect_equal(nrow(out$responses), 1)
  # One key row per reading, not per point: the readings stay long
  expect_equal(nrow(out$keys), nrow(aci))
  expect_equal(unique(out$keys$response_id), "01")
  expect_setequal(out$keys$point_id, c("01", "02", "03", "04"))
})


test_that("the wide view pairs a curve's variables, and is a view not a table", {
  out <- process_create_responses(aci, ctx, dts)
  db <- list(
    measurements = dplyr::bind_cols(aci, out$keys) %>%
      dplyr::rename(variable = "trait_name"),
    responses = out$responses
  )

  # There is no stored wide table -- that is the point
  expect_null(db$curve_points)

  wide <- response_pivot_wider(db)

  expect_equal(nrow(wide), 4)
  expect_true(all(c("A", "Ci") %in% names(wide)))
  # The pairing is the point: point 3 of A goes with point 3 of Ci
  expect_equal(wide$A[[3]], "15")
  expect_equal(wide$Ci[[3]], "300")
  # ...and it carries what curve each point came from
  expect_equal(unique(wide$data_type), "ACi")
  expect_equal(unique(wide$driver), "Ci")
})


test_that("`response_pivot_wider` can be restricted, and rejects an unknown variable", {
  out <- process_create_responses(aci, ctx, dts)
  db <- list(
    measurements = dplyr::bind_cols(aci, out$keys) %>%
      dplyr::rename(variable = "trait_name"),
    responses = out$responses
  )

  wide <- response_pivot_wider(db, vars = "A")
  expect_true("A" %in% names(wide))
  expect_false("Ci" %in% names(wide))

  expect_error(response_pivot_wider(db, vars = "Vcmax"), "No such variable: Vcmax")
  expect_error(response_pivot_wider(list()), "no `measurements` table")
})


test_that("data_type and driver come off the context and the data type table", {
  out <- process_create_responses(aci, ctx, dts)

  expect_equal(out$responses$data_type, "ACi")
  expect_equal(out$responses$driver, "Ci")
  expect_equal(out$responses$instrument, "Li6400 IRGA")
  expect_equal(out$responses$n_points, "4")
  expect_equal(out$responses$point_order, "recorded")
})


test_that("a nested data type carries both drivers", {
  ctx2 <- ctx
  ctx2$value[[1]] <- "ACi-T"
  out <- process_create_responses(aci, ctx2, dts)

  expect_equal(out$responses$driver, "Ci")
  expect_equal(out$responses$driver_outer, "leaf_temperature_setpoint")
})


test_that("`.na` driver and an unknown data type both give no driver", {
  ctx2 <- ctx
  ctx2$value[[1]] <- "survey"
  expect_true(is.na(process_create_responses(aci, ctx2, dts)$responses$driver))

  ctx3 <- ctx
  ctx3$value[[1]] <- "something we have not defined"
  expect_true(is.na(process_create_responses(aci, ctx3, dts)$responses$driver))
})


test_that("`link_vals` is a list of ids, not one id", {
  # A context value can cover several method contexts, recorded as
  # "01, 02, 03". Joining on the raw string matches none of them, and the
  # curve silently loses its data_type.
  two <- dplyr::bind_rows(aci, dplyr::mutate(aci, method_context_id = "03"))
  ctx2 <- ctx
  ctx2$link_vals <- "01, 03"

  out <- process_create_responses(two, ctx2, dts)

  expect_equal(nrow(out$responses), 2)
  expect_equal(unique(out$responses$data_type), "ACi")
})


test_that("a single-point observation is a curve of length one, not a special case", {
  out <- process_create_responses(make_traits(), ctx, dts)

  expect_equal(nrow(out$responses), 1)
  expect_equal(out$responses$n_points, "1")
  expect_equal(nrow(out$keys), 1)
})


test_that("curves are separated by method context", {
  # An ACi-T dataset is one curve per cuvette temperature, and that is what
  # distinguishes them.
  two <- dplyr::bind_rows(aci, dplyr::mutate(aci, method_context_id = "02"))
  out <- process_create_responses(two, ctx, dts)

  expect_equal(nrow(out$responses), 2)
  expect_equal(out$responses$response_id, c("01", "02"))
  expect_setequal(unique(out$keys$response_id), c("01", "02"))
})


test_that("a curve with no recorded point order says so", {
  no_order <- dplyr::mutate(aci, repeat_measurements_id = NA_character_)
  out <- process_create_responses(no_order, ctx, dts)

  expect_equal(out$responses$point_order, "file order")
})


test_that("`check_curve_pairing` flags only curves where the order matters", {
  # No order, several points, several variables -- the values are all there but
  # which A goes with which Ci is not recorded.
  as_db <- function(traits) {
    out <- process_create_responses(traits, ctx, dts)
    list(
      measurements = dplyr::bind_cols(traits, out$keys) %>%
        dplyr::rename(variable = "trait_name"),
      responses = out$responses
    )
  }

  no_order <- dplyr::mutate(aci, repeat_measurements_id = NA_character_)
  expect_s3_class(check_curve_pairing(as_db(no_order)), "data.frame")

  # An ordered curve is never flagged
  expect_equal(nrow(check_curve_pairing(as_db(aci))), 0)

  # Nor is a single point, which needs no ordering
  expect_equal(nrow(check_curve_pairing(as_db(make_traits()))), 0)
})


test_that("`get_data_types` returns an empty list rather than failing", {
  # A compilation that has not written the file still builds; its curves just
  # carry no driver.
  d <- withr::local_tempdir()
  withr::local_dir(d)
  expect_equal(get_data_types(), list())
})


test_that("`get_data_types` rejects a file without the expected block", {
  d <- withr::local_tempdir()
  path <- file.path(d, "data_types.yml")
  writeLines(c("something_else:", "  elements:", "    ACi:"), path)

  expect_error(get_data_types(path), "no `data_types: elements:` block", fixed = TRUE)
  expect_error(get_data_types(file.path(d, "absent.yml")), "No data type definitions")
})


test_that("empty input gives empty tables with the right columns", {
  out <- process_create_responses(aci[0, ], ctx, dts)

  expect_equal(nrow(out$responses), 0)
  expect_true(all(c("response_id", "data_type", "driver", "n_points") %in% names(out$responses)))
  expect_true(all(c("response_id", "point_id") %in% names(out$keys)))
})


# `response_pivot_wider()` exists so that the wide shape need not be stored.
# What a caller does next is always the same three things -- filter to one kind
# of measurement, make the values numbers, drop the columns this dataset never
# used -- so it does them.

pivot_db <- function() {
  ge <- make_traits(
    trait_name = rep(c("A", "Ci"), each = 2),
    value = as.character(c(5, 10, 100, 200)),
    repeat_measurements_id = rep(c("01", "02"), 2)
  )
  hyd <- make_traits(
    dataset_id = "Other", observation_id = "001", method_context_id = "01",
    trait_name = rep(c("PLCstem", "PSIstem"), each = 2),
    value = as.character(c(10, 90, -1, -4)),
    repeat_measurements_id = rep(c("01", "02"), 2)
  )
  ctx2 <- dplyr::bind_rows(ctx, dplyr::mutate(ctx, dataset_id = "Other",
                                              value = c("stem hydraulic vulnerability", "HS18")))
  dt2 <- c(dts, list(`stem hydraulic vulnerability` = list(driver = "PSIstem")))

  parts <- lapply(list(ge, hyd), function(tr) {
    out <- process_create_responses(tr, ctx2[ctx2$dataset_id == tr$dataset_id[[1]], ], dt2)
    list(m = dplyr::bind_cols(tr, out$keys) %>% dplyr::rename(variable = "trait_name"),
         r = out$responses)
  })

  list(
    measurements = dplyr::bind_rows(lapply(parts, `[[`, "m")),
    responses = dplyr::bind_rows(lapply(parts, `[[`, "r")),
    definitions = list(A = list(type = "numeric"), Ci = list(type = "numeric"),
                       PLCstem = list(type = "numeric"), PSIstem = list(type = "numeric"))
  )
}


test_that("`data_type` matches on (dataset, response), not the id alone", {
  # `response_id` is generated per dataset, so "01" exists in all of them.
  # Filtering with `%in%` on the id alone pulled in whatever shared the number
  # elsewhere, and a request for A-Ci curves came back carrying `PLCstem`.
  db <- pivot_db()

  aci <- response_pivot_wider(db, data_type = "ACi")

  expect_true(all(c("A", "Ci") %in% names(aci)))
  expect_false(any(c("PLCstem", "PSIstem") %in% names(aci)))
  expect_equal(unique(aci$dataset_id), "Test")
})


test_that("values come back as numbers, and empty columns are dropped", {
  db <- pivot_db()

  out <- response_pivot_wider(db, data_type = "stem hydraulic vulnerability")

  expect_true(is.numeric(out$PSIstem))
  expect_equal(sort(out$PLCstem), c(10, 90))
  # A and Ci belong to the other dataset and are all-NA here
  expect_false(any(c("A", "Ci") %in% names(out)))

  # ...and both can be turned off
  raw <- response_pivot_wider(db, data_type = "ACi", numeric = FALSE)
  expect_type(raw$A, "character")
})


test_that("an unknown data_type names the ones that exist", {
  expect_error(
    response_pivot_wider(pivot_db(), data_type = "AQi"),
    "No such data_type: AQi"
  )
  expect_error(
    response_pivot_wider(pivot_db(), data_type = "AQi"),
    "This database has: ACi"
  )
})
