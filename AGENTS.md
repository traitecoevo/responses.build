# responses.build — agent & contributor guide

`responses.build` is an R package providing a **workflow to harmonise physiological response-curve
data** — leaf gas exchange, hydraulic vulnerability, fluorescence — into a documented, relational
standard structure. It is a **fork of [`traits.build`](https://github.com/traitecoevo/traits.build)**
(itself spun out of AusTraits in 2023; Wenk et al. 2024, doi:10.1016/j.ecoinf.2024.102773), created
because response curves do not fit the one-value-per-entity assumption and were being encoded inside
the `contexts` block instead. It exists to serve [AusFizz](https://github.com/traitecoevo/ausfizz).

**Read [`PLAN.md`](PLAN.md) before changing anything.** It records the fork point, the seven stages
that implement the response-curve model, and the invariants below.

### Terminology — three levels, and they are not interchangeable

```
variables      raw per-point readings              A, Ci, gsw, Tleaf, Qin, PSIstem, f0
curves         the curve as an addressable object
traits         derived parameters, one per entity  Amax, Vcmax25, Jmax25, P50, TLP
```

The upstream data model called the first row "traits", which is why the AusFizz `traits` table needs
584,338 rows to hold what `curve_points` holds in 50,506. `traits` is reserved here for the third row
— the parameters fitted from curves, which are what eventually reaches AusTraits.

**Naming rule, everywhere:** identifiers are `snake_case`, carry no units, spaces or brackets, and
units live in a `unit` field beside the value.

### How a dataset says what it measured

`measurements:` — one block per data file — desugars in `dataset_configure()` into the `traits:` list
the rest of the build understands (`R/measurements.R`). Order matters inside that expansion:
instrument profile → `column_suffix` → `use` → `variables_extra`. The first two describe the
*profile*; extras are written out in full and must come last, or `use` silently filters them away.

### The curve tables

`curves` and `curve_points` are the point of this package. A curve is identified by
`(dataset_id, observation_id, method_context_id)`; its points are ordered by `repeat_measurements_id`.

Two things that look like tidying up and are not:

- **`method_id` is deliberately absent from `curves`.** It belongs to a (curve, variable) pair, not to
  the curve. Adding it to the key splits curves that should stay whole — measured: 75 of them, and in
  `Ghannoum_2010` it fragments a complete eight-variable curve because `Tleaf` alone was measured twice.
- **`link_vals` in the contexts table is a comma-separated list of ids**, not one id. Any join against
  it must split first, or it silently matches nothing.

`n_points` is character, like every other column of every other table here, so `write_plaintext()` and
`read_csv_char()` round-trip.

### The fork is a real fork

The curve model is in the built object as of Stage 2; `PLAN.md` Stage 3 onwards rewrites the AusFizz
metadata against it. This package no longer tracks upstream, and the `austraits` linkage is severed:

- Built databases carry the S3 class `responses.build` and record
  `https://github.com/traitecoevo/responses.build` as the `isCompiledBy` related identifier. Both
  previously reported upstream's values so that `austraits::check_compatibility()` — which
  string-matches that exact URL — would accept the output. Both are pinned by tests.
- `austraits` is not a dependency. `convert_list_to_df1()`, `convert_list_to_df2()`,
  `convert_df_to_list()` and `bind_databases()` are defined here.
- The AusTraits pipeline is still the point of this repository, but as a **data handoff** — derived
  traits written out for `austraits.build` to ingest — not a runtime dependency.

**The dataset report** (`inst/support/report_dataset.Rmd`) is built on the 2026 template from
`traits.build`'s `feature/add-dataset-skill` branch, with its trait sections replaced by curve ones.
When that template gains something upstream, take it from there rather than reinventing it — but its
`Trait measurements` section is the wrong question for this data and should stay replaced.

**`bind_databases()` refuses to guess a licence.** Upstream kept the first argument's metadata and
dropped the rest, so merging `ausfizz` with `ausfizz-private` stamped the result CC-BY-4.0 while it
held all-rights-reserved data, decided by argument order. Pass `rights` when the inputs disagree.

## Repo-local guidance

- **Code:** `R/` (functions), `tests/` (testthat), `man/` (generated docs), `NAMESPACE`.
- **Data-model ontology:** `ontology/` documents the ontology of the *data model*
  (entities/relations). This is **not** APD's trait-definition vocabulary — they're parallel, don't
  conflate them (see family context below).
- **Schema:** `inst/support/responses.build_schema.yml`. Still a verbatim copy of `traits.build`'s
  schema, but no longer for compatibility reasons — the response-curve extensions simply have not
  been made yet. `PLAN.md` Stages 1–4 change it, and this repo owns it outright.
- **Docs:** user manual at the [traits.build-book](https://traitecoevo.github.io/traits.build-book/);
  function reference at <http://traitecoevo.github.io/responses.build/>.

Dev follows the standard R-package workflow: `devtools::load_all()`, `devtools::test()`,
`devtools::check()`. Default development branch is `develop`.

**Building a compilation:** `build_setup_pipeline()` writes `_targets.R`; `targets::tar_make()`
runs it. `method = "base"` writes a dependency-free linear `build.R`, kept for debugging, and the
suite asserts the two agree. `remake` and `furrr` are gone.

**Test fixtures:** the nine `tests/testthat/examples/Test_2023_*` datasets are golden-file
regression tests covering the whole output structure. Never hand-edit an expected file towards the
output you observed — run `Rscript regenerate-examples.R` from `tests/testthat/` and read the diff.
Every diff is either a fix you meant to make or a regression.

### `custom_R_code` and the evaluation environment

Datasets carry `custom_R_code` snippets in their `metadata.yml`, evaluated by
`process_custom_code()` (`R/process.R`). Those snippets write `mutate()`, `filter()`,
`str_detect()` unqualified.

They used to resolve through the **search path**, which is why `dplyr`, `lubridate`, `readr`,
`stringr` and `tidyr` were in `Depends`: the build worked only because loading the package attached
them. The same snippet then behaved differently under `library()`, `responses.build::`, `Rscript`
and a `targets` worker.

The environment is now built explicitly — `util_custom_code_env()` in `R/utils.R` — as a chain of
one environment per package ending at `baseenv()`. **It must never reach `globalenv()`**; a test
asserts that, because if it does, resolution is back to depending on what a session happens to have
attached. Adding a package a snippet may use means adding it to `CUSTOM_CODE_PACKAGES`, not
attaching it somewhere.

`data` is **bound** into that environment. It used to be reachable only because the environment's
parent was the frame holding the argument.

The five tidyverse packages are in `Imports` now. Anything that relied on this package attaching
them — including this repo's own tests — needs its own `library()` call.

---

## AusTraits family — cross-package context

`responses.build` is part of the **AusTraits family** (a subset of the
[`traitecoevo`](https://github.com/traitecoevo) org) — here, a fork of the generic workflow engine,
specialised for response-curve data and paired with the `AusFizz` compilation. Family-wide concerns
are documented centrally in
**[austraits-meta](https://github.com/traitecoevo/austraits-meta)** — don't restate them here, read
them there:

- **Start with [`AGENTS.md`](https://github.com/traitecoevo/austraits-meta/blob/main/AGENTS.md)** —
  pipeline order, who owns what, dependency direction, source-of-truth rules, cross-boundary
  artifacts, gotchas. Note that it still records a reversed `responses.build → austraits` package
  edge; that edge was removed here — see "The fork is a real fork" above.
- **[`dependencies.yml`](https://github.com/traitecoevo/austraits-meta/blob/main/dependencies.yml)** —
  machine-readable package graph + cross-boundary artifacts.
- **[`governance/`](https://github.com/traitecoevo/austraits-meta/tree/main/governance)** —
  label taxonomy, board #9 conventions, release playbooks, triage.

### Filing issues: **file them here**, even when they are about the data

**This repo is the issue tracker for the whole AusFizz effort** — the engine, the `ausfizz`
compilation, and `ausfizz-private`. File data issues here too, and label them.

The reason is mechanical, not editorial. `ausfizz` and `ausfizz-private` are private, and Actions
are blocked on private repos across the `traitecoevo` org (free plan, allowance exhausted), so
their own `add-to-project` hooks cannot run and issues filed there never reach the board. This repo
is **public**, where Actions are unmetered, so filing here works and costs nothing. Their hooks are
left in place and will start working on their own if private-repo billing is ever restored.

Issues auto-add to [AusFizz #19](https://github.com/orgs/traitecoevo/projects/19) — *not* the
family-wide [AusTraits #9](https://github.com/orgs/traitecoevo/projects/9). Board #19 mirrors #9's
field conventions (Status, Priority, Area) and this repo's labels are identical to
`traits.build`'s. Follow the
[issue & labelling guide](https://github.com/traitecoevo/austraits-meta/blob/main/governance/issue-guide.md):
pick one work-type label (`bug` / `task` / `epic`); Status, Priority and Area are set on the board,
not as labels. Use `Area: data` on the board to separate compilation issues from engine ones.

**This repo is public.** Do not paste restricted data, contributor correspondence, or anything from
`ausfizz-private` into an issue here.

**Commit messages:** every family repo squash-merges, so the **PR title and body become the permanent
commit message**. Keep the subject ≤50 characters as typed and the body ≤10 lines; put the working
detail — what you tried, benchmarks, test counts, rejected alternatives — in the **first PR comment**
instead. Full convention:
[`commit-messages.md`](https://github.com/traitecoevo/austraits-meta/blob/master/governance/commit-messages.md).

> austraits-meta is hand-maintained prose — a map, not ground truth. Verify specifics against the
> actual repos.
