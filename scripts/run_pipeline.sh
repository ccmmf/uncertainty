#!/bin/bash
set -euo pipefail

#$ -o _logs/
#$ -j y

# Full uncertainty quantification pipeline
# Phase 1: Local SA  -- OAT elasticities (001-012)
# Phase 2: Global SA -- Sobol indices    (021-025)
# Phase 3: Integration -- Variance decomposition (031)

CONFIG="${1:-000-config.yml}"
LOGFILE="_logs/pipeline_$(date +%Y%m%d_%H%M%S).log"

mkdir -p _logs

module load R

echo "--- Uncertainty quantification pipeline ---"
echo "Config: $CONFIG"
echo "Started: $(date)"
echo "Log: $LOGFILE"

{
  echo "Phase 1: local sensitivity analysis"
  bash scripts/run_local_sa.sh "$CONFIG"

  # preserve local SA output before global SA overwrites it
  if [ -d output ]; then
    echo "Archiving local SA output -> output_local_sa/"
    mv output output_local_sa
  fi

  echo "Phase 2: global sensitivity analysis"
  bash scripts/run_global_sa.sh "$CONFIG"

  echo "Phase 3: variance decomposition"
  Rscript scripts/031_partition_variance.R --config "$CONFIG"

  echo "--- Pipeline complete: $(date) ---"
  echo "Key outputs:"
  echo "  output_local_sa/   - Local OAT run output"
  echo "  output/            - Global SA run output"
  echo "  data/sobol_indices.csv"
  echo "  data/variance_partition_site_level.csv"
} 2>&1 | tee "$LOGFILE"
