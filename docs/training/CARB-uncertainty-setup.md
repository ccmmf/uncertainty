# Environment setup

Conda, the AWS CLI, and the S3 profile are set up once for all of MAGiC, and are
documented in
[CARB PEcAn Environment Setup](https://github.com/ccmmf/magic-training/blob/main/CARB-PEcAn-setup.md).
Follow that first.

This page covers the steps specific to the uncertainty workflow.

## Clone the repository

```bash
git clone https://github.com/ccmmf/uncertainty
cd uncertainty
```

The rest of the instructions assume that you are working inside the uncertainty
repository directory.

## Every time you start a new terminal session

Return to the uncertainty repository directory and activate conda before continuing.

```bash
cd /path/to/uncertainty
conda activate ~/.conda/envs/pecan-all/
export AWS_PROFILE=magic
```

## SIPNET

The analyses run the SIPNET binary that the ensemble workflow builds. After a
`magic-ensemble` prepare step, it is at `sipnet.git` in that run directory; the
configuration file points to it.

## The configuration file

The uncertainty CLI uses a configuration file to control the workflow. For the demo, the
configuration file is provided with the demo data. For your own runs, copy and edit
`example_user_config.yaml`.

## Confirm setup

```bash
./magic-uncertainty help            # CLI runs
aws s3 ls s3://carb/pfts/           # bucket reads
```

If either fails, fix it before starting the demo.

The model runs and the steps that read their output should run on a compute node.

---

**Next:** [Uncertainty demo](uncertainty_demo.qmd).

**Overview:** [MAGiC uncertainty training](index.qmd).
