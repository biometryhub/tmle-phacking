#!/bin/bash
# Script to set the TMLE simulation script running on a VM with a
# specified N sample size (to distribute the computations across
# machines).
#
# Run with ./run_N.sh -n 50 -s 1000
# Where -n 50 (or 100, or 500, or whatever) specifies the N to use for the
# sample size in the R code, and -s 1000 (or whatever) specifies the
# total number of seeds to use for the run (optional).
#
# Code author: Russell A. Edson, Biometry Hub
# Date last modified: 28/03/2022
print_usage() {
  echo "Usage: run_N -n <sample_size> -s <total_seeds>"
  echo "  e.g. run_N.sh -n 50 -s 1000"
}

N=""
SEEDS="10000"
while getopts 'n:s::' ARG; do
  case "${ARG}" in
    n) N="${OPTARG}" ;;
    s) SEEDS="${OPTARG}" ;;
    *) print_usage
       exit 1 ;;
  esac
done

HOST_WD="${HOME}/tmle-phacking"
DOCKER_WD="${HOME}/run"
OUTPUT_DIR="output_${N}"
HOST_OUT="${HOST_WD}/${OUTPUT_DIR}"
DOCKER_OUT="${DOCKER_WD}/${OUTPUT_DIR}"
HOST_LOG="${HOST_OUT}/shell_log.txt"
DOCKER_LOG="${DOCKER_OUT}/shell_log.txt"
R_SCRIPT="${DOCKER_WD}/simulate_TMLE.R"

mkdir "${HOST_OUT}"

# Query and log system info
echo "$(uname -a)" >> "${HOST_LOG}"
echo "$(free -h)" >> "${HOST_LOG}"
echo "$(df -h)" >> "${HOST_LOG}"
echo "$(lscpu)" >> "${HOST_LOG}"

sudo chmod -R ugo+rw "${HOST_WD}"

# Run R job
sudo docker run --name "tmle-phacking-run${N}" -it -d \
  -v "${HOST_WD}:${DOCKER_WD}" tmle-phacking
sudo nohup docker exec "tmle-phacking-run${N}" sh -c \
  "R -e \"source('${R_SCRIPT}'); run_compute(${N}, '${DOCKER_OUT}', ${SEEDS})\" >>${DOCKER_LOG} 2>&1"
