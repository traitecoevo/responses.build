# responses.build — plan

Status as of 2026-08-28. This file records what has been decided and why, what is still open, and the invariants a future change could break without noticing. Keep it current or retire it.

**This plan supersedes the fork-parity plan that preceded it.** That earlier plan pinned an invariant — builds must stay identical under either backend — which existed to cover the initial swap from `traits.build` and has served its purpose. It is retired, and replaced by the migration invariant in Stage 3.

## Why this repo exists

`AusFizz` holds physiological response-curve data — leaf gas exchange (A‑Ci, A‑Q, A‑Ci‑T), hydraulic vulnerability, fluorescence. It was built on `traits.build`, whose data model assumes a measurement is **one value for one entity**. A response curve is not that: it is a set of paired measurements taken across a driver gradient, which belong together as one identifiable curve.

The curves never fitted into AusTraits. The *parameters extracted from them* always did — and that is the long-term purpose of this repository: fit curves, derive traits, contribute those traits to AusTraits.

## The three levels

```
variables      raw per-point readings              A, Ci, gsw, Tleaf, Qin, PSIstem, f0
curves         the curve as an addressable object
traits         derived parameters, one per entity  Amax, Vcmax25, Jmax25, P50, TLP
```

`traits` keeps its name because it is exactly right for the third row. It starts empty rather than misused. `variables` is the term for the raw readings — bland, exact, and it covers a LiCor channel, a pressure-chamber reading and a fluorometer output alike.

**Naming rule, everywhere:** identifiers are `snake_case`; they carry no units, spaces or brackets; units live in a `unit` field beside the value. `latitude (deg)` → `latitude` + `unit: deg`. `leaf_temperature_settings_Cel` → `leaf_temperature_setpoint` + `unit: C`.

## What the corpus costs today — measured on AusFizz `master`, 2026-08-28

| | measured |
|---|---|
| `metadata.yml` across 31 datasets | 8,872 lines / 469,519 chars |
| of which `traits:` mapping blocks | 4,377 lines (49%) |
| trait mappings | 369, over only 3–7 distinct `var_in` aliases per variable |
| `methods:` entries | 369 lines holding **34 distinct strings** — 143,889 chars, 31% of all metadata bytes, ~92% verbatim duplication |
| dataset-level constants injected by `custom_R_code` then re-declared as contexts | 12 properties, each in 24–30 of 31 datasets |
| mappings duplicated purely to carry a second data type | 39 of 369, in `Aspinwall_2016` (542-line yml), `Bloomfield_2014_a` (968), `Blackman_2019` |
| `traits` table | 590,031 rows |
| the same data as one row per curve-point | **50,089 rows — 11.8× smaller** |
| curves with more than one identified point | 2,874 of 25,547 groups |
| `config/traits.yml` definitions | 34, all of them instrument variables, all `entity_URI` empty |
| `individual_id` carrying a curve number | 10 of 29 datasets (`Curve_Id`, `curve_id`, `Curve_number`) |
| `repeat_measurements_id: yes` set | 21 of 31 datasets → 67.4% of rows have one |
| `collection_date` not ISO (d/m/Y) | 19 of 30 datasets, ~half of all rows |

Three conclusions drive everything below.

1. **The vocabulary is wrong.** `A`, `Ci`, `gsw`, `Tleaf`, `Qin`, `flow`, `Patm`, `area` are instrument readings, not properties of a plant. Calling them traits forces every reading of every point into its own row — which is why 590,031 rows encode 50,089 measurements.
2. **The curve has no name.** It is derivable — `(dataset_id, observation_id, method_context_id)` ordered by `repeat_measurements_id` — but nothing says so, so ten datasets smuggle it through `individual_id`, every notebook re-derives it, and a third of rows have no point ordering at all.
3. **Half the metadata restates what a profile could state once.** Every Li‑6400 export has the same columns. Every dataset repeats one methods paragraph twenty times. Twelve descriptors are constant per dataset and written twice each.

## Decisions taken

**Name: `responses.build`.** Sibling of `traits.build`, named for what it builds. Domain-neutral rather than `physiology.build`, so it can later serve any response-curve data; `traits.build`'s own history is generalisation away from a domain (`austraits.build` → `traits.build`), and repeating that mistake was not attractive. Rejected `physiologyresponse.build` as long and awkward as a `library()` call.

**Fork, not extension.** Decided before this repo existed, after trying to fit the data into `traits.build`'s `contexts`.

**Fork point: `traits.build` `develop` @ `c2be7f9` (2.1.0.900).**

**Version starts at 0.1.0.9000**, not continuing upstream's 2.1.0.900. The engine version is stamped into every built database, so a shared numbering would be actively misleading.

**Diverge fully (2026-08-28).** Stop tracking `traits.build`, and drop the `austraits` runtime linkage entirely — no S3-class handshake, no `isCompiledBy` URL match, no package dependency. See Stage 0.

**The AusTraits pipeline becomes a data handoff, not a runtime dependency.** Derived traits will be written out as a `traits.build`-shaped dataset folder that `austraits.build` ingests like any other contribution. A file contract survives refactors on either side; a runtime class-and-URL handshake — as upstream's `get_compiled_by_traits.build()` string match shows — does not.

**targets only** for the build pipeline. **Migrate all 30 AusFizz datasets mechanically.** **Curve-first tables ship as built tables**, not accessor functions.

## Stages

Board issues [#1–#4](https://github.com/orgs/traitecoevo/projects/19) close as consequences of the model rather than as patches: #1 (`data_type` as a core column) in Stage 2, #2 (structured treatments) in Stage 4, #3 (multi-data-type studies) in Stage 3, #4 (curve-aware reports) in Stage 6.

### Stage 0 — sever

Small, mostly deletion, and every later stage is cheaper once the compatibility constraints are gone.

- Rewrite this file. `scripts/compare-backends.R` → `scripts/compare-migration.R`: same discipline, new anchor.
- Drop the two upstream identities in `R/process.R` — the emitted S3 class becomes `responses.build`, and the `isCompiledBy` related identifier becomes this repo's own URL. Honest provenance, which the previous plan already listed as the right end state and only deferred for compatibility. Replace the tests that pinned them.
- Drop `austraits` from `Depends`. Vendor `convert_list_to_df2()` and `convert_df_to_list()`. Delete the deprecation shims and re-exports for `convert_list_to_df1`, `bind_databases`, `flatten_database` and `build_combine` — they exist for upstream users this fork does not have. This also removes the reversed `responses.build → austraits` package-graph edge.
- Keep a merge function: `ausfizz` + `ausfizz-private` need it. **Fix its licence bug while vendoring** — upstream does `metadata <- databases[[1]][["metadata"]]`, so merging public+restricted silently stamps the result CC‑BY‑4.0 while it holds all-rights-reserved data. The vendored version must refuse to merge differing licences without an explicit argument, and stamp the most restrictive.

### Stage 1 — naming and vocabulary

- New `config/variables.yml` in AusFizz, holding all 34 current definitions.
- `config/traits.yml` starts empty, keeps its meaning — one value per entity.
- `config/Index.xlsx` is retired: it documents variable syntax in a binary file that cannot be diffed, reviewed or read by the build. Fold into `variables.yml` and delete — which also drops it from the manual four-file `cp` sync with `ausfizz-private`.
- New `config/instruments/*.yml` — canonical export columns per instrument (`Photo → A`, `Cond → gsw`, `PARi → Qin`, …) plus observed aliases. 3–7 aliases per variable, so this resolves the large majority of the 369 mappings.
- New `config/data_types/*.yml` — expected variables and the driver, per `data_type`.

### Stage 2 — emit `curves` and `curve_points` from the *existing* metadata

Before touching a single `metadata.yml`. This proves the model against all 30 datasets while the inputs are still known-good, and produces the reference output Stage 3's migration must reproduce.

```
curves        dataset_id, curve_id, data_type, driver, driver_value,
              taxon_name, individual_id, observation_id, collection_date,
              location_id, treatment_id, entity_context_id, method_id,
              instrument, n_points
curve_points  dataset_id, curve_id, point_id, <one column per variable>
```

- `curve_id` ← `(dataset_id, observation_id, method_context_id)`, sequential within dataset.
- `point_id` ← `repeat_measurements_id`; where absent, row order within the curve. **Set `repeat_measurements_id: yes` for the 10 datasets that omit it** — without an ordering a curve is a bag of points and `A` cannot be paired with `Ci`.
- `data_type` ← lifted from the `data_type` method_context (present in 30 of 31 datasets).
- `driver` ← per `data_type`: `ACi → Ci`, `AQ → Qin`, `ACi-T → (leaf_temperature_setpoint, Ci)`, `PV curve → PSIleaf`, `stem hydraulic vulnerability → PSIstem`; `Rd`/`Amax`/`survey` → none.
- **A single-point observation is a curve with `n_points = 1` and no driver.** This is the common case (22,673 of 25,547) and must not be a special path.

### Stage 3 — metadata schema v2, and migrate all 30

`traits:` is replaced by `measurements:` — one block per data file, which is what makes multi-data-type studies dissolve rather than get patched.

- `methods` moves from per-trait to per-`measurements` block: 369 lines → ~34.
- The 12 constants become `dataset:` fields with controlled vocabularies in the schema (2–9 distinct values each, so each vocabulary is small and enumerable). Roughly 100 unqualified `custom_R_code` call sites disappear, which Stage 5 depends on.
- `contexts:` keeps only genuine contexts — things that vary within a dataset and are not treatments.
- One migration script, `scripts/migrate-metadata-v2.R`, run once, output committed. Datasets it cannot handle it leaves alone and reports.
- Fix `collection_date` here. The parser cannot distinguish `3/12/2010` from `12/3/2010`, so **confirm each dataset's convention against its source before converting** — do not let the migration guess.

### Stage 4 — treatments as numbers

Each treatment level carries named, united, numeric factors, defined in `config/treatment_factors.yml` so a factor means the same thing in every study. `experimental_manipulation` becomes derived, not authored. Where a study reports a qualitative level and no number, `factors` is absent and `label` carries it — **do not invent numbers**.

### Stage 5 — targets

- `build_setup_pipeline()` emits `_targets.R`. Delete the three whisker templates; drop `remake` and `furrr`.
- **Give `custom_R_code` an explicit evaluation environment** before anything else here (see the invariant below).
- Then move `dplyr`, `lubridate`, `readr`, `stringr`, `tidyr` from `Depends` to `Imports`.

### Stage 6 — curve-aware reports

Rewrite `inst/support/report_dataset.Rmd` against `curves` / `curve_points`: the curves themselves, per-curve point counts and driver ranges, within-study outlier flagging, coverage tiles. Drive it from a small config so adding a panel is not a package change.

### Stage 7 — repo structure and docs

The build-and-reshape half of `ausfizz/scripts/AusFizz_demo.qmd` becomes a vignette here; the exploration half stays in AusFizz. Make the `ausfizz-private` config sync enforced rather than documented. Stub `export_traits_dataset()` so the AusTraits handoff is visible before curve fitting exists.

## Invariant: the migration must not change `curves` or `curve_points`

This replaces the retired backend-parity invariant, and it is the same discipline against a new anchor.

Stage 2 emits the curve tables from the *current* metadata. Stage 3 rewrites all 30 `metadata.yml` files. The migration re-expresses the same facts in a shorter form — so if `curves` or `curve_points` moves, the migration is wrong. Reproduce with `scripts/compare-migration.R`.

Expected metadata after migration: roughly 2,500–3,000 lines, from 8,872. That number is the payoff; the invariant is what makes it safe to collect.

## Invariant: `custom_R_code` resolves through the search path

`DESCRIPTION` has `dplyr`, `lubridate`, `readr`, `stringr` and `tidyr` in **`Depends`**, so they are *attached* when the package loads. That is currently load-bearing. Datasets carry `custom_R_code` snippets in their `metadata.yml`, which the build evaluates with `eval(parse(text = ...), new.env())` in `process_custom_code()` (`R/process.R`). `new.env()` chains to the **search path**, so those snippets resolve unqualified names — `mutate()`, `filter()`, `str_detect()` — through whatever is attached.

AusFizz has ~100 such call sites. **Moving those five to `Imports` breaks them**, and it is also why targets workers are a hazard today.

Upstream cannot fix this cheaply: `austraits.build` (970 call sites) and `ausinvertraits.build` (170) are bound by the same contract. **This fork serves only AusFizz**, and Stage 3 removes most of its call sites — so the blocker does not apply here. Order matters: explicit eval environment first, rebuild AusFizz and diff, *then* `Depends` → `Imports`, and diff again.

## Open — curve fitting and the AusTraits handoff

Not started, and deliberately after Stage 7. Once curves are addressable, fitting them (Vcmax25, Jmax25, Amax, P50, TLP) populates `traits`, and `export_traits_dataset()` writes that out for `austraits.build` to ingest. Nothing before Stage 2 should assume a particular fitting library.

## Inherited debt, deliberately not fixed

- 80 lintr findings remain: 55 `line_length`, 9 `return_linter`, 8 `object_name`, 8 `object_usage`. `types` in `R/setup.R:646` is a false positive — it is used at line 663. Fix opportunistically as files are rewritten by the stages above, not as a sweep.
- `ontology/` is carried over verbatim and still describes the `traits.build` ontology, published under w3id. It is not ours to rename. With full divergence this now needs its own decision — either a `responses.build` ontology covering `variables` / `curves` / `traits`, or an explicit statement that we reference upstream's. Do it in Stage 7.
- `NEWS.md` keeps upstream's history below a fork marker, for provenance.
- No hex logo: upstream's was removed as `traits.build` branding.
- `tests/testthat/config/testgit.zip` must be force-added (`git add -f`) — `.gitignore` has `*.zip`, and the test suite unzips it to create the `.git` fixture `util_get_SHA()` needs.
