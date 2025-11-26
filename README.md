# Uncertainty Analysis

Uncertainty and sensitivity analysis of crop model outputs, including local/global sensitivity, variance decomposition, and CSV-driven design points integrated with model templates.

## Executing the Sensitivity Analysis

To reproduce the analysis, follow the steps below. Ensure you have the necessary R packages and PEcAn dependencies installed.

### 1. Setup

Clone the repository and navigate to the directory:

```bash
git clone https://github.com/ccmmf/uncertinity.git
cd uncertinity
```

Initialize the design points using clustering and build the XML configurations:

```bash
# Generate design points based on CSV inputs
Rscript scripts/001_setup_design_points.R

# Build the XML settings files
Rscript scripts/002_build_xml.R
```

### 2. Local Sensitivity Analysis (One-at-a-Time)

Execute the OAT runs, aggregate the results, and generate the report:

```bash
# Run the model for local sensitivity
Rscript scripts/011_run_local_sensitivity.R

# Aggregate and process the sensitivity results
Rscript scripts/012_aggregate_sensitivity.R

# Render the analysis report
quarto render analysis/local_sensitivity.qmd
```

---

### 3. Global Sensitivity Analysis (Sobol)

Generate the Sobol design, prepare inputs, run the ensemble, and compute indices:

```bash
# Generate the Sobol design matrix
Rscript scripts/021_generate_sobol_design.R

# Prepare PEcAn-specific inputs based on the design
Rscript scripts/022_prepare_pecan_inputs.R

# Run the global sensitivity ensemble
Rscript scripts/023_run_global_sensitivity.R

# Compute Sobol indices (First and Total order)
Rscript scripts/024_compute_sobol_indices.R

# Render the global sensitivity report
quarto render analysis/global_sensitivity.qmd
```

---

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
|   ├── 002_build_xml.R
│   ├── 011_run_local_sensitivity.R
│   ├── 012_aggregate_sensitivity.R
│   ├── 021_generate_sobol_design.R
|   ├── 022_prepare_pecan_inputs.R
│   ├── 023_run_global_sensitivity.R
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
