# Uncertainty Analysis

Uncertainty and sensitivity analysis of crop model outputs, including local/global sensitivity, variance decomposition, and CSV-driven design points integrated with model templates.


## Repository structure:

<!--not set in stone!-->

```
├── README.md
├── examples/        one directory per analysis: config, site table, template
├── R
│   ├── global_sensitivity.R
│   ├── local_sensitivity.R
│   └── variance_decomposition.R
├── analysis/
│   ├── global_sensitivity.qmd
│   ├── local_sensitivity.qmd
│   └── variance_decomposition.qmd
├── data_raw/   
│   ├── sa_design_points.csv
│   └── template.xml
├── scripts/
│   ├── 001_setup_design_points.R
│   ├── 011_run_local_sensitivity.R
│   ├── 012_aggregate_sensitivity.R
│   ├── 021_generate_sobol_design.R
│   ├── 022_run_global_sensitivity.R
│   ├── 023_compute_sobol_indices.R
│   ├── 031_partition_variance.R
│   └── 032_hierarchical_variance.R
├── docs/
├── tests/
└── reports/
    └── uncertainty_analysis.qmd
```

note: `data_raw` is for data of limited size (<MB) that is input to the pipeline; small outputs from these workflows can go in 'data/' but most inputs and outputs will go in one of the outdirs listed in config.yml

## Configuration

- Configuration lives in `examples/<analysis>/config.yml` and is read with
  `config::get(file = ...)`, passed to every script as `-c`. One directory per
  analysis, so adding a statewide pass means adding `examples/statewide/`
  rather than branching the scripts.
- `config.yml` carries only what is not already in the PEcAn settings: where the
  input package is, which binary, where the run tree goes. Everything the model
  reads stays in that example's `template.xml`, which is the record of what the
  pass ran.
- `data_raw/template.xml` is the original placeholder from the workflows
  repository and has no sensitivity blocks; `examples/calval/template.xml` is
  the one this analysis uses.

## Cal/val OAT sensitivity analysis

One-at-a-time parameter sensitivity at the cal/val sites: 25 runs over 7 sites,
one run per site and treatment, each with a plant and a soil PFT.

```sh
export UNCERTAINTY_DATA_ROOT=/path/to/artifacts
Rscript scripts/010_build_settings.R -c examples/calval/config.yml
Rscript scripts/020_run_sa.R         -c examples/calval/config.yml
Rscript scripts/030_aggregate.R      -c examples/calval/config.yml
```

Each analysis is a directory under `examples/` holding its own `config.yml`,
`sites.csv` and `template.xml`; `R/` and `scripts/` are generic and take the
config with `-c`. The template is per example on purpose: it is the record of
what a pass actually ran, including the SIPNET revision and the model options.

The repository holds configuration only. Input packages, model binaries and run
trees live under one directory named by `UNCERTAINTY_DATA_ROOT`, and the example
config carries paths relative to it, so no absolute path is committed. An unset
root is an error rather than a path relative to the working directory.

The cal/val input package is published at `s3://carb/calval_sa_inputs/v1.0`;
unpack it under that root. Every path in `sites.csv` resolves against
`input_root` in turn.

### The run table contract

`build_settings()` requires five columns and nothing else:

```
id, lat, lon, veg_pft, soil_pft
```

Everything else is optional and has a fallback, so one function serves passes
with different shapes:

| column | when absent |
|---|---|
| `run_start`, `run_end` | the `window` argument, one period for all runs |
| `met_src`, `ic_src`, `events_src` | derived per run from the `dirs` glue templates |

Any further column is carried into `run$site` untouched, which is how the
cal/val table keeps `site` and `treatment` for grouping in the analysis without
those becoming part of this contract.

The cal/val sites need the per-row form because they do not share a run period:
modesto is 2018-2019, russell 1992-2014, salinas 2005-2011. A statewide pass
over design points would supply neither the dates nor the paths and get one
window and a path convention instead.

Ensemble members are read from the input directory rather than generated from a
count, because replication is not uniform: met has ten members at some cal/val
sites and twenty at others.

### Run identity

`id` is the run key everything downstream joins on, `<site>.<treatment>`
for cal/val and the site id for a design-point pass. Each block writes its analysis output to its own directory named by that
key, so `aggregate_sa()` recovers the block from the path rather than from an
ensemble-id lookup. The output variable and the window are read from the file
name, so two analyses of one block that differ only in their years stay
distinct rows, and a file whose window cannot be read is an error rather than a
silent merge.

PEcAn normalises partial variance within a PFT, so the shares sum to one per
PFT and to two per block. The aggregated table keeps that per-PFT share as
`partial_variance` and adds `joint_share`, which puts the plant and soil PFTs
on a common denominator.
