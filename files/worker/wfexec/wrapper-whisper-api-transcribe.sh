#!/bin/bash
# wrapper-whisper-api-transcribe.sh
# Wrapper to safely run whisper-api-transcribe.py as the opencast user

# ---- CONFIG ----
SCRIPT="/opt/opencast/wfexec/whisper-api-transcribe.py"

# ---- LOGGING ----
echo "Starting Whisper transcription wrapper"
echo "Arguments received: $@"

# ---- VALIDATION ----
if [ ! -f "$SCRIPT" ]; then
  echo "ERROR: Python script not found at $SCRIPT"
  exit 1
fi

# ---- CALL PYTHON SCRIPT ----
python3 "$SCRIPT" "$@" > /tmp/whisper.log 2>&1
EXIT_CODE=$?

echo "Python script exited with code $EXIT_CODE"
echo "Last 20 lines of log:"
tail -n 20 /tmp/whisper.log

exit $EXIT_CODE