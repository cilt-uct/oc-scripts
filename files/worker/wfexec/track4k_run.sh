#!/bin/bash

# Initialize our variables:
input_file=""
output_file=""
location=""

# -d, --debug   If the flag exists then output debug file
DEBUG=false

OPTIONS=o:i:l:d
LONGOPTIONS=debug,input:,output:,location:

# get user trigerring this script
EXEC_USER=$(whoami)
EXEC_HOST=$(hostname)
TIMESTAMP=$(date +"%Y-%m-%d %H:%M:%S")
LOGFILE="/tmp/track4k.log"

# Pre-check: Test if the Docker daemon is running and accessible
echo "$TIMESTAMP INFO: Checking Docker daemon accessibility..." >> "$LOGFILE" 2>&1
if ! docker info >/dev/null 2>&1; then
    echo "$TIMESTAMP ERROR: Docker daemon is not running or accessible. Please check permissions for user '$EXEC_USER' on host '$EXEC_HOST'." >> "$LOGFILE" 2>&1
    exit 1
fi
echo "$TIMESTAMP INFO: Docker daemon is accessible." >> "$LOGFILE" 2>&1

# Existing debug block
if [ "$DEBUG" = true ]; then
    exec 1> >(tee -a "$LOGFILE") 2>&1
    set -x # Enable command tracing
else
    exec 1>> "$LOGFILE" 2>&1
fi

echo "$TIMESTAMP INFO: Starting Docker-related operations..."

if [ ! "$(docker ps -a -q -f name=registry)" ]; then
    docker run -d -p 5000:5000 --restart always --name registry registry:2
elif [ "$(docker ps -a -q -f status=exited -f name=registry)" ]; then
    docker container start registry
fi


# echo "$TIMESTAMP INFO: Script triggered by user '$EXEC_USER' on host '$EXEC_HOST'." > /tmp/track4k.log

# -temporarily store output to be able to check for errors
# -e.g. use “--options” parameter by name to activate quoting/enhanced mode
# -pass arguments only via   -- "$@"   to separate them correctly
PARSED=$(getopt --options=$OPTIONS --longoptions=$LONGOPTIONS --name "$0" -- "$@")
if [[ $? -ne 0 ]]; then
    # e.g. $? == 1
    #  then getopt has complained about wrong arguments to stdout
    usage $@
    exit 2
fi
# read getopt’s output this way to handle the quoting right:
eval set -- "$PARSED"

# now enjoy the options in order and nicely split until we see --
while true; do
    case "$1" in
        -i|--input)
            input_file="$2"
            shift 2
            ;;
        -o|--output)
            output_file="$2"
            shift 2
            ;;
        -l|--location)
            location="$2"
            shift 2
            ;;
        -d|--debug)
            DEBUG=true
            shift
            ;;
        --)
            shift
            break
            ;;
        *)
            echo "Programming error"
            exit 3
            ;;
    esac
done

# handle non-option arguments

if [ "$DEBUG" = true ]; then
    exec 1> >(tee -a "$LOGFILE") 2>&1
    set -x # Enable command tracing
else
    # In non-debug mode, redirect all output to the log file only
    exec 1>> "$LOGFILE" 2>&1
fi

if [ -z "$input_file" ] && [ -z "$output_file" ] && [ -z "$location" ];
    then
        echo "Required: input, output file and location (-i /path/to/file-media-wav -o /path/to/output.txt -l /path/to/track4k.json)"
        echo "Input failed" >> "$LOGFILE"
        exit 4
fi

# input_file=$(echo "$input_file" | xargs)

# Extract directory
dir=$(dirname "$input_file")

# filename
input_filename=$(basename "$input_file")
out_filename=$(basename "$output_file")

# Test input params
echo "Input file: $input_file Output file: $output_file Location: $location  directory from dir $dir and input filename: $input_filename and output filename: $out_filename : $TIMESTAMP" >> /tmp/track4k.log

# check pwd
# echo "PWD - $PWD" >> "$LOGFILE"

# check docker is installed
echo "Checking if docker is installed" >> "$LOGFILE"

# this works : Docker is installed: Docker version 28.1.1, build 4eba377
if command -v docker &> /dev/null; then
    echo " Docker is installed: $(docker --version)" >> "$LOGFILE"
else
  echo "Docker not installed" >> "$LOGFILE"
fi

# /data/src/scripts/files/config/default/wfexec/track4k.sh
# docker run --rm -v $dir/$input_filename $dir/$out_filename $location


echo "$dir/":/data docker-track4k /$input_filename /$out_filename $location >> "$LOGFILE"

sudo docker run --rm -v "$dir/":/data docker-track4k /data/"$input_filename" /data/"$out_filename" "$location"


# docker run --rm -v "$dir/":/data docker-track4k /data/"$input_filename" /data/"$out_filename" "$location"

# docker run --rm -v "$dir/":/data docker-track4k $dir/$input_filename $dir/$input_filename $location

# pass input and output as variables
# Input file: /data/opencast/archive/shared/workspace/https_mediadev.uct.ac.za/assets/assets/track4k_test/track-0/14/presenter.mkv
# Output file: /data/opencast/archive/shared/workspace/https_mediadev.uct.ac.za/assets/assets/track4k_test/track-0/14/124479317_tracked.mp4
# Location: hoerilt2