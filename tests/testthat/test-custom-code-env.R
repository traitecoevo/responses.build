# `custom_R_code` snippets write `mutate()`, `str_detect()`, `filter()`
# unqualified. Those used to resolve through the search path, which made the
# build depend on `Depends` attaching five tidyverse packages -- and made the
# same snippet behave differently under `library()`, `pkg::`, `Rscript` and a
# `targets` worker.

test_that("the evaluation environment never reaches the search path", {
  # This is the whole point. If the chain ends at `globalenv()`, resolution is
  # back to depending on what a session happens to have attached, and a
  # `targets` worker with a different search path gets a different build.
  env <- responses.build:::util_custom_code_env()

  seen <- character(0)
  e <- env
  while (!identical(e, emptyenv())) {
    seen <- c(seen, environmentName(e))
    if (identical(e, baseenv())) break
    e <- parent.env(e)
  }

  expect_false("R_GlobalEnv" %in% seen)
  expect_true(any(grepl("^base$", seen)))
})


test_that("the environment carries the functions the corpus actually uses", {
  # Surveyed across AusFizz's 30 datasets: 206 unqualified calls over 30
  # distinct functions, all from base, dplyr or stringr.
  env <- responses.build:::util_custom_code_env()

  for (fn in c("mutate", "filter", "group_by", "ungroup", "select", "arrange",
               "summarise", "across", "row_number", "full_join", "join_by",
               "rename_with", "str_c", "str_replace", "str_detect",
               "str_extract", "str_to_lower", "%>%")) {
    expect_true(exists(fn, envir = env), info = fn)
  }

  # ...and base is still reachable through it
  expect_true(exists("ifelse", envir = env))
  expect_true(exists("as.POSIXct", envir = env))
})


test_that("a snippet runs, and `data` is bound rather than found by scoping", {
  f <- responses.build:::process_custom_code(
    "data %>% mutate(b = a * 2) %>% filter(b > 2)"
  )
  out <- f(tibble::tibble(a = c(1, 2, 3)))

  expect_equal(out$b, c(4, 6))
})


test_that("earlier packages shadow later ones, as the search path ordered them", {
  # `dplyr::filter` must win over `stats::filter`, which is what `Depends`
  # attaching dplyr used to achieve.
  env <- responses.build:::util_custom_code_env()

  expect_identical(get("filter", envir = env), dplyr::filter)
  expect_identical(get("lag", envir = env), dplyr::lag)
})


test_that("no custom code is the identity function", {
  expect_identical(responses.build:::process_custom_code(NA), identity)
  expect_identical(responses.build:::process_custom_code(NULL), identity)
  expect_identical(responses.build:::process_custom_code(""), identity)
})
