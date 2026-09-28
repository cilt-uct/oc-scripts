#!/bin/bash

# wrapper-detect-audio.sh
# Wrapper to safely run detect-audio.py as the opencast user

SCRIPT="/opt/opencast/wfexec/detect-audio.py"

echo "Starting audio detection wrapper"
echo "Arguments received: $@"

if [ "$#" -ne 2 ]; then
  echo "Usage: ${0##*/} <mediapackage_id> <output_file>" >&2
  exit 1
fi

MEDIAPACKAGE_ID="$1"
OUTPUT_FILE="$2"

if ! command -v python3 >/dev/null 2>&1; then
  echo "ERROR: python3 interpreter not found in PATH" >&2
  exit 1
fi

PYTHON_BIN="$(command -v python3)"

if [ ! -x "$PYTHON_BIN" ]; then
  echo "ERROR: python3 interpreter at $PYTHON_BIN is not executable" >&2
  exit 1
fi

if [ ! -f "$SCRIPT" ] || [ ! -r "$SCRIPT" ]; then
  echo "ERROR: Python script not found or not readable at $SCRIPT" >&2
  exit 1
fi

echo "Executing Python audio detection script"

"$PYTHON_BIN" "$SCRIPT" \
  "$MEDIAPACKAGE_ID" \
  "$OUTPUT_FILE"

EXIT_CODE=$?

echo "Python script exited with code $EXIT_CODE"

exit $EXIT_CODE