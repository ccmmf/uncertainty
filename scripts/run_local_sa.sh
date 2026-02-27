#!/bin/bash
set -euo pipefail
# Local sensitivity analysis pipeline.
# Runs OAT (one-at-a-time) perturbations to compute elasticities
# and partial variances for each parameter at each site.
#
# Usage:
#   bash scripts/run_local_sa.sh
#   bash scripts/run_local_sa.sh --config path/to/config.yml

CONFIG="${1:---config 000-config.yml}"

echo "--- Local sensitivity analysis ---"
echo "Started: $(date)"

echo "[1/4] Setting up design points..."
Rscript scripts/001_setup_design_points.R ${CONFIG}

echo "[2/4] Building PEcAn XML..."
Rscript scripts/002_build_xml.R

echo "[3/4] Running OAT sensitivity (CONFIG -> MODEL -> OUTPUT -> SA)..."
Rscript scripts/011_run_local_sensitivity.R

echo "[4/4] Aggregating sensitivity results..."
Rscript scripts/012_aggregate_sensitivity.R

echo "--- Local SA complete: $(date) ---"
echo "Outputs: data/aggregated_sensitivity.csv, data/parameter_rankings.csv"
