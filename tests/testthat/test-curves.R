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


test_that("points of one curve become one row each, one column per variable", {
  out <- process_create_curves(aci, ctx, dts)

  expect_equal(nrow(out$curves), 1)
  expect_equal(nrow(out$curve_points), 4)
  expect_true(all(c("A", "Ci") %in% names(out$curve_points)))
  # The pairing is the point: point 3 of A goes with point 3 of Ci
  expect_equal(out$curve_points$A[[3]], "15")
  expect_equal(out$curve_points$Ci[[3]], "300")
})


test_that("data_type and driver come off the context and the data type table", {
  out <- process_create_curves(aci, ctx, dts)

  expect_equal(out$curves$data_type, "ACi")
  expect_equal(out$curves$driver, "Ci")
  expect_equal(out$curves$instrument, "Li6400 IRGA")
  expect_equal(out$curves$n_points, "4")
  expect_equal(out$curves$point_order, "recorded")
})


test_that("a nested data type carries both drivers", {
  ctx2 <- ctx
  ctx2$value[[1]] <- "ACi-T"
  out <- process_create_curves(aci, ctx2, dts)

  expect_equal(out$curves$driver, "Ci")
  expect_equal(out$curves$driver_outer, "leaf_temperature_setpoint")
})


test_that("`.na` driver and an unknown data type both give no driver", {
  ctx2 <- ctx
  ctx2$value[[1]] <- "survey"
  expect_true(is.na(process_create_curves(aci, ctx2, dts)$curves$driver))

  ctx3 <- ctx
  ctx3$value[[1]] <- "something we have not defined"
  expect_true(is.na(process_create_curves(aci, ctx3, dts)$curves$driver))
})


test_that("`link_vals` is a list of ids, not one id", {
  # A context value can cover several method contexts, recorded as
  # "01, 02, 03". Joining on the raw string matches none of them, and the
  # curve silently loses its data_type.
  two <- dplyr::bind_rows(aci, dplyr::mutate(aci, method_context_id = "03"))
  ctx2 <- ctx
  ctx2$link_vals <- "01, 03"

  out <- process_create_curves(two, ctx2, dts)

  expect_equal(nrow(out$curves), 2)
  expect_equal(unique(out$curves$data_type), "ACi")
})


test_that("a single-point observation is a curve of length one, not a special case", {
  out <- process_create_curves(make_traits(), ctx, dts)

  expect_equal(nrow(out$curves), 1)
  expect_equal(out$curves$n_points, "1")
  expect_equal(nrow(out$curve_points), 1)
})


test_that("curves are separated by method context", {
  # An ACi-T dataset is one curve per cuvette temperature, and that is what
  # distinguishes them.
  two <- dplyr::bind_rows(aci, dplyr::mutate(aci, method_context_id = "02"))
  out <- process_create_curves(two, ctx, dts)

  expect_equal(nrow(out$curves), 2)
  expect_equal(out$curves$curve_id, c("01", "02"))
  expect_equal(nrow(out$curve_points), 8)
})


test_that("a curve with no recorded point order says so", {
  no_order <- dplyr::mutate(aci, repeat_measurements_id = NA_character_)
  out <- process_create_curves(no_order, ctx, dts)

  expect_equal(out$curves$point_order, "file order")
})


test_that("`check_curve_pairing` flags only curves where the order matters", {
  # No order, several points, several variables -- the values are all there but
  # which A goes with which Ci is not recorded.
  no_order <- dplyr::mutate(aci, repeat_measurements_id = NA_character_)
  bad <- process_create_curves(no_order, ctx, dts)
  # Collapsing every point onto point 01 leaves one row, so build a case where
  # the points survive: two variables, two method contexts, no ordering.
  expect_s3_class(check_curve_pairing(bad), "data.frame")

  # An ordered curve is never flagged
  expect_equal(nrow(check_curve_pairing(process_create_curves(aci, ctx, dts))), 0)

  # Nor is a single point, which needs no ordering
  expect_equal(
    nrow(check_curve_pairing(process_create_curves(make_traits(), ctx, dts))),
    0
  )
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
  out <- process_create_curves(aci[0, ], ctx, dts)

  expect_equal(nrow(out$curves), 0)
  expect_true(all(c("curve_id", "data_type", "driver", "n_points") %in% names(out$curves)))
  expect_true(all(c("curve_id", "point_id") %in% names(out$curve_points)))
})
