#!/bin/bash
# wrapper-get-organizer-details.sh
# Wrapper to safely run get_organizer_details.pl as the opencast user
# Usage: wrapper-get-organizer-details.sh <mediapackage-id> <output-file>

SCRIPT="/opt/opencast/wfexec/get_organizer_details.pl"
PERL_BIN="/usr/bin/perl"

# Check arguments
if [ $# -ne 2 ]; then
    echo "Usage: $0 <mediapackage-id> <output-file>" >&2
    exit 1
fi

MEDIAPACKAGE_ID="$1"
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
"$PERL_BIN" "$SCRIPT" "$MEDIAPACKAGE_ID" "$OUTPUT_FILE"
EXIT_CODE=$?

if [ $EXIT_CODE -ne 0 ]; then
    echo "Error: $SCRIPT failed with exit code $EXIT_CODE" >&2
    exit $EXIT_CODE
fi

exit 0
