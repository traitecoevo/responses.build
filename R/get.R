
#' Load schema for an responses.build data compilation (excluding traits)
#'
#' @param path path to schema file. By default loads version included with the package
#' @param subsection section to load
#'
#' @return a list
#' @export
#'
#' @examples{
#'
#' schema <- get_schema()
#' }
get_schema <-
  function(path = system.file("support", "responses.build_schema.yml", package = "responses.build"),
           subsection = NULL) {

  schema <- yaml::read_yaml(path)

  if (!is.null(subsection)) {
    schema <-  schema[[subsection]]
  }

  schema
}

#' Load the vocabulary of variables a compilation measures
#'
#' Reads the definitions of the quantities that appear in the `value` column --
#' the readings taken at each point of a response curve: `A`, `Ci`, `gsw`,
#' `Tleaf`, `PSIstem` and the rest.
#'
#' # `variables`, not `traits`
#'
#' These are instrument readings and measured state, not traits. A trait is a
#' derived parameter with one value per entity -- `Amax`, `Vcmax25`, `P50` --
#' and those live in `config/traits.yml`, which is where curve fitting will
#' eventually write. Calling the readings "traits" is what the upstream data
#' model did, and it is why 590,031 rows in AusFizz encode 50,089 measurements.
#'
#' A compilation that still keeps its vocabulary in `config/traits.yml` is read
#' from there, with a message. That fallback exists so a repository can move at
#' its own pace; it is not a second supported layout.
#'
#' @param path Path to the variable definitions. By default `config/variables.yml`,
#'   falling back to `config/traits.yml` if that does not exist.
#'
#' @return A list of variable definitions
#' @export
#'
#' @examples{
#' \dontrun{
#' definitions <- get_definitions()
#' }
#' }
get_definitions <- function(path = NULL) {

  if (is.null(path)) {
    if (file.exists("config/variables.yml")) {
      path <- "config/variables.yml"
    } else if (file.exists("config/traits.yml")) {
      message(
        "Reading variable definitions from `config/traits.yml`.\n",
        "These are variables -- per-point instrument readings -- not traits. ",
        "Rename the file to `config/variables.yml` and its top-level key to ",
        "`variables`; `config/traits.yml` is for derived parameters."
      )
      path <- "config/traits.yml"
    } else {
      stop(
        "No variable definitions found. Expected `config/variables.yml` ",
        "(or `config/traits.yml`) relative to ", getwd(),
        call. = FALSE
      )
    }
  }

  definitions <- yaml::read_yaml(path)

  # The top-level key names what the file holds, so either is readable without
  # the caller having to know which layout a repository is on.
  key <- intersect(c("variables", "traits"), names(definitions))

  if (length(key) == 0) {
    stop(
      path, " has no `variables:` (or `traits:`) block. Found: ",
      paste(names(definitions), collapse = ", "),
      call. = FALSE
    )
  }

  definitions[[key[[1]]]]
}

#' Retrieve version for compilation from definitions
#'
#' @param path path to traits definitions
#'
#' @return a string
#' @export
util_get_version <- function(path =  "config/metadata.yml") {
  get_schema(path)$metadata$version
}


#' Get SHA string from Github repository for latest commit
#'
#' Get SHA string for the latest commit on Github for the repository. SHA is the
#' abbreviated SHA-1 40 digit hexadecimal number which Github uses as the
#' Commit ID to track changes made to a repo
#'
#' @param path root directory where a specified file is located, default file name
#' is the remake.yml file
#'
#' @return 40-digit SHA character string for the latest commit to the repository
#' @export
util_get_SHA <- function(path = ".") {
  sha <- tryCatch({
      git2r::sha(git2r::last_commit(git2r::repository(path)))
    }, error = function(cond) NA)
  sha
}
