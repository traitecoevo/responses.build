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

**Consequence:** `dataset_report()` is out of service until Stage 6. Its template is written against
the `austraits` reader, whose accessors now reject databases built here. It errors with an
explanation; three tests in `test-setup.R` are skipped naming Stage 6.

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

**Test fixtures:** the nine `tests/testthat/examples/Test_2023_*` datasets are golden-file
regression tests covering the whole output structure. Never hand-edit an expected file towards the
output you observed — run `Rscript regenerate-examples.R` from `tests/testthat/` and read the diff.
Every diff is either a fix you meant to make or a regression.

### `Depends` is a contract, not an oversight — read this before editing `DESCRIPTION`

This is the easiest way to break every downstream database, and it looks exactly like tidying up.

`DESCRIPTION` has `dplyr`, `lubridate`, `readr`, `stringr` and `tidyr` in **`Depends`**, so they are
*attached* when responses.build loads. That is load-bearing. Datasets carry `custom_R_code` snippets in
their `metadata.yml`, which the build evaluates with `eval(parse(text = ...), new.env())` in
`process_custom_code()` (`R/process.R`). `new.env()` chains to the **search path**, so those snippets
resolve unqualified names — `mutate()`, `filter()`, `str_detect()` — through whatever is attached.

**This fork serves only AusFizz**, which has ~100 such call sites. Upstream cannot move these five
because `austraits.build` (411 datasets, 970 unqualified calls) and `ausinvertraits.build` (160, 170)
are bound by the same contract — but those repos build with `traits.build`, not with this package, so
that blocker does not apply here.

**Moving the five to `Imports` still breaks AusFizz today.** `PLAN.md` Stage 3 removes most of its
call sites by demoting the 12 dataset-level constants out of `custom_R_code`; Stage 5 then fixes
`process_custom_code()` to populate its evaluation environment explicitly, and only then moves them.
Order matters, and each step wants the gate: rebuild AusFizz, diff the output. Nothing in this repo's
own suite will catch a regression here.

Until Stage 5, `custom_R_code` behaves differently under `library()`, `responses.build::`, `Rscript`
and `targets` workers — which is also why Stage 5 has to do the environment fix before switching the
pipeline to targets.

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
