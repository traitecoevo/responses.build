#!/usr/bin/env Rscript
#
# Compare a database built with `traits.build` against the same database built
# with `responses.build`.
#
# While the response-curve data model is unimplemented, the two must agree
# everywhere except where the engine necessarily stamps its own identity. Run
# this after any change to R/ to confirm the divergence is still deliberate.
#
# Usage, from a database repository (e.g. AusFizz):
#
#   Rscript -e 'library(traits.build);    build_setup_pipeline("base", database_name = "X")'
#   Rscript build.R && cp export/data/curr/X.rds /tmp/x_traits.rds
#   Rscript -e 'library(responses.build); build_setup_pipeline("base", database_name = "X")'
#   Rscript build.R && cp export/data/curr/X.rds /tmp/x_responses.rds
#   Rscript scripts/compare-backends.R /tmp/x_traits.rds /tmp/x_responses.rds

args <- commandArgs(trailingOnly = TRUE)
if (length(args) != 2L) {
  stop("usage: compare-backends.R <traits.build.rds> <responses.build.rds>", call. = FALSE)
}

a <- readRDS(args[[1]])
b <- readRDS(args[[2]])

# `build_info$session_info` records the loaded namespaces, so it names whichever
# engine was attached and can never match. Excluded by construction, not because
# it happened to differ.
excluded <- "build_info"

# The engine version stamp lives in the `isCompiledBy` related identifier. The
# URL there is a compatibility handshake and must be identical; only the version
# is expected to differ.
split_build_stamp <- function(db) {
  ids <- db$metadata$related_identifiers
  is_engine <- vapply(
    ids,
    function(e) identical(e$identifier, "https://github.com/traitecoevo/traits.build"),
    logical(1)
  )
  list(
    stamp = ids[is_engine],
    metadata_without_stamp = {
      db$metadata$related_identifiers <- ids[!is_engine]
      db$metadata
    }
  )
}

failures <- character(0)
report <- function(label, ok, detail = NULL) {
  cat(sprintf("%-28s %s\n", label, if (ok) "identical" else "DIFFERS"))
  if (!ok) {
    failures <<- c(failures, label)
    if (!is.null(detail)) cat(paste0("    ", detail, collapse = "\n"), "\n")
  }
}

cat("Comparing", basename(args[[1]]), "vs", basename(args[[2]]), "\n\n")

report("names()", identical(names(a), names(b)))
report("class()", identical(class(a), class(b)),
       paste(deparse(class(a)), "vs", deparse(class(b))))

for (nm in setdiff(names(a), c(excluded, "metadata"))) {
  cmp <- all.equal(a[[nm]], b[[nm]])
  report(nm, isTRUE(cmp), if (!isTRUE(cmp)) utils::head(cmp, 5))
}

sa <- split_build_stamp(a)
sb <- split_build_stamp(b)
cmp <- all.equal(sa$metadata_without_stamp, sb$metadata_without_stamp)
report("metadata (minus stamp)", isTRUE(cmp), if (!isTRUE(cmp)) utils::head(cmp, 5))

cat("\nEngine stamp (expected to differ in `version` only):\n")
str(sa$stamp, max.level = 3)
str(sb$stamp, max.level = 3)

stamp_url_ok <- identical(
  lapply(sa$stamp, `[[`, "identifier"),
  lapply(sb$stamp, `[[`, "identifier")
)
report("stamp identifier URL", stamp_url_ok)

cat("\n")
if (length(failures) > 0) {
  stop("backends diverge in: ", paste(failures, collapse = ", "), call. = FALSE)
}
cat("PASS: backends agree everywhere except the engine version stamp and build_info.\n")
