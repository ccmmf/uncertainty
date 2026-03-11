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


TASK_ID=${SGE_TASK_ID}

LAUNCHDIR="$1"
JOBLIST="$LAUNCHDIR/joblist.txt"

if [[ -z ${TASK_ID} ]]; then
  echo "ERROR: SGE_TASK_ID not set"
  exit 1
fi

if [[ ! -f "${JOBLIST}" ]]; then
  echo "ERROR: joblist.txt not found in $LAUNCHDIR"
  exit 1
fi

task_line=$((TASK_ID + 1))
total_lines=$(wc -l < "${JOBLIST}")

if [[ "${task_line}" -gt "${total_lines}" ]]; then
  echo "SGE task ${TASK_ID} exceeds available jobs ($((total_lines - 1))). Exiting."
  exit 0
fi

jobscript=$(head -n1 "${JOBLIST}")
taskdir=$(sed -n "${task_line}p" "${JOBLIST}")

if [[ ! -d "${taskdir}" ]] || [[ ! -f "${taskdir}/${jobscript}" ]]; then
  echo "ERROR: directory or job script missing for run $taskdir"
  exit 1
fi

echo "SGE task ${TASK_ID} running ${taskdir}/${jobscript}"
cd "${taskdir}"
bash "${jobscript}"
