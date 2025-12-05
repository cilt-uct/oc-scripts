#!/bin/bash

# ===========================
# track4k.sh
# ===========================

# Values to be filled from wfexec
input_filename=""
out_filename=""
dir=""
location=""
DEBUG=false
OPTIONS=i:o:l:d
LONGOPTIONS=input:,output:,location:,debug

# pass these files and loc to perl script
PERL_SCRIPT="/data/src/docker-track4k/run-wrapper.pl"

# Server info for logging
EXEC_USER=$(whoami)
EXEC_HOST=$(hostname)
TIMESTAMP=$(date +"%Y-%m-%d %H:%M:%S")
LOGFILE="/tmp/track4k.log"

# testong
PARSED=$(getopt --options=$OPTIONS --longoptions=$LONGOPTIONS --name "$0" -- "$@")
if [[ $? -ne 0 ]]; then
  echo "[$TIMESTAMP] ERROR: Failed to parse options." >&2
  exit 1
fi
eval set -- "$PARSED"

while true; do
  case "$1" in
    -i|--input)     input_filename="$2"; shift 2 ;;
    -o|--output)    out_filename="$2"; shift 2 ;;
    -l|--location)  location="$2"; shift 2 ;;
    -d|--debug)     DEBUG=true; shift ;;
    --) shift; break ;;
    *) echo "[$TIMESTAMP] ERROR: Unexpected option $1"; exit 1 ;;
  esac
done

# Default dir to current working directory if not set
dir=$(pwd)

# Logging setup
> "$LOGFILE"  # clear log
exec 1>> "$LOGFILE" 2>&1

# Enable command tracing only if --debug
if [ "$DEBUG" = true ]; then
  set -x
fi

# check path parameters, fix // if needed
if [[ "$input_filename" = /* ]]; then
  INPUT_FILE_PATH="$input_filename"
else
  INPUT_FILE_PATH="${dir%/}/$input_filename"
fi

if [[ "$out_filename" = /* ]]; then
  OUTPUT_FILE_PATH="$out_filename"
else
  OUTPUT_FILE_PATH="${dir%/}/$out_filename"
fi

# --- Docker run ---
docker run --rm \
  -v "$(dirname "$input_filename")":/data_in \
  -v "$(dirname "$out_filename")":/data_out \
  docker-track4k \
  /data_in/"$(basename "$input_filename")" \
  /data_out/"$(basename "$out_filename")" \
  "$location"

# Execute the Perl script, passing the required arguments
perl "$PERL_SCRIPT" "$INPUT_FILE_PATH" "$OUTPUT_FILE_PATH" "$location" >> "$LOGFILE" 2>&1
