#!/bin/bash
#$ -V
#$ -cwd
#$ -S /bin/bash
#$ -t 1-@NJOBS@
#$ -N @NAME@
#$ -o @STDOUT@
#$ -e @STDERR@
#$ -pe omp 1
#$ -l h_rt=2:00:00
#$ -l buyin
# =============================================================================
# SGE Array Job Launcher for PEcAn Model Runs
# 
# PEcAn calls this script with a single argument: path to joblist.txt
# joblist.txt format:
#   Line 1: job script name (e.g., ./job.sh)
#   Line 2+: run directories relative to workspace root
#
# CRITICAL: job.sh uses relative paths, so we must run from SGE_O_WORKDIR
# =============================================================================
set -e  # Exit on error
TASK_ID=${SGE_TASK_ID}
# Validate task ID
if [[ -z "${TASK_ID}" ]]; then
  echo "ERROR: SGE_TASK_ID not set"
  exit 1
fi
# Must run from the original submission directory
cd "${SGE_O_WORKDIR}" || exit 1
# Get joblist path (argument can be relative or absolute)
JOBLIST="$1"
if [[ "${JOBLIST:0:1}" != "/" ]]; then
  JOBLIST="${SGE_O_WORKDIR}/${JOBLIST}"
fi
# NFS caching workaround: wait for file to be readable
WAIT_COUNT=0
while [[ ${WAIT_COUNT} -lt 60 ]]; do
  if [[ -r "${JOBLIST}" ]]; then
    break
  fi
  sleep 1
  WAIT_COUNT=$((WAIT_COUNT + 1))
done
if [[ ! -r "${JOBLIST}" ]]; then
  echo "ERROR: Cannot read joblist at ${JOBLIST} after ${WAIT_COUNT}s"
  exit 1
fi
# Get job script name (line 1) and total jobs
JOBSCRIPT=$(head -n 1 "${JOBLIST}")
TOTAL_LINES=$(wc -l < "${JOBLIST}")
TOTAL_JOBS=$((TOTAL_LINES - 1))
# Check if this task exceeds available jobs
if [[ ${TASK_ID} -gt ${TOTAL_JOBS} ]]; then
  echo "Task ${TASK_ID} exceeds available jobs (${TOTAL_JOBS}). Exiting."
  exit 0
fi
# Get run directory for this task (line TASK_ID + 1)
TASK_LINE=$((TASK_ID + 1))
RUNDIR=$(sed -n "${TASK_LINE}p" "${JOBLIST}")
# Make absolute if relative
if [[ "${RUNDIR:0:1}" != "/" ]]; then
  RUNDIR="${SGE_O_WORKDIR}/${RUNDIR}"
fi
# Handle ./job.sh vs job.sh
JOBSCRIPT="${JOBSCRIPT#./}"
echo "Task ${TASK_ID}/${TOTAL_JOBS}: Running ${RUNDIR}/${JOBSCRIPT}"
# Execute job.sh from workspace root (required for relative paths in job.sh)
bash "${RUNDIR}/${JOBSCRIPT}"
