# Uncertainty Analysis

Uncertainty and sensitivity analysis of crop model outputs, including local/global sensitivity, variance decomposition, and CSV-driven design points integrated with model templates.


## Repository structure:

<!--not set in stone!-->

```
├── README.md
├── 000-config.yml
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

Trying something new:
- putting configuration in `000-config.yml` and reading with `config::get(file = "000-config.yml")`.
- Added PEcAn settings template (`template.xml`) is a placeholder from the workflows repository; needs sensitivity blocks added. config.yml should not duplicate content of the pecan.xml 
