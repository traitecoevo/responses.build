# responses.build 0.1.0.9000 (development version)

- Forked from `traits.build` at `develop` commit `c2be7f9` (version 2.1.0.900). The initial commit changed nothing but the package's own identity — its name, version, authorship, and the `system.file()` lookups and schema filename that follow from it — and a database built with either engine was identical apart from the version stamp. That parity was retired in Stage 0; the entries below are where the two diverge.
- `PLAN.md` sets out the seven stages that implement the response-curve model. Stages 0 to 2 are below; the model is now in the built object, and Stage 3 rewrites the AusFizz metadata against it.
- **Severed the `austraits` linkage.** `austraits` is no longer a dependency. Built databases now carry the S3 class `responses.build` and record `https://github.com/traitecoevo/responses.build` as the `isCompiledBy` related identifier — honest provenance, where both previously reported upstream's so that `austraits::check_compatibility()` would accept the output. Both are pinned by tests. The AusTraits pipeline remains the long-term goal, but as a data handoff rather than a runtime dependency.
- `convert_list_to_df1()`, `convert_list_to_df2()` and `convert_df_to_list()` are now defined here rather than re-exported from `austraits`. The deprecated aliases `util_list_to_df1()`, `util_list_to_df2()`, `util_df_to_list()` and `build_combine()` are removed, as is `database_create_combined_table()` — a pass-through to `austraits::flatten_database()`. The `curve_points` table replaces the combined table in Stage 2.
- **`bind_databases()` no longer discards a licence silently.** Merging databases took the metadata block of its first argument and dropped the rest, so merging a public compilation with a restricted one stamped the result with the public licence while it held all-rights-reserved data, decided purely by argument order. It now refuses to merge databases declaring different `rights` unless the caller states the merged licence via `rights` or `license`.
- **`get_definitions()` reads `config/variables.yml`.** The build's vocabulary is the per-point instrument readings — `A`, `Ci`, `gsw`, `Tleaf` — which are variables, not traits; `config/traits.yml` is now reserved for derived parameters. A compilation still keeping its vocabulary in `traits.yml` is read from there with a message, so repositories can move at their own pace. The `remake`, `base` and `furrr` templates call `get_definitions()` instead of `get_schema("config/traits.yml", "traits")`.
- **Built databases now carry `curves` and `curve_points`.** A response curve is addressable: `curves` has one row per curve, with what it is (`data_type`), what it was measured across (`driver`), and how many points it holds; `curve_points` has one row per point and one column per variable -- the shape the measurements were taken in. On AusFizz that is 50,506 rows where `traits` needs 584,338, with every value recoverable. A single-point observation is a curve of length one, not a special case. `traits` is unchanged.
- New: `get_data_types()`, `check_curve_pairing()` (curves whose variables cannot be paired because no point order was recorded), `check_curve_points_conflicts()` (variables with two values at one point). `dataset_process()` gains a `data_types` argument, defaulting to `config/data_types.yml` if present.
- **A dataset describes what it measured with `measurements:`, not `traits:`.** One block per data file: name the instrument and its column map is resolved from `config/instruments/`, write the methods paragraph once instead of once per variable, and list only deviations under `variables_extra`. `column_suffix` lets one file carry two data types, which is what a study measuring both A-Ci curves and survey points in one spreadsheet needs. A hand-written `traits:` block still builds. On AusFizz this took the metadata from 8,872 lines to 5,832, with every table of the built database identical before and after.
- New: `get_instruments()`. `dataset_configure()` gains `instruments` and `data_types` arguments. `write_metadata()` knows about `measurements:` and `treatments:`, and no longer drops a section it does not recognise.
- **Context ids no longer depend on the order the metadata happens to list properties in.** The id for a context combination is assigned by sorting a key built from every property in that category, and that key was pasted in file order -- so reversing a dataset's `contexts:` block left the grouping identical but swapped the labels `02` and `03` on `treatment_context_id`. The properties are now sorted first, the same way `observation_id` and `location_id` already were, and for the same reason: a build must not depend on incidental input order.

  **This relabels ids.** Verified across AusFizz's 30 datasets that every id column keeps exactly the same grouping -- each is a relabelling, none a regrouping -- and that `contexts` content and `curve_points` values are unchanged. But `observation_id`, `entity_context_id`, `treatment_context_id`, `temporal_context_id` and `method_context_id` may carry different integers than a previous build gave them, so an analysis that saved those ids and joins on them needs rebuilding. This is the one time it moves.
- **A dataset declares its constant descriptors once, in `dataset:`.** `instrument`, `growth_environment`, `leaf_status` and the rest were each written twice — a literal inside `custom_R_code` making a column of one repeated value, and a `contexts` entry naming that column. Declared once now; the build puts back both, taking each descriptor's context category from `config/vocabularies.yml`. On AusFizz this removed a further 868 metadata lines and left five datasets with no `custom_R_code` at all.
- New: `get_vocabularies()`, `check_vocabularies()` (descriptor values outside their controlled vocabulary — reported, not enforced). `dataset_process()` gains a `vocabularies` argument.
- **Built databases carry a `treatments` table**, saying what each experimental treatment did as named, united numbers rather than as a sentence. Additive: the `treatment_context` keeps its id and its link to the measurements. A level whose study stated no quantity appears with its label and no factor — the record of an unstated quantity, not a gap. New: `get_treatment_factors()`.
- **Dataset-level descriptors live in a `descriptors:` block, not in `dataset:`.** A `dataset:` field means "a column name, or the value itself", so `plant_organ: leaf` in a file with a column called `leaf` was read as a column reference and renamed it. Descriptors are always values. They are expanded before `custom_R_code` runs, restored after it and their gaps filled — code that reads, drops or joins on them all work — and a descriptor that is not constant after `custom_R_code` is now an error rather than a silently flattened column.
- `contexts` rows now sort by `context_property` and `value` as well as `dataset_id` and `category`, so the published row order no longer moves when a context is added or removed.
- `dataset_report()` is temporarily out of service and says so. Its template is written against the `austraits` reader, whose accessors reject databases built here now the handshake is severed. Stage 6 rewrites it against the curve tables.

---

Everything below is inherited history from `traits.build`, retained for provenance.

# traits.build (development version)

- `dataset_test()` no longer aborts with `the condition has length > 1` for a dataset that declares more than one identifier. `metadata$identifiers` is a list, so `is.na()` on it returns one value per identifier.
- Builds are now reproducible across machines. `observation_id`, `location_id` and the context ids were generated by sorting with `sort()` and `as.factor()`, which collate according to the session's `LC_COLLATE`. The same dataset therefore produced different ids on a contributor's machine than on CI, which runs in the C locale (#29). Ids are now always generated using C-locale collation, matching what previous builds produced on CI, so existing outputs are unchanged. `util_separate_and_sort()` is likewise no longer locale-dependent.
- `process_format_identifiers()` no longer fails with `object 'schema' not found`. Its third argument is the schema, as documented, rather than the trait data, and it now reads the identifiers list it is passed instead of looking one level too deep. `dataset_test()` was erroring on every dataset that declares identifiers.
- `metadata_add_contexts()` no longer writes time-valued contexts as a number of seconds (`9:00:00` became `32400.0`) when called with `user_responses`, and now reports when a time column has been reformatted so the recorded values can be recognised as matching `data.csv` (#49).
- `metadata_add_contexts()`, `metadata_add_traits()` and `metadata_add_identifiers()` now guess column types from the same number of rows as the build (`guess_max = 100000`), so a sparse column can no longer be typed one way when metadata is written and another way when the database is built.
- `metadata_add_source_doi()` now reports clearly that the optional `rcrossref` package is needed, and offers to install it in interactive sessions, instead of failing with `there is no package called 'rcrossref'` (#178).
- Corrected the link to the AusTraits source repository, which had been misspelled `autraits.build` in `DESCRIPTION`, the package documentation and `NEWS.md`, and pointed at a URL that did not resolve. The Code of Conduct and reference website links in `README.md` were also dead or redirecting, and now resolve directly.
- Added `CITATION.cff` and `inst/CITATION`, so `citation("traits.build")` and GitHub's "Cite this repository" widget both return the Wenk et al. (2024) paper. `CITATION.cff` is excluded from the package tarball via `.Rbuildignore`.
- Removed a duplicated "AusTraits family" section from `README.md`, which had been added twice.

# traits.build 2.1.0

- Identifiers table added, allowing trait values to be linked to a specific identifiers in an herbarium, museum collection, GenBank, or an arboretum. If a data contributor has collected data on the same individual plants across multiple datasets, these can also be linked.
- Methods table documents the dataset's Bibtex types, whether the data are from a Journal article, Online resource, Unpublished dataset, Thesis, etc.
- Additional entity_type values added to schema, included `standard_error`, `standard_deviation`.
- A collection of minor errors have been fixed - including empty datasets breaking the build process, and the wrong location name column being read in

# traits.build 2.0.0

- traits.build paper published in Sep 2024 in Ecological Informatics (DOI: [10.1016/j.ecoinf.2024.102773](https://doi.org/10.1016/j.ecoinf.2024.102773))
- Added standard error and standard deviation as value types
- Moved functions to austraits package and made austraits package a dependancy
- Renamed some of the functions that are now moved to austraits package 
    * `bind_databases` <-- `build_combine`
    * `convert_df_to_list` <-- `util_df_to_list`
    * `convert_list_to_df1` <-- `util_list_to_df1`
    * `convert_list_to_df2` <-- `util_list_to_df2`
- Renamed functions still *also* assigned their old name, with a deprecation warning indicating the new name  
- `plot_trait_distribution_beeswarm`, `trait_pivot_longer` and `trait_pivot_wider` had been in both austraits and traits.build packages and have now been removed from traits.build
- Import new austraits function `flatten_database` (had been suggested to be `database_create_combined_table`)
- Refactoring of test functions used by `dataset_test`
- Added tests using the `dataset_test` function, so it is checked explicitly by traits.build (run on Example datasets)
- Minor bug fixes
- Minor updates to ontology (now version 1.0)

# traits.build 1.1.0

- Small bugfixes in dataset_test
- Add Onotology
- Add Hex sticker


# traits.build 1.0.1

As described in #134, fixes some minor issues with 

- testing of datasets in `dataset_test`
- generating of reports
- standardising of taxonomic names. 

# traits.build 1.0.0

This is the first major release of the {traits.build} package, providing a workflow to harmonise trait data from diverse sources. The code was originally built to support AusTraits (see Falster et al 2021, <doi:10.1038/s41597-021-01006-6>, <https://github.com/traitecoevo/austraits.build>) and has been generalised here to support construction of other trait databases. Detailed instructions are available at

- package website: <https://traitecoevo.github.io/traits.build/>
- package book: <https://traitecoevo.github.io/traits.build-book/>

