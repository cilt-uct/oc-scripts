#!/bin/bash

# ===========================
# track4k.sh
# ===========================

# Docker image to use
IMAGE="devubuopc003.uct.ac.za:5001/docker-track4k:latest"

# Values to be filled from wfexec
input_filename=""
out_filename=""
dir=""
location=""
DEBUG=false
OPTIONS=i:o:l:d
LONGOPTIONS=input:,output:,location:,debug

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

# Logging setup
exec 1>> "$LOGFILE" 2>&1

# Enable command tracing only if --debug
if [ "$DEBUG" = true ]; then
  set -x
fi

# Default dir to current working directory if not set
dir=$(pwd)

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

if ! docker image inspect "$IMAGE" >/dev/null 2>&1; then
  echo "Image not found locally, pulling..."
  if ! docker pull "$IMAGE"; then
    echo "ERROR: Failed to pull docker image: $IMAGE"
    exit 1
  fi
fi

# --- Docker run ---
docker run --rm \
#   --cpus=2 \
#   --memory=4g \
  -v "$(dirname "$input_filename")":/data_in \
  -v "$(dirname "$out_filename")":/data_out \
  $IMAGE \
  /data_in/"$(basename "$input_filename")" \
  /data_out/"$(basename "$out_filename")" \
  "$location"
