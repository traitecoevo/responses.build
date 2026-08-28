# responses.build — plan

Status as of 2026-08-28. This file records what has been decided and why, what is still open, and the invariants a future change could break without noticing. Keep it current or retire it.

## Why this repo exists

`AusFizz` holds physiological response-curve data — leaf gas exchange (A‑Ci, A‑Q, A‑Ci‑T), hydraulic vulnerability, fluorescence. It was built on `traits.build`, whose data model assumes a measurement is **one value for one entity**. A response curve is not that: it is a set of paired measurements taken across a driver gradient, which belong together as one identifiable curve.

With no first-class representation for any of that, four unrelated things end up inside the `contexts` block:

- the **curve driver** — the x-axis of the curve itself (e.g. `leaf_temperature_settings_Cel`, `Ci`)
- the **curve identity** — which points form one curve (e.g. `tree_number`, enumerated `ch01`…`ch17` by hand)
- **instrument and method metadata** (`instrument`, `data_type: ACi-T`)
- genuine **treatments** (CO₂, temperature)

Measured on the current AusFizz `master`: 8,524 lines of `metadata.yml` across 30 datasets, with context blocks up to 104 lines (`Crous_2013`). The encoding works, but it is verbose, repetitive, and cannot answer "give me the A‑Ci curve for individual X" without knowing the local convention each dataset invented.

This package exists to give response curves a first-class representation instead. **That model is not implemented yet.**

## Decisions taken

**Name: `responses.build`.** Sibling of `traits.build`, named for what it builds. Domain-neutral rather than `physiology.build`, so it can later serve any response-curve data; `traits.build`'s own history is generalisation away from a domain (`austraits.build` → `traits.build`), and repeating that mistake was not attractive. Rejected `physiologyresponse.build` as long and awkward as a `library()` call.

**Fork, not extension.** Decided before this repo existed, after trying to fit the data into `traits.build`'s `contexts`.

**Fork point: `traits.build` `develop` @ `c2be7f9` (2.1.0.900).** The initial commit changes nothing but the package's own identity — name, version, authorship, `system.file()` lookups, schema filename.

**The public API stays identical.** `dataset_configure()`, `dataset_process()`, `dataset_update_taxonomy()`, `build_setup_pipeline()` and the rest keep their names and signatures, so a database repository switches engines by changing which package it loads and nothing else. Diverge here only when the response-curve model genuinely requires it.

**Version starts at 0.1.0.9000**, not continuing upstream's 2.1.0.900. The engine version is stamped into every built database, so a shared numbering would be actively misleading.

**The schema stays byte-identical to upstream's** (`inst/support/responses.build_schema.yml`). `traits.build` remains the source of truth for the shared structure; this repo owns only response-curve extensions to it, of which there are none yet. A rename of the file's *contents* was reverted for exactly this reason — see the invariant below.

## Invariant: builds must stay identical under either backend

While the response-curve model is unimplemented, a database built with `responses.build` must match one built with `traits.build` **everywhere except the engine version stamp and `build_info$session_info`**.

Verified on AusFizz (30 datasets, 2026-08-28): all of `traits`, `locations`, `contexts`, `methods`, `excluded_data`, `taxonomic_updates`, `taxa`, `identifiers`, `contributors`, `sources`, `definitions`, `schema` and `metadata` are identical. Reproduce with `scripts/compare-backends.R`.

This is not ceremony. It is what makes the fork rebasable against an upstream that is still moving (`traitecoevo/traits.build` epic #225 is mid-flight). Every deliberate divergence should be a commit that says so.

## Two upstream identities that must not be "tidied up"

`austraits` is a hard dependency of every database built here, and it couples to two things:

1. **The emitted S3 class is `traits.build`** (`R/process.R`). `austraits` dispatches on it (`print.traits.build`).
2. **The `isCompiledBy` related identifier is `https://github.com/traitecoevo/traits.build`** (`R/process.R`). `austraits:::get_compiled_by_traits.build()` **string-matches that exact URL** to decide whether a database is readable at all; if it matches nothing, `check_compatibility()` returns `FALSE` and every accessor refuses to run. It is a compatibility handshake, not a provenance claim.

Changing #2 to the fork's own URL was tried and reverted: it broke six tests, all of them downstream `austraits` calls. Both are now pinned by tests.

**Open — honest provenance.** The right end state is that a database records *which* engine compiled it. That needs `austraits` to match either URL (or better, to stop string-matching a URL) **before** this package emits a second row. Cross-package change; coordinate with `traitecoevo/austraits`.

## Open — the response-curve data model

Not started. The design question to settle first: what is the minimal addition that lets a curve be addressed as an object? Sketch, to be argued rather than assumed:

- a **curve identifier**, so points can be grouped without per-dataset conventions
- a **driver** column pair (variable + value) distinguished from `contexts`
- a rule for which existing `contexts` entries migrate to each of the above

Whatever is chosen has to come with a migration path for the 30 AusFizz datasets, since their current encoding is the only real corpus.

## Inherited debt, deliberately not fixed

- 80 lintr findings remain: 55 `line_length`, 9 `return_linter`, 8 `object_name`, 8 `object_usage`. Fixing them would diverge ~70 lines from upstream for no behavioural gain. `types` in `R/setup.R:646` is a false positive — it is used at line 663.
- `ontology/` is carried over verbatim and still describes the `traits.build` ontology, published under w3id. It is not ours to rename. Decide later whether the fork needs its own or should keep referencing upstream's.
- `NEWS.md` keeps upstream's history below a fork marker, for provenance.
- No hex logo: upstream's was removed as `traits.build` branding. `responses.build` needs its own.
- `tests/testthat/config/testgit.zip` must be force-added (`git add -f`) — `.gitignore` has `*.zip`, and the test suite unzips it to create the `.git` fixture `util_get_SHA()` needs.
