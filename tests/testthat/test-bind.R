# Merging databases merges data held under different licences. The version of
# `bind_databases()` inherited from `austraits` took `databases[[1]][["metadata"]]`
# and discarded the rest, so merging AusFizz (CC-BY-4.0) with ausfizz-private
# (all rights reserved) stamped the result CC-BY-4.0 while it held restricted
# data, and nothing warned. Argument order decided the licence.

make_db <- function(rights, dataset_id = "Test_2022") {
  db <- list(
    measurements = tibble::tibble(
      dataset_id = dataset_id, taxon_name = "Acacia aneura",
      observation_id = "001", response_id = "01", point_id = "01",
      variable = "A", value = "1"
    ),
    locations = tibble::tibble(dataset_id = dataset_id, location_id = "01"),
    contexts = tibble::tibble(dataset_id = dataset_id, category = "method_context"),
    methods = tibble::tibble(dataset_id = dataset_id, trait_name = "A"),
    excluded_data = tibble::tibble(
      dataset_id = dataset_id, observation_id = "001", variable = "A"
    ),
    taxonomic_updates = tibble::tibble(
      original_name = "Acacia aneura", aligned_name = "Acacia aneura",
      taxon_name = "Acacia aneura", taxonomic_resolution = "species"
    ),
    taxa = tibble::tibble(taxon_name = "Acacia aneura"),
    identifiers = tibble::tibble(dataset_id = dataset_id),
    contributors = tibble::tibble(
      dataset_id = dataset_id, last_name = "Falster", given_name = "Daniel"
    ),
    sources = list(),
    definitions = list(),
    schema = list(),
    metadata = list(
      license = list(
        rights = rights,
        rights_holder = "Falster, Daniel",
        rights_URI = paste0("https://example.org/", rights)
      )
    )
  )
  class(db) <- c("list", "responses.build")
  db
}


test_that("merging databases with the same licence keeps it", {
  merged <- bind_databases(databases = list(
    make_db("CC-BY-4.0", "Test_2022"),
    make_db("CC-BY-4.0", "Test_2023")
  ))

  expect_s3_class(merged, "responses.build")
  expect_equal(merged$metadata$license$rights, "CC-BY-4.0")
  expect_equal(nrow(merged$measurements), 2)
})


test_that("merging different licences refuses rather than picking the first", {
  # The whole point: this used to succeed silently and stamp the result with
  # whichever database was passed first.
  public <- make_db("CC-BY-4.0", "Test_2022")
  restricted <- make_db("All rights reserved", "Test_2023")

  expect_error(
    bind_databases(databases = list(public, restricted)),
    "declare different licences"
  )

  # ...and it is not a matter of argument order
  expect_error(
    bind_databases(databases = list(restricted, public)),
    "declare different licences"
  )
})


test_that("a stated licence resolves the merge, and carries its whole block", {
  public <- make_db("CC-BY-4.0", "Test_2022")
  restricted <- make_db("All rights reserved", "Test_2023")

  merged <- bind_databases(
    databases = list(public, restricted),
    rights = "All rights reserved"
  )

  expect_equal(merged$metadata$license$rights, "All rights reserved")
  # The holder and URI come from the input that declared these rights, so the
  # block cannot end up internally inconsistent
  expect_equal(
    merged$metadata$license$rights_URI,
    "https://example.org/All rights reserved"
  )
  expect_equal(nrow(merged$measurements), 2)
})


test_that("a licence not declared by any input drops the stale URI and description", {
  merged <- bind_databases(
    databases = list(make_db("CC-BY-4.0"), make_db("All rights reserved", "Test_2023")),
    rights = "CC-BY-NC-4.0"
  )

  expect_equal(merged$metadata$license$rights, "CC-BY-NC-4.0")
  # Better absent than pointing at the wrong licence
  expect_null(merged$metadata$license$rights_URI)
  expect_null(merged$metadata$license$description)
})


test_that("`bind_databases` needs at least one database", {
  expect_error(bind_databases(databases = list()), "at least one database")
  expect_error(bind_databases(databases = list(NULL)), "at least one database")
})
