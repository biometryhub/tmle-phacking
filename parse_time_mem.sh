#!/bin/bash
# Quick awk script to parse the time and memory usage for each
# of the SuperLearner combinations given the R_log.txt text file.
#
# Run with ./parse_time_mem.sh R_log.txt
#
# Code author: Russell A. Edson, Biometry Hub
# Date last modified: 28/04/2022
FILE="$1"
REGEX='/(?<=comb=)(\d+).*(?<=time:)([\d+|.]+).*(?<=usage: )([^\r\n]+)/'
echo "n,time,memory"
cat "$FILE" |
    awk 'BEGIN { RS="\n\n"; FS="\n" } /SLcomb=/ { print $1"|"$3"|"$4 }' |
    perl -ne "${REGEX} and print \"\$1,\$2,\$3\n\""
