#!/bin/bash
# Submit 023_generate_management_events.R as an SGE array job.
#
# Each task processes CHUNK_SIZE samples via --start/--end.
# After all tasks complete, run with --combine to merge mapping CSVs.
#
# Usage:
#   bash tools/023_submit_events_array.sh [CHUNK_SIZE]
#   bash tools/023_submit_events_array.sh --combine

set -euo pipefail

PROJ_DIR="/projectnb/dietzelab/abv1/ccmmf/uncertainty"
DESIGN_CSV="${PROJ_DIR}/data/sobol_design_matrix.csv"
EVENTS_DIR="${PROJ_DIR}/data/events"
LOG_DIR="${PROJ_DIR}/_logs/023_events"

# row count from design matrix (subtract header)
N_TOTAL=$(( $(wc -l < "${DESIGN_CSV}") - 1 ))

# --- SGE task mode: when running inside an array task ---
if [[ "${SGE_TASK_ID:-}" =~ ^[0-9]+$ ]]; then
  cd "${PROJ_DIR}"
  START=$(( (SGE_TASK_ID - 1) * EVENTS_CHUNK_SIZE + 1 ))
  END=$(( SGE_TASK_ID * EVENTS_CHUNK_SIZE ))
  [ "${END}" -gt "${EVENTS_N_TOTAL}" ] && END="${EVENTS_N_TOTAL}"
  module load R/4.4.0 2>/dev/null || module load R 2>/dev/null || true
  Rscript scripts/023_generate_management_events.R \
    --start "${START}" --end "${END}"
  exit 0
fi

# --combine: merge chunk mapping fragments into final CSV
if [[ "${1:-}" == "--combine" ]]; then
  MAPPING="${EVENTS_DIR}/events_path_mapping.csv"
  echo "sample_id,site_id,events_in_path" > "${MAPPING}"

  for f in "${EVENTS_DIR}"/mapping_chunk_*.csv; do
    tail -n+2 "${f}" >> "${MAPPING}"
  done

  # sort by sample_id (numeric) then site_id (alpha)
  (head -1 "${MAPPING}"; tail -n+2 "${MAPPING}" | sort -t, -k1,1n -k2,2) \
    > "${MAPPING}.tmp" && mv "${MAPPING}.tmp" "${MAPPING}"

  ROWS=$(( $(wc -l < "${MAPPING}") - 1 ))
  N_IN=$(find "${EVENTS_DIR}" -maxdepth 1 -name 'events_sample_*.in' | wc -l)
  # each sample generates one .in per site
  N_SITES=$(awk -F, 'NR>1{print $2}' "${MAPPING}" | sort -u | wc -l)
  EXPECTED=$(( N_TOTAL * N_SITES ))
  echo "mapping rows: ${ROWS} / ${EXPECTED} expected,  .in files: ${N_IN},  sites: ${N_SITES}"

  rm -f "${EVENTS_DIR}"/mapping_chunk_*.csv
  echo "Done: ${MAPPING}"
  exit 0
fi

# chunk size: default 3 -> ~9900 tasks; set to 2 for max parallelism
CHUNK_SIZE="${1:-3}"
N_TASKS=$(( (N_TOTAL + CHUNK_SIZE - 1) / CHUNK_SIZE ))

echo "samples=${N_TOTAL}  chunk=${CHUNK_SIZE}  tasks=${N_TASKS}"

mkdir -p "${EVENTS_DIR}" "${LOG_DIR}"

qsub \
  -V -cwd \
  -sync y \
  -N ev023 \
  -o "${LOG_DIR}/" \
  -e "${LOG_DIR}/" \
  -t "1-${N_TASKS}" \
  -l h_rt=00:30:00 \
  -pe omp 1 \
  -v "EVENTS_CHUNK_SIZE=${CHUNK_SIZE},EVENTS_N_TOTAL=${N_TOTAL}" \
  "${PROJ_DIR}/tools/023_submit_events_array.sh"

echo "All ${N_TASKS} tasks completed."
echo "Combining mapping fragments..."

# auto-combine after synchronous completion
bash "${PROJ_DIR}/tools/023_submit_events_array.sh" --combine
