#!/bin/bash
set -euo pipefail

#$ -o _logs/
#$ -j y

# global sensitivity analysis pipeline (021 -> 025)

CONFIG="${1:-000-config.yml}"
LOGFILE="_logs/global_sa_$(date +%Y%m%d_%H%M%S).log"

mkdir -p _logs

module load R

echo "--- Global sensitivity analysis ---"
echo "Config: $CONFIG"
echo "Started: $(date)"
echo "Log: $LOGFILE"

{
  echo "[1/5] Generating sobol design matrix..."
  Rscript scripts/021_generate_sobol_design.R --config "$CONFIG"

  echo "[2/5] Preparing pecan input objects..."
  Rscript scripts/022_prepare_pecan_inputs.R --config "$CONFIG"

  echo "[3/5] Generating per-sample management events..."
  Rscript scripts/023_generate_management_events.R --config "$CONFIG"

  echo "[4/5] Running global SA workflow (CONFIG -> MODEL -> OUTPUT)..."
  Rscript scripts/024_run_global_sensitivity.R --config "$CONFIG"

  echo "[5/5] Computing sobol indices..."
  Rscript scripts/025_compute_sobol_indices.R --config "$CONFIG"

  echo "--- Global SA complete: $(date) ---"
} 2>&1 | tee "$LOGFILE"
