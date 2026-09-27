#!/bin/bash -l

#$ -l h_rt=02:00:00
#$ -N oat2-sites
#$ -o logs/
#$ -j y
#$ -cwd
#$ -t 1-100

module load R/4.4.3
Rscript scripts/012_site_results.R -i "$SGE_TASK_ID"
