#!/bin/bash
# wrapper-whisper-api-transcribe.sh
# Wrapper to safely run whisper-api-transcribe.py as the opencast user

# ---- CONFIG ----
SCRIPT="/opt/opencast/wfexec/whisper-api-transcribe.py"

# ---- LOGGING ----
echo "Starting Whisper transcription wrapper"
echo "Arguments received: $@"

# ---- LOG FILE ----
TMPDIR="${TMPDIR:-/tmp}"
LOGFILE="$TMPDIR/whisper-transcription.log"
rm -f "$LOGFILE"
touch "$LOGFILE"
chmod 600 "$LOGFILE"

# ---- ARGUMENT VALIDATION ----
if [ "$#" -lt 3 ]; then
  echo "Usage: ${0##*/} <input_file> <output_file> <mediapackage_id>" >&2
  exit 1
fi

# ---- VALIDATION ----
# Ensure python3 interpreter is available and executable
if ! command -v python3 >/dev/null 2>&1; then
  echo "ERROR: python3 interpreter not found in PATH"
  exit 1
fi
PYTHON_BIN="$(command -v python3)"
if [ ! -x "$PYTHON_BIN" ]; then
  echo "ERROR: python3 interpreter at $PYTHON_BIN is not executable"
  exit 1
fi

# Ensure the transcription script exists and is readable
if [ ! -f "$SCRIPT" ]; then
  echo "ERROR: Python script not found at $SCRIPT"
  exit 1
fi

if [ ! -r "$SCRIPT" ]; then
  echo "ERROR: Python script at $SCRIPT is not readable"
  exit 1
fi

# ---- CALL PYTHON SCRIPT ----
python3 "$SCRIPT" "$@" > "$LOGFILE" 2>&1
EXIT_CODE=$?

echo "Python script exited with code $EXIT_CODE"
echo "Last 20 lines of log:"
tail -n 20 "$LOGFILE"

exit $EXIT_CODE