#!/usr/bin/env bash

mkdir -p logs

qsub -N oat1 scripts/scc011-run.sh
qsub -N oat2 -hold_jid oat1 scripts/scc012-site-results.sh
qsub -N oat3 -hold_jid oat2 scripts/scc013-aggregate.sh
