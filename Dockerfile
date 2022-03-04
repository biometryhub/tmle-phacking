# Dockerfile for setting up a Rocker Rv4.1.2 environment (+ packages)
# for Max's paper.
#
# Code author: Russell A. Edson, Biometry Hub
# Date last modified: 03/03/2022

## Build atop Rocker r-ver:4.1.2
FROM rocker/r-ver:4.1.2

## Install ancillary packages
RUN install2.r \
  data.table \
  tmle \
  SuperLearner \
  arm \
  rpart \
  ranger

## Make an ubuntu user and working directory
RUN useradd -ms /bin/bash ubuntu
USER ubuntu
WORKDIR /home/ubuntu

ENTRYPOINT [ "/bin/bash" ]

## Build with
##   sudo docker build -t tmle-phacking .
##
## Run it with current directory mounted to ~/run by
##   sudo docker run -it tmle-phacking -v "$(pwd)":/home/ubuntu/run
## and then execute the run_N.sh script for a given N to set the job
## running.
