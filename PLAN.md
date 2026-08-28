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

### Stage 0 — sever — **done**

Small, mostly deletion, and every later stage is cheaper once the compatibility constraints are gone.

- Rewrite this file. `scripts/compare-backends.R` → `scripts/compare-migration.R`: same discipline, new anchor.
- Drop the two upstream identities in `R/process.R` — the emitted S3 class becomes `responses.build`, and the `isCompiledBy` related identifier becomes this repo's own URL. Honest provenance, which the previous plan already listed as the right end state and only deferred for compatibility. Replace the tests that pinned them.
- Drop `austraits` from `Depends`. Vendor `convert_list_to_df2()` and `convert_df_to_list()`. Delete the deprecation shims and re-exports for `convert_list_to_df1`, `bind_databases`, `flatten_database` and `build_combine` — they exist for upstream users this fork does not have. This also removes the reversed `responses.build → austraits` package-graph edge.
- Keep a merge function: `ausfizz` + `ausfizz-private` need it. **Fix its licence bug while vendoring** — upstream does `metadata <- databases[[1]][["metadata"]]`, so merging public+restricted silently stamps the result CC‑BY‑4.0 while it holds all-rights-reserved data. The vendored version must refuse to merge differing licences without an explicit argument, and stamp the most restrictive.

### Stage 1 — naming and vocabulary — **done**

- `get_definitions()` in the engine reads `config/variables.yml`, falling back to `config/traits.yml` with a message. The three build templates call it instead of `get_schema("config/traits.yml", "traits")`.
- `config/variables.yml` holds all 34 definitions, units and ranges **verbatim** from the `traits.yml` that preceded it, plus `domain` and `data_types`. Five datasets were built both ways: `traits`, `excluded_data`, `contexts`, `locations`, `methods`, `taxonomic_updates` and `taxa` all identical. The additive fields do not even reach the output — `dataset_configure()` subsets `definitions` to the fields the build uses.
- `config/traits.yml` is empty, and says why in a header rather than by absence.
- `config/Index.xlsx` retired, its content split four ways: `variables.yml`, `data_types.yml` (11 data types with driver and source URI), `vocabularies.yml` (19 controlled vocabularies), `context_properties.yml`. Recovered from git history if needed.
- `config/instruments/{licor_6400,licor_6800,lca4}.yml` derived from the corpus.
- `ausfizz-private/scripts/sync-config.R` replaces the README's `cp` line: checks by default, exits non-zero on drift, `--write` repairs. It also fails on a file present in the private repo but not AusFizz — the more dangerous direction.

**One deviation from this plan as written:** data types are a single `config/data_types.yml`, not a `config/data_types/` directory. Eleven short entries read better in one file. Instruments stayed a directory, where the per-file column maps are long.

#### An alias must be an instrument variant, not a name one dataset used

The instrument profiles promote a column name to an `alias` only if two or more datasets use it. This matters more than it sounds: one dataset maps a column called `temp` to `Tleaf`. As a global alias that would silently read *any* file's `temp` column as leaf temperature. Single-dataset names stay in that dataset's own `variables_extra` block. 23 names were held back on this rule.

#### Found in Stage 1, deliberately not fixed

These are data questions, not vocabulary questions. Each needs the source checked, so each is Stage 3 work or its own issue — the same treatment as `collection_date`.

- **`Index.xlsx` had drifted from the file the build enforces, in 16 allowed-value ranges.** `Tleaf`/`Tair` (0–100 vs −20–70), `Patm` (0–110 vs 50–120), `VPDleaf` (max 10 vs 5), `FvFm` (max 1 vs 3000), `f0` (max 5000 vs 3000), and the sign of the minimum on `CO2r`, `CO2s`, `gsw`, `Qin`, `Qout`, `RHr`. `variables.yml` keeps the enforced values, because changing them changes what lands in `excluded_data`. Neither source is uniformly right: `Tleaf` min 0 excludes sub-zero leaf temperatures, and `FvFm` max 3000 is meaningless for a ratio.
- **Three columns are declared with two different units, each a 1000× discrepancy.** `Trmmol` → `E` as both `mmol{H2O}/m2/s` (10 datasets) and `mol{H2O}/m2/s` (1); the same for the LI-6800 short-form `E`; and `gsw` as both `mol` and `mmol`. LI-COR writes `Trmmol` in mmol, so the odd ones out are likely 1000× wrong in value. Check the source files.
- **123 of 315 descriptor values do not match a controlled vocabulary**, in four groups: `unknown` was missing from vocabularies that need it (fixed here — `unknown` is data, not an error); compound values composed with `; ` (fixed here via `multiple: yes`); genuine spelling mismatches (`upper canopy` *and* `upper_canopy` in the same corpus for the same thing, neither matching ESS-DIVE's `top of canopy`; `PLC whole segment` vs `PLC wholesegment`; `early morning` vs `morning`); and a **name collision** — AusFizz's `plant_age` holds actual ages (`2 years`, `4-7 years`) in 28 of 30 datasets, while ESS-DIVE's `plantAge` is a life-stage category, and `life_stage` already exists as a dataset field. Recorded in `vocabularies.yml` next to the vocabulary each concerns.
- **AusFizz's `remake.yml` still declared `packages: traits.build`.** It had never been regenerated after the fork. Regenerated.

### Stage 2 — emit `curves` and `curve_points` from the *existing* metadata — **done**

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

#### Result, measured on the full 30-dataset build

| | |
|---|---|
| `traits` rows | 584,338 |
| `curve_points` rows | **50,506 — 11.6× smaller** |
| curves | 25,699 |
| traits values not recoverable from `curve_points` | **0** |
| curves carrying a `data_type` | 25,554 of 25,699 — closes board #1 |
| curves carrying a `driver` | 12,095 (`ACi-T` correctly nested: `Ci` over `leaf_temperature_setpoint`) |
| curves whose points cannot be paired | **0** |
| `curve_points` conflicts | **0** |

#### Three things the implementation had to get right

- **`method_id` is not part of the curve.** It is a property of a (curve, variable) pair: one curve can hold a variable measured under a different method from the rest. Putting it in the key made the key non-unique, and would have split 75 curves across two datasets — in `Ghannoum_2010` fragmenting a complete eight-variable curve into that curve plus a one-variable remnant, because `Tleaf` alone was measured twice. In `Bloomfield_2014_a` different variables use different methods, so splitting breaks the pairing outright. The key is `(dataset_id, observation_id, method_context_id)`; `method_id` is not on the curve row at all.
- **`link_vals` in the contexts table is a comma-separated *list* of ids**, not one id. Joining on the raw string silently matches nothing whenever a context value covers more than one method context — which is how `data_type` is usually recorded. Pinned by a test.
- **The `curve_points` conflict is a check, not a build warning.** Where a variable has two values at one point, only one fits the wide view (lowest `method_id` wins) and `check_curve_points_conflicts()` reports it. It is not warned at build time: for trait-style data several methods per trait is the normal case, and it fired 45 times on a single test fixture. A warning nobody can act on is one everybody learns to ignore.

#### Found in Stage 2, deliberately not fixed

- **`Drake_2017` declares no `data_type` context at all** — the only one of 30 — so its 145 curves carry none. It also uses `instrument_ID` where every other dataset uses `instrument`. Stage 3.
- **`Drake_2015` has three raw CSVs and no `metadata.yml`.** It is board issue #3 waiting to happen, and the reason `remake.yml` carries 31 targets for 32 data folders.
- **`n_points` is character**, like every other column of every other table in this data model, so a written CSV reads back as what the database held.

### Stage 3 — metadata schema v2, and migrate all 30 — **done, with one part deferred**

`traits:` is replaced by `measurements:` — one block per data file, desugared in `dataset_configure()` into the `traits:` list the rest of the build understands. A dataset names its instrument instead of restating twenty column mappings, and writes its methods paragraph once instead of once per variable.

```yaml
measurements:
- data_type: ACi-T
  instrument: Li6400 IRGA
  use: [A, gsw, Ci, VPDleaf, Tair, Tleaf, CO2r, CO2s, Qin]
  methods: |
    Each Anet-Ci response curve started with a steady-state measurement ...
  variables_extra:
  - variable: leaf_temperature_setpoint
    var_in: temp
    unit_in: C
```

`column_suffix` closes **board #3**: a study measuring two data types in one spreadsheet writes `Photo` and `Photo_survey_Amax`, and a second block says that in one line instead of duplicating nineteen mappings.

**Result: 8,872 metadata lines → 5,832 (34% smaller), 386 mappings → 38 measurement blocks, 36 methods entries → 36 written once instead of 386 times.** The gate passed strictly: every table — `traits`, `curves`, `curve_points`, `contexts`, `methods`, `excluded_data`, `locations`, `taxa`, `definitions`, `metadata` — is identical before and after.

#### Deferred: the 12 descriptors stay in `contexts:` for now

This plan said they would become `dataset:` fields, and estimated 2,500–3,000 lines. **They did not, and the honest number is 5,832.**

Measured while implementing: reversing a dataset's `contexts:` list leaves `curve_points` byte-identical and the curve-to-point grouping identical, but **permutes the integer labels of `treatment_context_id`** — 03 and 02 swap. The partition is the same; only the names of its parts move. Promoting the descriptors out of `contexts:` reorders that list, so it relabels ids.

Those labels are published output that a saved analysis may join on. A migration whose whole premise is "nothing changes" must not smuggle them, so this half is deferred rather than forced.

**The right fix is upstream of the migration: context ids should not depend on the order somebody happened to write YAML in.** `process_generate_id()` already sorts for `observation_id`; the context ids do not. That is the same class of defect as the locale-collation bug upstream already fixed — a build that depends on incidental input order. Make ids order-independent, accept the one-time relabelling deliberately and with a NEWS entry, and the descriptors can then move for free. **Its own stage, its own decision.**

#### Two bugs the gate caught, which review would not have

- **`use:` was applied after `variables_extra` was merged**, so it filtered out every variable the instrument profile did not cover. `excluded_data` fell from 14,782 rows to 1,029 and `methods` from 350 to 293. `use` and `column_suffix` describe the *profile*; extras are written out in full and come after.
- **Coverage was decided on `var_in` and `unit_in` alone**, so a mapping overriding `value_type` or `replicates` was folded into `use:` and silently took the defaults — 14 entries in `Bloomfield_2014_a` went from `mean`/5 replicates to `raw`/1. A mapping is covered only if it also takes every default.

Both were invisible in the migrated YAML and obvious in the diff of the built object. This is what the invariant is for.

#### Found in Stage 3, deliberately not fixed

- **`collection_date` is still d/m/Y in 19 of 30 datasets.** `3/12/2010` cannot be told from `12/3/2010` without the source file, so the migration reports and never converts. Needs a person with the original data; its own board issue.
- Nine datasets match no instrument profile and keep their mappings as `variables_extra`. `Krishnananthaselvan_2024` (4 methods, 25 mappings), `Drake_2017` and `Kumarathunge_2018` are the largest. Not a defect — they are hydraulic or hand-transcribed files with no shared column vocabulary to factor out.

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
