#!/bin/bash -l

#$ -l h_rt=12:00:00
#$ -N oat1-run
#$ -o logs/
#$ -j y
#$ -cwd

module load R/4.4.3
Rscript scripts/011_run_local_sensitivity.R
