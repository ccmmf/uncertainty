#!/bin/bash
set -euo pipefail
# Full uncertainty quantification pipeline.
# Runs local SA, global SA, and variance decomposition end-to-end.
# Each sub-pipeline has skip-if-exists guards, so re-running is safe.
#
# Usage:
#   bash scripts/run_pipeline.sh
#   bash scripts/run_pipeline.sh --config path/to/config.yml
#
# Pipeline order (Dietze 2017 framework):
#   Phase 1: Local SA  -- OAT elasticities (011-012)
#   Phase 2: Global SA -- Sobol indices    (021-025)
#   Phase 3: Integration -- Variance decomposition (031)

CONFIG="${1:---config 000-config.yml}"

echo "--- Uncertainty quantification pipeline ---"
echo "  $(date)"

echo "Phase 1: Local sensitivity analysis"
bash scripts/run_local_sa.sh ${CONFIG}

echo "Phase 2: Global sensitivity analysis"
bash scripts/run_global_sa.sh ${CONFIG}

echo "Phase 3: Variance decomposition"
Rscript scripts/031_partition_variance.R ${CONFIG}

echo "Pipeline complete: $(date)"
echo "Key outputs:"
echo "data/aggregated_sensitivity.csv       - Local OAT results"
echo "data/sobol_indices.csv                - Sobol Si/Ti indices"
echo "data/variance_partition_site_level.csv - Variance budget"
echo "data/variance_partition_parameters.csv - Per-parameter breakdown"
echo "data/plots/                            - Visualization figures"
