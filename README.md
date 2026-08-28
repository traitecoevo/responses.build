# The {responses.build} R package

<!-- badges: start -->
[![R-CMD-check](https://github.com/traitecoevo/responses.build/actions/workflows/R-CMD-check.yml/badge.svg)](https://github.com/traitecoevo/responses.build/actions/workflows/R-CMD-check.yml)
[![Lifecycle: experimental](https://img.shields.io/badge/lifecycle-experimental-orange.svg)](https://lifecycle.r-lib.org/articles/stages.html#experimental)
<!-- badges: end -->

`responses.build` is a workflow for harmonising **physiological response-curve data** — leaf gas exchange, hydraulic vulnerability, and fluorescence response curves — from disconnected primary sources into a documented, relational structure.

It is a fork of [`traits.build`](https://github.com/traitecoevo/traits.build), which harmonises single-valued trait data. That engine assumes a measurement is *one value for one entity*. A response curve is not: it is a set of paired measurements, taken across a driver gradient, that belong together as one identifiable curve. Building [AusFizz](https://github.com/traitecoevo/ausfizz) on `traits.build` meant encoding the driver, the curve identity, and the instrument settings inside the `contexts` block — which works, but makes each dataset's metadata large, repetitive, and hard to query. `responses.build` exists to give response curves a first-class representation instead.

## Status

**Experimental, and deliberately so.** The initial commit is `traits.build` (`develop`, commit [`c2be7f9`](https://github.com/traitecoevo/traits.build/commit/c2be7f9)) with nothing changed but the package's own identity. Databases built with `responses.build` are byte-identical to those built with `traits.build`, apart from the engine version stamp — this is verified, and the check is kept as a regression test so divergence stays deliberate and visible.

The response-curve data model is not implemented yet. See [`PLAN.md`](PLAN.md) for what is decided, what is open, and the compatibility constraints any change has to respect.

## Relationship to traits.build

`responses.build` intentionally keeps `traits.build`'s public API — `dataset_configure()`, `dataset_process()`, `dataset_update_taxonomy()`, `build_setup_pipeline()`, and the rest. A database repository switches engines by changing which package it loads, and nothing else.

Two pieces of upstream identity are kept on purpose, because downstream tooling depends on them:

- Built databases carry the S3 class `traits.build`, because `austraits` dispatches on it (`print.traits.build`).
- Built databases carry the `isCompiledBy` related-identifier URL `https://github.com/traitecoevo/traits.build`, because `austraits` string-matches that URL to decide whether a database is readable at all. It is a compatibility handshake, not a provenance claim.

Both are pinned by tests. Changing either requires a coordinated change in [`austraits`](https://github.com/traitecoevo/austraits); see `PLAN.md`.

## Related repositories

| Repo | What it is |
|---|---|
| `responses.build` | This repo: the engine |
| [`AusFizz`](https://github.com/traitecoevo/ausfizz) | The compilation intended for public release, and the source of truth for shared configuration |
| [`ausfizz-private`](https://github.com/traitecoevo/ausfizz-private) | Restricted datasets that cannot be released yet, built by the same pipeline and merged on demand |

Issues for all three are tracked on the [AusFizz board (#19)](https://github.com/orgs/traitecoevo/projects/19), not the family-wide AusTraits board.

Splitting the data across two repositories is lossless: building AusFizz's datasets in two groups and binding them with `austraits::bind_databases()` reproduces every table of a single combined build exactly. The merged object keeps only one `metadata` block.

## Installation

```r
# install.packages("remotes")
remotes::install_github("traitecoevo/responses.build")
```

## Usage

Identical to `traits.build`. From the root of a database repository:

```r
library(responses.build)

build_setup_pipeline(method = "remake", database_name = "AusFizz")
AusFizz <- remake::make("AusFizz")
```

## Documentation

The data model and workflow concepts are shared with `traits.build` and are documented in the [traits.build book](https://traitecoevo.github.io/traits.build-book/). Read that first. This repository documents only where `responses.build` departs from it.

## How to cite

`responses.build` derives from the `traits.build` workflow. Until it has its own paper, please cite:

> Wenk E, Bal P, Coleman D, Gallagher R, Yang S, Falster DS (2024) **traits.build: A data model, workflow and R package for building harmonised ecological trait databases.** *Ecological Informatics* 83:102773. <https://doi.org/10.1016/j.ecoinf.2024.102773>

## AusTraits family

`responses.build` is part of the **AusTraits family** of packages maintained by the [AusTraits](https://austraits.org) team. See **[austraits.org](https://austraits.org)** for the project, the data, and the people behind it.

Cross-package knowledge and governance live in [`austraits-meta`](https://github.com/traitecoevo/austraits-meta) — start with its [`AGENTS.md`](https://github.com/traitecoevo/austraits-meta/blob/main/AGENTS.md) and the [issue & labelling guide](https://github.com/traitecoevo/austraits-meta/blob/main/governance/issue-guide.md).

## Acknowledgements

AusTraits is made possible by contributions from our partner organisations — the [University of New South Wales](https://www.unsw.edu.au/), [Western Sydney University](https://www.westernsydney.edu.au/), [Botanic Gardens of Sydney](https://www.botanicgardens.org.au/), [the University of Melbourne](https://www.unimelb.edu.au/), the [Atlas of Living Australia](https://www.ala.org.au/), and the Australian Government [Department of Climate Change, Energy, the Environment and Water](https://www.dcceew.gov.au) — and from our [advisory board, data contributors, and past partners](https://austraits.org/team/team-partners.html).

AusTraits is a co-investment partnership with the [Australian Research Data Commons](https://ardc.edu.au/) (ARDC) through the Planet Research Data Commons ([DOI: 10.3565/nyk4-4r91](https://doi.org/10.3565/nyk4-4r91)). The ARDC is enabled by the Australian Government's [National Collaborative Research Infrastructure Strategy](https://www.education.gov.au/ncris) (NCRIS).

## License

BSD 2-clause, inherited from `traits.build`. See [LICENCE](LICENCE).
