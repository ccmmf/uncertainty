#!/bin/bash -l

#$ -l h_rt=01:00:00
#$ -N oat3-aggregate
#$ -o logs/
#$ -j y
#$ -cwd

module load R/4.4.3
Rscript scripts/013_aggregate_sensitivity.R
