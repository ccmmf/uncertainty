# Uncertainty Analysis

Uncertainty and sensitivity analysis of crop model outputs, including local/global sensitivity, variance decomposition, and CSV-driven design points integrated with model templates.
Three-phase pipeline: local SA, global SA, and variance decomposition.

## Quick Start

```bash
# full pipeline (each step has skip-if-exists guards)
bash scripts/run_pipeline.sh

# or run phases individually
bash scripts/run_local_sa.sh
bash scripts/run_global_sa.sh
Rscript scripts/031_partition_variance.R
```

## Pipeline Structure

### Phase 0: Setup

| Script | Description |
|--------|-------------|
| `001_setup_design_points.R` | Sample design points |
| `002_build_xml.R` | Build multisite PEcAn settings XML |

### Phase 1: Local Sensitivity (OAT)

| Script | Description |
|--------|-------------|
| `011_run_local_sensitivity.R` | Run OAT perturbations |
| `012_aggregate_sensitivity.R` | Aggregate elasticities across sites |

### Phase 2: Global Sensitivity (Sobol)

| Script | Description |
|--------|-------------|
| `021_generate_sobol_design.R` | Generate Saltelli quasi-random design matrix |
| `022_prepare_pecan_inputs.R` | Convert design to PEcAn samples.Rdata |
| `023_generate_management_events.R` | Build per-sample events from baseline + quantiles |
| `024_run_global_sensitivity.R` | Run N*(k+2) model evaluations via PEcAn |
| `025_compute_sobol_indices.R` | Compute first/total-order Sobol indices |

### Phase 3: Variance Decomposition

| Script | Description |
|--------|-------------|
| `031_partition_variance.R` | Partition variance by source category |

## Repository Structure

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
|   ├── 002_build_xml.R
│   ├── 011_run_local_sensitivity.R
│   ├── 012_aggregate_sensitivity.R
│   ├── 021_generate_sobol_design.R
|   ├── 022_prepare_pecan_inputs.R
│   ├── 023_generate_management_events.R
│   ├── 024_run_global_sensitivity.R
│   ├── 025_compute_sobol_indices.R
│   ├── 031_partition_variance.R
│   └── 032_hierarchical_variance.R
├── docs/
├── tests/
└── reports/
    └── uncertainty_analysis.qmd
```

## Configuration

- Configuration in `000-config.yml`, read with `config::get(file = "000-config.yml")`
- PEcAn settings template in `data_raw/template.xml`; `002_build_xml.R` populates paths at config time via `setEnsemblePaths()`
- Management events loaded from GitHub (`ccmmf/scenarios`) by default; override with `events_baseline_url` in config
