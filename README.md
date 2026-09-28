# Uncertainty

Sensitivity analyses of the SIPNET ecosystem model used in the MAGiC inventory runs:

- a local (one-at-a-time) analysis that ranks parameters by their share of the parameter
  variance of modeled soil carbon and nitrous oxide flux, and
- a global (Sobol) analysis that partitions the variance of those outputs among
  parameters, initial conditions, meteorology, and management.

Reports and training: <https://ccmmf.github.io/uncertainty/>

## Requirements

- the `pecan-all` conda environment (R, PEcAn, `yq`, `python3`)
- a SIPNET binary, such as the `sipnet.git` built by the ensemble workflow
- the inputs of a prepared ensemble run: site list, ERA5 meteorology, initial
  conditions, management events, and PFT priors

Model runs are submitted to Slurm or SGE as array jobs, or run with GNU parallel in
the current allocation, as set by `pecan_parallelism_mode` in the configuration.

## Running

Copy `example_user_config.yaml`, point `external_paths` at the ensemble run and the
SIPNET binary, then run from the repository root:

```bash
./magic-uncertainty prepare            --config config.yaml
./magic-uncertainty local-sensitivity  --config config.yaml
./magic-uncertainty global-sensitivity --config config.yaml
```

`./magic-uncertainty help` lists the commands. `--verbose` prints each script call.
Each command writes a log to `run_dir`. The
[training pages](https://ccmmf.github.io/uncertainty/docs/training/) walk through a
demo at two design points.

## Outputs

| Path in `run_dir` | Content |
|---|---|
| `local/local_sensitivity.csv` | CV, elasticity, and variance of every parameter at every design point |
| `local/figures/` | local analysis figures and `parameter_shares.csv` |
| `global/global_sensitivity.csv` | first-order and total-order indices with bootstrap intervals |
| `global/figures/` | global analysis figures and summary tables |

## Repository layout

```
magic-uncertainty            command line interface
uncertainty_manifest.yaml    steps, their inputs and outputs, and fixed settings
example_user_config.yaml     settings for one run
scripts/                     one script per step (001, 011-013, 021-023) and launchers
analysis/                    reports, their figure scripts, and figures
docs/training/               training pages
data_raw/                    settings templates and climate region boundaries
R/                           functions used by the scripts
```

## Site

The site is built with Quarto from `_quarto.yml`:

```bash
quarto render
quarto publish gh-pages
```
