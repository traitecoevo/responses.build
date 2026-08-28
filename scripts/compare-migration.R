#!/usr/bin/env Rscript
#
# Compare a database built before a metadata migration against the same
# database built after it.
#
# This replaces `compare-backends.R`, which compared a `traits.build` build
# against a `responses.build` one while the fork was still tracking upstream.
# That invariant is retired (PLAN.md, Stage 0). The invariant that replaces it:
#
#   Stage 3 rewrites all 30 AusFizz `metadata.yml` files into a shorter form.
#   It re-expresses the same facts, so `curves` and `curve_points` must not
#   move. If they do, the migration is wrong.
#
# Same discipline, new anchor. Until Stage 2 lands the curve tables, this falls
# back to comparing every table the build emits.
#
# Usage, from a database repository (e.g. AusFizz):
#
#   # before migrating
#   Rscript -e 'library(responses.build); build_setup_pipeline("base", database_name = "X")'
#   Rscript build.R && cp export/data/curr/X.rds /tmp/x_before.rds
#   # ... run scripts/migrate-metadata-v2.R ...
#   Rscript build.R && cp export/data/curr/X.rds /tmp/x_after.rds
#   Rscript scripts/compare-migration.R /tmp/x_before.rds /tmp/x_after.rds

args <- commandArgs(trailingOnly = TRUE)
if (length(args) != 2L) {
  stop("usage: compare-migration.R <before.rds> <after.rds>", call. = FALSE)
}

a <- readRDS(args[[1]])
b <- readRDS(args[[2]])

# `build_info$session_info` records the loaded namespaces and the time of the
# build, so it can never match. Excluded by construction, not because it
# happened to differ.
excluded <- "build_info"

# The tables the migration must not move. Once Stage 2 lands, these are the
# whole test; the rest of the tables are reported but a difference in them is
# expected wherever the migration deliberately reshapes `contexts`.
curve_tables <- c("curves", "curve_points")

failures <- character(0)
report <- function(label, ok, detail = NULL, fatal = TRUE) {
  cat(sprintf("%-28s %s\n", label, if (ok) "identical" else "DIFFERS"))
  if (!ok) {
    if (fatal) failures <<- c(failures, label)
    if (!is.null(detail)) cat(paste0("    ", detail, collapse = "\n"), "\n")
  }
}

cat("Comparing", basename(args[[1]]), "vs", basename(args[[2]]), "\n\n")

report("names()", identical(names(a), names(b)))
report("class()", identical(class(a), class(b)),
       paste(deparse(class(a)), "vs", deparse(class(b))))

present_curve_tables <- intersect(curve_tables, names(a))

if (length(present_curve_tables) == 0) {
  cat("\nNote: no curve tables in this build -- Stage 2 has not landed yet.\n",
      "Comparing every table instead; all differences are fatal.\n\n", sep = "")
}

for (nm in setdiff(names(a), excluded)) {
  cmp <- all.equal(a[[nm]], b[[nm]])
  # Before Stage 2, everything is fatal. After it, only the curve tables are:
  # `contexts` and `methods` are exactly what the migration reshapes.
  fatal <- length(present_curve_tables) == 0 ||
    nm %in% present_curve_tables ||
    !nm %in% c("contexts", "methods", "metadata")
  report(nm, isTRUE(cmp), if (!isTRUE(cmp)) utils::head(cmp, 5), fatal = fatal)
}

cat("\n")
if (length(failures) > 0) {
  stop(
    "The migration changed: ", paste(failures, collapse = ", "), "\n",
    "A migration re-expresses the same facts. A difference here is a bug in ",
    "the migration, not an improvement to the data.",
    call. = FALSE
  )
}
cat("PASS: the migration did not change the build.\n")
