# responses.build — agent & contributor guide

`responses.build` is an R package providing a **workflow to harmonise physiological response-curve
data** — leaf gas exchange, hydraulic vulnerability, fluorescence — into a documented, relational
standard structure. It is a **fork of [`traits.build`](https://github.com/traitecoevo/traits.build)**
(itself spun out of AusTraits in 2023; Wenk et al. 2024, doi:10.1016/j.ecoinf.2024.102773), created
because response curves do not fit the one-value-per-entity assumption and were being encoded inside
the `contexts` block instead. It exists to serve [AusFizz](https://github.com/traitecoevo/AusFizz).

**Read [`PLAN.md`](PLAN.md) before changing anything.** It records the fork point, what has been
decided, and the compatibility constraints below.

### Fork relationship — two things you must not "tidy up"

The response-curve data model is **not implemented yet**. As of the initial commit this package is
`traits.build` with only its own identity changed, and a database built with either engine is
identical apart from the version stamp and `build_info$session_info`. Keep it that way until a
change is deliberate.

Two pieces of upstream identity are kept on purpose, because `austraits` depends on both:

- Built databases carry the S3 class `traits.build` (`R/process.R`), because `austraits` dispatches
  on it (`print.traits.build`).
- Built databases carry `https://github.com/traitecoevo/traits.build` as the `isCompiledBy` related
  identifier (`R/process.R`). `austraits:::get_compiled_by_traits.build()` **string-matches that
  exact URL** to decide whether a database is readable; if it matches nothing,
  `check_compatibility()` returns `FALSE` and every austraits accessor refuses to run. It is a
  compatibility handshake, not a provenance claim.

Both are pinned by tests. Changing either requires a coordinated change in `austraits` first.

## Repo-local guidance

- **Code:** `R/` (functions), `tests/` (testthat), `man/` (generated docs), `NAMESPACE`.
- **Data-model ontology:** `ontology/` documents the ontology of the *data model*
  (entities/relations). This is **not** APD's trait-definition vocabulary — they're parallel, don't
  conflate them (see family context below).
- **Schema:** `inst/support/responses.build_schema.yml`. It is currently a verbatim copy of
  `traits.build`'s schema — that package remains the source of truth for the shared structure, and
  this repo owns only the response-curve extensions to it (none yet).
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

Across the three database repos that is **~1,240 unqualified call sites in 601 datasets**:

| Repo | Datasets | Unqualified calls |
|---|---|---|
| `austraits.build` | 411 | 970 |
| `ausinvertraits.build` | 160 | 170 |
| `AusFizz` | 30 | 100 |

**Moving those five to `Imports` breaks all of them**, at build time, in repos whose tests do not run
here. CRAN treats a heavy `Depends` as a style smell rather than a blocker, so there is no deadline
forcing the change.

What is safe: adding to `Imports`, and removing entries that are genuinely unused — `base` (a no-op)
and `forcats` (referenced nowhere) came out this way. What is not safe: moving any of the tidyverse
five out of `Depends` without first making the `custom_R_code` environment explicit, i.e. having
`process_custom_code()` populate its evaluation environment from the namespaces user code is entitled
to use instead of relying on what happens to be attached. Do that and `Depends` → `Imports` becomes
safe, and `custom_R_code` starts behaving identically under `library()`, `responses.build::`, `Rscript`
and `targets` workers — which it does not today. traitecoevo/traits.build#225 sketches the fix; it is not done.

Any change here wants the downstream gate: build all three repos before and after, and diff the
output. Nothing in this repo's own suite will catch it.

> Separately: `austraits` is also in `Depends`, for a few re-exported conversion helpers, so the
> package graph runs `responses.build → austraits` even though in the *data* pipeline responses.build is
> upstream of austraits. That edge is a known wart with a plan attached (traitecoevo/traits.build#225 Option A); it is not
> the contract above, and moving `austraits` to `Suggests` does not endanger `custom_R_code`, since
> no downstream snippet calls it unqualified. Run this package's tests after touching those helpers.

---

## AusTraits family — cross-package context

`responses.build` is part of the **AusTraits family** (a subset of the
[`traitecoevo`](https://github.com/traitecoevo) org) — here, a fork of the generic workflow engine,
specialised for response-curve data and paired with the `AusFizz` compilation. Family-wide concerns
are documented centrally in
**[austraits-meta](https://github.com/traitecoevo/austraits-meta)** — don't restate them here, read
them there:

- **Start with [`AGENTS.md`](https://github.com/traitecoevo/austraits-meta/blob/main/AGENTS.md)** —
  pipeline order, who owns what, dependency direction (incl. the reversed `responses.build → austraits`
  edge), source-of-truth rules, cross-boundary artifacts, gotchas.
- **[`dependencies.yml`](https://github.com/traitecoevo/austraits-meta/blob/main/dependencies.yml)** —
  machine-readable package graph + cross-boundary artifacts.
- **[`governance/`](https://github.com/traitecoevo/austraits-meta/tree/main/governance)** —
  label taxonomy, board #9 conventions, release playbooks, triage.

**Filing issues:** this repo tracks to its own board,
[AusFizz #19](https://github.com/orgs/traitecoevo/projects/19), shared with `AusFizz` and
`ausfizz-private` (new issues auto-add to it) — *not* the family-wide
[AusTraits #9](https://github.com/orgs/traitecoevo/projects/9). Board #19 mirrors #9's field
conventions (Status, Priority, Area) and this repo's labels are identical to `traits.build`'s.
Follow the [issue & labelling guide](https://github.com/traitecoevo/austraits-meta/blob/main/governance/issue-guide.md):
pick one work-type label (`bug` / `task` / `epic`); Status, Priority and Area are set on the board,
not as labels.

**Commit messages:** every family repo squash-merges, so the **PR title and body become the permanent
commit message**. Keep the subject ≤50 characters as typed and the body ≤10 lines; put the working
detail — what you tried, benchmarks, test counts, rejected alternatives — in the **first PR comment**
instead. Full convention:
[`commit-messages.md`](https://github.com/traitecoevo/austraits-meta/blob/master/governance/commit-messages.md).

> austraits-meta is hand-maintained prose — a map, not ground truth. Verify specifics against the
> actual repos.
