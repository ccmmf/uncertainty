# Uncertainty Analysis

Trying something new:
- putting configuration in `000-config.yml` and reading with `config::get(file = "000-config.yml")`.
- Added PEcAn settings template (`template.xml`) is a placeholder from the workflows repository; needs sensitivity blocks added. config.yml should not duplicate content of the pecan.xml 

Repository layout:
- `R/` – reusable helper functions for each workflow component.
- `scripts/` – orchestration entry points (`001`, `011`, `021`, `031` series).
- `analysis/` – Quarto notebooks for future reporting.
- `data/`, `results/` – inputs and derived outputs.

## Quickstart

1. Edit `000-config.yml` to match your environment.
2. Run `Rscript scripts/001_setup_design_points.R` to materialize `data/sa_design_points.csv`.
3. Work through the remaining scripts in numerical order as functionality lands.

See `instructions.md` for the current iteration plan and `instructions_v0.md` for the detailed long-form design.

## Repository structure:

<!--not set in stone!-->

```
├── README.md
├── 000-config.yml
├── R
│   ├── global_sensitivity.R
│   ├── local_sensitivity.R
│   └── variance_decomposition.R
├── analysis
│   ├── global_sensitivity.qmd
│   ├── local_sensitivity.qmd
│   └── variance_decomposition.qmd
├── data_raw
│   ├── sa_design_points.csv
│   └── template.xml
├── scripts
│   ├── 001_setup_design_points.R
│   ├── 011_run_local_sensitivity.R
│   ├── 012_aggregate_sensitivity.R
│   ├── 021_generate_sobol_design.R
│   ├── 022_run_global_sensitivity.R
│   ├── 023_compute_sobol_indices.R
│   ├── 031_partition_variance.R
│   └── 032_hierarchical_variance.R
├── documentation
├── tests
└── results
    └── uncertainty_analysis.qmd
```
