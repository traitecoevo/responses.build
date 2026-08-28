# `measurements:` is how a dataset says what it measured. It desugars into the
# `traits:` list the rest of the build understands, so nothing downstream needs
# to know which form a dataset was written in.

profile_dir <- function() {
  d <- withr::local_tempdir(.local_envir = parent.frame())
  dir.create(file.path(d, "instruments"))
  writeLines(c(
    "instrument:",
    "  label: Test analyser",
    "  matches:",
    "  - Test IRGA",
    "  columns:",
    "    A:",
    '      var_in: "Photo"',
    '      unit_in: "umol{CO2}/m2/s"',
    "      aliases:",
    '      - "A"',
    "    Ci:",
    '      var_in: "Ci"',
    '      unit_in: "umol{CO2}/mol"',
    "    gsw:",
    '      var_in: "Cond"',
    '      unit_in: "mol{H2O}/m2/s"'
  ), file.path(d, "instruments", "test_irga.yml"))
  d
}

dts <- list(ACi = list(driver = "Ci"), survey = list(driver = ".na"))

md <- function(...) list(dataset = list(), measurements = list(...))


test_that("naming an instrument maps its whole column set", {
  instr <- get_instruments(file.path(profile_dir(), "instruments"))

  out <- metadata_expand_measurements(
    md(list(data_type = "ACi", instrument = "Test IRGA", methods = "how")),
    instr, dts
  )

  mapping <- convert_list_to_df2(out$traits)
  expect_equal(nrow(mapping), 3)
  expect_setequal(mapping$trait_name, c("A", "Ci", "gsw"))
  expect_equal(mapping$var_in[mapping$trait_name == "A"], "Photo")
  # The methods paragraph is written once and carried onto every variable --
  # 369 entries holding 34 distinct strings is what this removes
  expect_equal(unique(mapping$methods), "how")
  # Defaults every dataset previously wrote out per trait
  expect_equal(unique(mapping$value_type), "raw")
  expect_equal(unique(mapping$entity_type), "individual")
})


test_that("an instrument profile resolves by file stem or by instrument string", {
  instr <- get_instruments(file.path(profile_dir(), "instruments"))

  by_stem <- metadata_expand_measurements(
    md(list(instrument = "test_irga", methods = "how")), instr, dts)
  by_name <- metadata_expand_measurements(
    md(list(instrument = "Test IRGA", methods = "how")), instr, dts)

  expect_equal(by_stem$traits, by_name$traits)
})


test_that("`use` restricts to part of the profile", {
  instr <- get_instruments(file.path(profile_dir(), "instruments"))

  out <- metadata_expand_measurements(
    md(list(instrument = "Test IRGA", methods = "how", use = list("A", "Ci"))),
    instr, dts
  )

  expect_setequal(convert_list_to_df2(out$traits)$trait_name, c("A", "Ci"))
})


test_that("`variables_extra` survives `use` -- it is not part of the profile", {
  # This was a real bug: merging the extras before applying `use` filtered them
  # out, and the migration silently dropped every variable the profile did not
  # cover. The build gate caught it.
  instr <- get_instruments(file.path(profile_dir(), "instruments"))

  out <- metadata_expand_measurements(
    md(list(
      instrument = "Test IRGA", methods = "how", use = list("A"),
      variables_extra = list(list(variable = "PSIstem", var_in = "MPa", unit_in = "MPa"))
    )),
    instr, dts
  )

  mapping <- convert_list_to_df2(out$traits)
  expect_setequal(mapping$trait_name, c("A", "PSIstem"))
})


test_that("`variables_extra` overrides the profile, and carries its own settings", {
  instr <- get_instruments(file.path(profile_dir(), "instruments"))

  out <- metadata_expand_measurements(
    md(list(
      instrument = "Test IRGA", methods = "how", use = list("A"),
      variables_extra = list(list(
        variable = "A", var_in = "Photosynthesis", unit_in = "umol{CO2}/m2/s",
        value_type = "mean", replicates = 5
      ))
    )),
    instr, dts
  )

  mapping <- convert_list_to_df2(out$traits)
  expect_equal(nrow(mapping), 1)
  expect_equal(mapping$var_in, "Photosynthesis")
  expect_equal(mapping$value_type, "mean")
  expect_equal(mapping$replicates, "5")
})


test_that("`column_suffix` carries a second data type in one file", {
  # Board #3: a study measuring both A-Ci and survey in one spreadsheet writes
  # `Photo` and `Photo_survey_Amax`. One line, not a duplicated column map.
  instr <- get_instruments(file.path(profile_dir(), "instruments"))

  out <- metadata_expand_measurements(
    md(
      list(data_type = "ACi", instrument = "Test IRGA", methods = "curves"),
      list(data_type = "survey", instrument = "Test IRGA",
           column_suffix = "_survey_Amax", methods = "survey points")
    ),
    instr, dts
  )

  mapping <- convert_list_to_df2(out$traits)
  expect_equal(nrow(mapping), 6)
  expect_true("Photo" %in% mapping$var_in)
  expect_true("Photo_survey_Amax" %in% mapping$var_in)
  expect_setequal(unique(mapping$methods), c("curves", "survey points"))
})


test_that("a hand-written `traits:` block still builds, and `measurements:` wins", {
  instr <- get_instruments(file.path(profile_dir(), "instruments"))

  hand <- list(dataset = list(), traits = list(
    list(var_in = "X", unit_in = "m", trait_name = "A", methods = "old")
  ))
  expect_equal(metadata_expand_measurements(hand, instr, dts), hand)

  both <- hand
  both$measurements <- list(list(instrument = "Test IRGA", methods = "new"))
  expect_equal(unique(convert_list_to_df2(
    metadata_expand_measurements(both, instr, dts)$traits)$methods), "new")
})


test_that("a block that cannot be resolved says which block and why", {
  instr <- get_instruments(file.path(profile_dir(), "instruments"))

  expect_error(
    metadata_expand_measurements(md(list(instrument = "Test IRGA")), instr, dts, "Falster_2005"),
    "Falster_2005, measurements block 1: no `methods`"
  )
  expect_error(
    metadata_expand_measurements(md(list(instrument = "Nope", methods = "how")), instr, dts),
    "no profile for instrument 'Nope'"
  )
  expect_error(
    metadata_expand_measurements(
      md(list(instrument = "Test IRGA", methods = "how", use = list("Vcmax"))), instr, dts),
    "`use` names variables the instrument profile does not map: Vcmax"
  )
  expect_error(
    metadata_expand_measurements(md(list(methods = "how")), instr, dts),
    "names neither an `instrument` nor any `variables_extra`"
  )
  expect_error(
    metadata_expand_measurements(
      md(list(data_type = "not a type", instrument = "Test IRGA", methods = "how")),
      instr, dts),
    "is not defined in config/data_types.yml"
  )
})


test_that("`get_instruments` is empty rather than failing when there is no directory", {
  d <- withr::local_tempdir()
  withr::local_dir(d)
  expect_equal(get_instruments(), list())
})


test_that("`get_instruments` rejects a profile with no columns", {
  d <- withr::local_tempdir()
  writeLines(c("instrument:", "  label: Broken"), file.path(d, "broken.yml"))
  expect_error(get_instruments(d), "no `instrument: columns:` block", fixed = TRUE)
})
