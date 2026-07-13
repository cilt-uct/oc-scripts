#!/bin/bash


# from params
MEDIAPACKAGE_ID="$1"
OUTPUT_FILE="$2"

# check for existence of json file from whisper's output

# The workspace directory is: /data/opencast/archive/shared/workspace/
# ^ it needs to look for json file here, and then attach it to the mediapackage.  The json file is created by whisper but idk what it's named in the workspace directory.

# JSON_FILE="whisper_output.json" # what will it be titled????
# if [ ! -f "$JSON_FILE" ]; then
#   echo "JSON file not found!"
#   exit 1
# fi


# dir_shared_workspace="/data/opencast/archive/shared/workspace/mediapackage/$MEDIAPACKAGE_ID"



#!/usr/bin/env bash <<< I've seen both, not sure what to use


# echo "DEBUG output_file=$OUTPUT_FILE" >&2
# echo "DEBUG listing subtitles dir..." >&2
find "/data/opencast/archive/shared/workspace/collection/subtitles" -maxdepth 3 -type f | head -n 50 >&2 || true


JSON_FILE=$(find "/data/opencast/archive/shared/workspace/collection/subtitles" -type f -name "*.json" | head -n 1)

# if [[ -z "$JSON_FILE" || ! -f "$JSON_FILE" ]]; then
#   echo "No JSON found in subtitles collection" >&2
#   exit 1
# fi

# mkdir -p "$(dirname "$OUTPUT_FILE")"

cp "$JSON_FILE" "$OUTPUT_FILE"
echo "$OUTPUT_FILE"

