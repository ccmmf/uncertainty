#!/bin/bash
set -euo pipefail

#$ -o _logs/
#$ -j y

# local sensitivity analysis pipeline (001 -> 012)

CONFIG="${1:-000-config.yml}"
LOGFILE="_logs/local_sa_$(date +%Y%m%d_%H%M%S).log"

mkdir -p _logs

module load R

echo "--- Local sensitivity analysis ---"
echo "Config: $CONFIG"
echo "Started: $(date)"
echo "Log: $LOGFILE"

{
  echo "[1/4] Setting up design points..."
  Rscript scripts/001_setup_design_points.R --config "$CONFIG"

  echo "[2/4] Building PEcAn XML..."
  Rscript scripts/002_build_xml.R

  echo "[3/4] Running OAT sensitivity (CONFIG -> MODEL -> OUTPUT -> SA)..."
  Rscript scripts/011_run_local_sensitivity.R

  echo "[4/4] Aggregating sensitivity results..."
  Rscript scripts/012_aggregate_sensitivity.R

  echo "--- Local SA complete: $(date) ---"
} 2>&1 | tee "$LOGFILE"
