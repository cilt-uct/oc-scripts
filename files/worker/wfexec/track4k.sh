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

# Logging setup
exec 1>> "$LOGFILE" 2>&1

# Enable command tracing only if --debug
if [ "$DEBUG" = true ]; then
  set -x
fi

# Parse command line arguments
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

# --- VALIDATE REQUIRED PARAMETERS ---
if [ -z "$input_filename" ]; then
  echo "[$TIMESTAMP] ERROR: Input file parameter (-i or --input) is required"
  echo "Usage: $0 -i <input_file> -o <output_file> -l <location>"
  exit 1
fi

if [ -z "$out_filename" ]; then
  echo "[$TIMESTAMP] ERROR: Output file parameter (-o or --output) is required"
  echo "Usage: $0 -i <input_file> -o <output_file> -l <location>"
  exit 1
fi

if [ -z "$location" ]; then
  echo "[$TIMESTAMP] ERROR: Location parameter (-l or --location) is required"
  echo "Usage: $0 -i <input_file> -o <output_file> -l <location>"
  exit 1
fi

# Validate input file exists
if [ ! -f "$input_filename" ]; then
  echo "[$TIMESTAMP] ERROR: Input file does not exist: $input_filename"
  exit 1
fi

# Validate output directory exists
output_dir=$(dirname "$out_filename")
if [ ! -d "$output_dir" ]; then
  echo "[$TIMESTAMP] ERROR: Output directory does not exist: $output_dir"
  exit 1
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

echo "[$TIMESTAMP] Starting track4k processing..."
echo "[$TIMESTAMP] User: $EXEC_USER, Host: $EXEC_HOST"
echo "[$TIMESTAMP] Input: $INPUT_FILE_PATH"
echo "[$TIMESTAMP] Output: $OUTPUT_FILE_PATH"
echo "[$TIMESTAMP] Location: $location"

# Pull docker image if not present
if ! docker image inspect "$IMAGE" >/dev/null 2>&1; then
  echo "[$TIMESTAMP] Image not found locally, pulling..."
  if ! docker pull "$IMAGE"; then
    echo "[$TIMESTAMP] ERROR: Failed to pull docker image: $IMAGE"
    exit 1
  fi
else
  echo "[$TIMESTAMP] Using local docker image: $IMAGE"
fi

# --- Docker run ---
echo "[$TIMESTAMP] Starting docker container..."
docker run --rm \
  -v "$(dirname "$INPUT_FILE_PATH")":/data_in \
  -v "$(dirname "$OUTPUT_FILE_PATH")":/data_out \
  $IMAGE \
  /data_in/"$(basename "$INPUT_FILE_PATH")" \
  /data_out/"$(basename "$OUTPUT_FILE_PATH")" \
  "$location"

# Check docker exit status
DOCKER_EXIT=$?
if [ $DOCKER_EXIT -eq 0 ]; then
  echo "[$TIMESTAMP] SUCCESS: Processing completed"
else
  echo "[$TIMESTAMP] ERROR: Docker container exited with code $DOCKER_EXIT"
  exit $DOCKER_EXIT
fi
