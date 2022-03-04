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
HOST_WD="${HOME}/tmle-phacking"
DOCKER_WD="${HOME}/run"
OUTPUT_DIR="output_${N}"
HOST_OUT="${HOST_WD}/${OUTPUT_DIR}"
DOCKER_OUT="${DOCKER_OUT}/${OUTPUT_DIR}"
HOST_LOG="${HOST_OUT}/shell_log.txt"
DOCKER_LOG="${DOCKER_OUT}/shell_log.txt"
R_SCRIPT="${DOCKER_WD}/simulate_TMLE.R"

echo "$(uname -a)" >> "${HOST_LOG}"
echo "$(lscpu)" >> "${HOST_LOG}"

sudo chmod -R ugo+rw "${HOST_WD}"
sudo docker run --name "tmle-phacking-run${N}" -it -d \
  -v "${HOST_WD}:${DOCKER_WD}" tmle-phacking
sudo docker exec "tmle-phacking-run${N}" sh -c "mkdir ${DOCKER_OUT}"
sudo nohup docker exec "tmle-phacking-run${N}" sh -c \
  "R -e \"source('${R_SCRIPT}'); run_compute(${N}, '${DOCKER_OUT}')\" 2&>1 >> ${DOCKER_LOG}"
