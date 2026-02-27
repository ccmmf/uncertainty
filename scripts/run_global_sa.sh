#!/bin/bash
set -euo pipefail
# Global sensitivity analysis pipeline.
# Generates Sobol quasi-random design, prepares PEcAn inputs,
# builds management events, runs N*(k+2) model evaluations,
# and computes Sobol first/total-order indices.
#
# Usage:
#   bash scripts/run_global_sa.sh
#   bash scripts/run_global_sa.sh --config path/to/config.yml
#   bash scripts/run_global_sa.sh --sample-size 512

CONFIG="${1:---config 000-config.yml}"

echo "--- Global sensitivity analysis ---"
echo "Started: $(date)"

echo "[1/5] Generating Sobol design matrix..."
Rscript scripts/021_generate_sobol_design.R ${CONFIG}

echo "[2/5] Preparing PEcAn input objects..."
Rscript scripts/022_prepare_pecan_inputs.R ${CONFIG}

echo "[3/5] Generating per-sample management events..."
Rscript scripts/023_generate_management_events.R ${CONFIG}

echo "[4/5] Running global SA workflow (CONFIG -> EVENTS -> MODEL -> OUTPUT)..."
Rscript scripts/024_run_global_sensitivity.R ${CONFIG}

echo "[5/5] Computing Sobol indices..."
Rscript scripts/025_compute_sobol_indices.R ${CONFIG}

echo "--- Global SA complete: $(date) ---"
echo "Outputs: data/sobol_design_matrix.csv, data/sobol_indices.csv"
