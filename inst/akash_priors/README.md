# Vendored priors from `ccmmf/scenarios`

These two files are copied in unchanged from
[`ccmmf/scenarios`](https://github.com/ccmmf/scenarios) PR #3 (branch
`management_prac`):

- `sample_priors.R` — sampling helpers (`load_priors()`,
  `sample_distribution()`, `sample_practice()`, …)
- `management_priors.yaml` — distributions for CA agronomic management
  parameters

We vendor them so the calval → events.json pipeline can run without a
sibling checkout of `ccmmf/scenarios`. Once `ccmmf/scenarios` is
released as a proper R package with a `DESCRIPTION`, swap this directory
out for a `library(scenarios)` import.
