#!/bin/bash
# wrapper-test-multi-props.sh
# Wrapper to safely run test-multi-props.pl as the opencast user
# Usage: wrapper-test-multi-props.sh <track-filename> <output-file>

SCRIPT="/opt/opencast/wfexec/test-multi-props.pl"
PERL_BIN="/usr/bin/perl"

# Check arguments
if [ $# -ne 2 ]; then
    echo "Usage: $0 <track-filename> <output-file>" >&2
    exit 1
fi

TRACK_FILENAME="$1"
OUTPUT_FILE="$2"

# Check if script exists
if [ ! -x "$SCRIPT" ]; then
    echo "Error: script $SCRIPT not found or not executable" >&2
    exit 2
fi

# Check if Perl exists
if [ ! -x "$PERL_BIN" ]; then
    echo "Error: Perl binary $PERL_BIN not found or not executable" >&2
    exit 3
fi

# Run the Perl script as opencast user
"$PERL_BIN" "$SCRIPT" "$TRACK_FILENAME" "$OUTPUT_FILE"
EXIT_CODE=$?

if [ $EXIT_CODE -ne 0 ]; then
    echo "Error: $SCRIPT failed with exit code $EXIT_CODE" >&2
    exit $EXIT_CODE
fi

exit 0
