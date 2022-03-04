#!/bin/bash
# Script to set the TMLE simulation script running on a VM with a
# specified N sample size (to distribute the computations across
# machines).
#
# Run with ./run_N.sh 50
# Where 50 (or 100, or 500, or whatever) is the N to use for the
# sample size in the R code.
#
# Code author: Russell A. Edson, Biometry Hub
# Date last modified: 04/03/2022
N="$1"
OUTPUT_DIR="${HOME}/run/output_${N}"
LOG="${OUTPUT_DIR}/shell_log.txt"
R_SCRIPT="${HOME}/run/simulate_TMLE.R"

sudo docker run --name tmle-phacking-run -it -d tmle-phacking \
  -v "$(pwd)":/home/ubuntu/run
sudo docker exec tmle-phacking-run sh -c "mkdir ${OUTPUT_DIR}"
sudo nohup docker exec tmle-phacking-run sh -c \
  "R -e \"source('${R_SCRIPT}'); run_compute(${N}, ${OUTPUT_DIR})\" 2&>1 >> LOG"
