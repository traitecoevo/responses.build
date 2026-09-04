# `variables` are the per-point instrument readings; `traits` are the derived
# parameters fitted from a curve. The upstream data model used one word for
# both, which is what `get_definitions()` exists to separate. A compilation on
# either layout must build.

write_defs <- function(dir, key, file) {
  dir.create(file.path(dir, "config"), showWarnings = FALSE, recursive = TRUE)
  writeLines(
    c(paste0(key, ":"),
      "  description: test",
      "  type: list",
      "  elements:",
      "    A:",
      "      label: Assimilation",
      "      type: numeric",
      "      units: umol{CO2}/m2/s",
      "      allowed_values_min: -20",
      "      allowed_values_max: 120"),
    file.path(dir, "config", file)
  )
}


test_that("`get_definitions` reads config/variables.yml without comment", {
  d <- withr::local_tempdir()
  write_defs(d, "variables", "variables.yml")
  withr::local_dir(d)

  expect_silent(defs <- get_definitions())
  expect_named(defs$elements, "A")
  expect_equal(defs$elements$A$units, "umol{CO2}/m2/s")
})


test_that("`get_definitions` still reads config/traits.yml, and says why not to", {
  # The fallback lets a compilation move at its own pace. It is not a second
  # supported layout, so it is not silent.
  d <- withr::local_tempdir()
  write_defs(d, "traits", "traits.yml")
  withr::local_dir(d)

  expect_message(defs <- get_definitions(), "not traits")
  expect_named(defs$elements, "A")
})


test_that("`get_definitions` prefers variables.yml when both exist", {
  # A repository mid-migration has both. The new file wins, and the message
  # about the old one must not fire.
  d <- withr::local_tempdir()
  write_defs(d, "variables", "variables.yml")
  write_defs(d, "traits", "traits.yml")
  withr::local_dir(d)

  expect_silent(get_definitions())
})


test_that("`get_definitions` reads either top-level key from an explicit path", {
  d <- withr::local_tempdir()
  write_defs(d, "variables", "variables.yml")
  write_defs(d, "traits", "traits.yml")

  expect_equal(
    get_definitions(file.path(d, "config", "variables.yml")),
    get_definitions(file.path(d, "config", "traits.yml"))
  )
})


test_that("`get_definitions` names the directory it looked in", {
  # "cannot open the connection" names neither the file nor where it looked.
  d <- withr::local_tempdir()
  withr::local_dir(d)

  expect_error(get_definitions(), "No variable definitions found")
  expect_error(get_definitions(), "variables.yml")
  # The message has to say where it looked, and the search directory is now a
  # parameter rather than always `config`
  expect_error(get_definitions(dir = "elsewhere"), "elsewhere")
})


test_that("`get_definitions` rejects a file with neither block, and lists what it found", {
  d <- withr::local_tempdir()
  dir.create(file.path(d, "config"))
  path <- file.path(d, "config", "variables.yml")
  writeLines(c("definitions:", "  elements:", "    A:", "      type: numeric"), path)

  expect_error(get_definitions(path), "no `variables:`")
  expect_error(get_definitions(path), "definitions")
})
