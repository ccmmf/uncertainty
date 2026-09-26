#!/bin/bash
# Chain the OAT workflow from a login node: 011 writes configs and runs SIPNET, 012
# reads each site as one array task once 011 is done, 013 aggregates once every site
# is. An array and a single job can't share one qsub, hence a launcher. Paths come
# from 000-config.R.
#   bash scripts/qsub_local_sensitivity.sh
set -euo pipefail
mkdir -p logs
n=$(( $(wc -l < data_raw/statewide_sites.csv) - 1 ))
job() { qsub -terse -cwd -j y -o logs -b y "$@" | cut -d. -f1; }
r() { echo "module load R/4.4.3 && Rscript $*"; }
run=$(job -N oat-run -l h_rt=12:00:00 bash -lc "$(r scripts/011_run_local_sensitivity.R)")
sites=$(job -N oat-sites -hold_jid "$run" -t 1-"$n" -l h_rt=2:00:00 bash -lc "$(r scripts/012_site_results.R)")
job -N oat-aggregate -hold_jid "$sites" bash -lc "$(r scripts/013_aggregate_sensitivity.R)"
