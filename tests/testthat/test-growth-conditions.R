# A treatment was recorded as a verbatim level and a sentence: `elevated`,
# "plants grown in 3 degrees C above ambient temperatures". Readable, and
# useless for comparing studies -- `elevated` is +3 C in one and +4 in another.

CONDITIONS <- list(
  growth_air_temperature_offset = list(unit = "C"),
  growth_co2_offset = list(unit = "umol{CO2}/mol")
)

ctx <- tibble::tibble(
  dataset_id = "Test",
  context_property = "growth_temperature_treatment",
  category = "treatment_context",
  value = c("ambient", "elevated"),
  description = NA_character_,
  link_id = "treatment_context_id",
  link_vals = c("01, 03", "02")
)

md <- function(...) list(growth_conditions = list(...))


test_that("a factor becomes one row per treatment context it applies to", {
  out <- process_create_growth_conditions(
    md(list(context_property = "growth_temperature_treatment", value = "elevated",
            conditions = list(list(condition = "growth_air_temperature_offset", value = 3)))),
    ctx, CONDITIONS, "Test"
  )

  expect_equal(nrow(out), 1)
  expect_equal(out$treatment_context_id, "02")
  expect_equal(out$value, "3")
  expect_equal(out$label, "elevated")
  # The unit comes from the factor definition, not from the dataset
  expect_equal(out$unit, "C")
})


test_that("`link_vals` is a list of ids, so one level can cover several", {
  out <- process_create_growth_conditions(
    md(list(context_property = "growth_temperature_treatment", value = "ambient",
            conditions = list(list(condition = "growth_air_temperature_offset", value = 0)))),
    ctx, CONDITIONS, "Test"
  )

  expect_equal(nrow(out), 2)
  expect_setequal(out$treatment_context_id, c("01", "03"))
})


test_that("a level with no stated quantity is recorded, not dropped", {
  # Most water treatments in AusFizz are `well-watered` against `water deficit`
  # with no number anywhere. The absence is the record of an unstated quantity.
  out <- process_create_growth_conditions(
    md(list(context_property = "growth_temperature_treatment", value = "ambient")),
    ctx, CONDITIONS, "Test"
  )

  expect_equal(nrow(out), 2)
  expect_true(all(is.na(out$condition)))
  expect_equal(unique(out$label), "ambient")
})


test_that("a treatment must describe a level that exists", {
  expect_error(
    process_create_growth_conditions(
      md(list(context_property = "growth_temperature_treatment", value = "scorching",
              conditions = list(list(condition = "growth_air_temperature_offset", value = 9)))),
      ctx, CONDITIONS, "Test"),
    "no treatment context has `growth_temperature_treatment` = 'scorching'"
  )
})


test_that("an undefined factor, a factor with no value, and a wrong unit all fail", {
  base <- function(f) md(list(context_property = "growth_temperature_treatment",
                              value = "elevated", conditions = list(f)))

  expect_error(
    process_create_growth_conditions(base(list(condition = "made_up", value = 1)), ctx, CONDITIONS, "Test"),
    "is not defined in config/growth_conditions.yml"
  )
  expect_error(
    process_create_growth_conditions(
      base(list(condition = "growth_air_temperature_offset")), ctx, CONDITIONS, "Test"),
    "no `value`"
  )
  # A dataset naming a different unit is stating a disagreement, not a variant
  expect_error(
    process_create_growth_conditions(
      base(list(condition = "growth_air_temperature_offset", value = 3, unit = "K")),
      ctx, CONDITIONS, "Test"),
    "unit 'K' but the condition is defined in 'C'"
  )
})


test_that("a block has to say which level it describes", {
  expect_error(
    process_create_growth_conditions(md(list(value = "elevated")), ctx, CONDITIONS, "Falster_2005"),
    "Falster_2005, growth_conditions block 1: applies to the whole dataset but lists no conditions"
  )
})


test_that("no treatments block gives an empty table with the right columns", {
  out <- process_create_growth_conditions(list(), ctx, CONDITIONS, "Test")

  expect_equal(nrow(out), 0)
  expect_named(out, c("dataset_id", "treatment_context_id", "context_property",
                      "label", "condition", "value", "unit", "manipulated"))
})


test_that("`get_growth_conditions` is empty rather than failing when absent", {
  d <- withr::local_tempdir()
  withr::local_dir(d)
  expect_equal(get_growth_conditions(), list())
})


test_that("`get_growth_conditions` rejects a file without the expected block", {
  d <- withr::local_tempdir()
  path <- file.path(d, "tf.yml")
  writeLines(c("something:", "  elements:", "    x:"), path)
  expect_error(get_growth_conditions(path),
               "no `growth_conditions: elements:` block", fixed = TRUE)
})
