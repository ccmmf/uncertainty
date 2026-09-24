# Cal/val OAT sensitivity analysis

One-at-a-time parameter sensitivity at the cal/val sites: 25 runs over 7 sites,
one per site and treatment, each with a plant and a soil PFT.

```sh
export UNCERTAINTY_DATA_ROOT=/path/to/artifacts
Rscript scripts/010_build_settings.R -c examples/calval/config.yml
Rscript scripts/020_run_sa.R         -c examples/calval/config.yml
Rscript scripts/030_aggregate.R      -c examples/calval/config.yml
```

| file | what it is |
|---|---|
| `config.yml` | input package, binary, workspace, ensemble size |
| `sites.csv` | one row per run: id, location, PFT pair, window, input directories |
| `template.xml` | whole-run PEcAn settings, expanded per run by `010_build_settings.R` |

## Inputs

Model inputs come from one package, published at
`s3://carb/calval_sa_inputs/v1.0`. Unpack it under `UNCERTAINTY_DATA_ROOT`.
Paths in `config.yml` are relative to that root so no absolute path is
committed, and an unset root is an error rather than a path relative to the
working directory.

## Why the run table carries a window

The cal/val sites do not share a run period: modesto is 2018-2019, russell
1992-2014, salinas 2005-2011. `run_start` and `run_end` are therefore per row,
and the dates, the sensitivity window, the PFT pair and the inputs are set on
each run rather than once for the whole matrix.

`id` is `<site>.<treatment>` and is the run key. Each run writes its analysis
output to a directory named by it, so the aggregation recovers the run from the
path rather than from an ensemble id lookup.
