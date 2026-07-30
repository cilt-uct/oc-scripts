#!/bin/bash
# wrapper-translate-whisper-subtitles.sh
# Wrapper to safely run translate-whisper-subtitles.py as the opencast user

# ---- CONFIG ----
SCRIPT="/opt/opencast/wfexec/translate-whisper-subtitles.py"

# ---- LOGGING ----
echo "Starting Whisper subtitle translation wrapper"
echo "Arguments received: $@"

# ---- TEMP LOG FILE ----
TMPDIR="${TMPDIR:-/tmp}"
LOGFILE="$(mktemp "$TMPDIR/whisper-translation.XXXXXXXXXX.log")"
chmod 600 "$LOGFILE"
trap 'rm -f "$LOGFILE"' EXIT

# ---- ARGUMENT VALIDATION ----
# Required:
# input_vtt target_language output_vtt mediapackage_id
if [ "$#" -ne 4 ]; then
  echo "Usage: ${0##*/} <input_vtt> <target_language> <output_vtt> <mediapackage_id>" >&2
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

# Ensure the translation script exists and is readable
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