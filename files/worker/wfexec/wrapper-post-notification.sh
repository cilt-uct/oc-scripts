#!/bin/bash
# wrapper-post-notification.sh
# Wrapper to safely run post-notification.pl as the opencast user
# Usage: wrapper-post-notification.sh <mediapackage-id> <subject>

SCRIPT="/opt/opencast/wfexec/post-notification.pl"
PERL_BIN="/usr/bin/perl"

# Check arguments
if [ $# -ne 2 ]; then
    echo "Usage: $0 <mediapackage-id> <subject>" >&2
    exit 1
fi

MEDIAPACKAGE_ID="$1"
SUBJECT="$2"

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
"$PERL_BIN" "$SCRIPT" "$MEDIAPACKAGE_ID" "$SUBJECT"
EXIT_CODE=$?

if [ $EXIT_CODE -ne 0 ]; then
    echo "Error: $SCRIPT failed with exit code $EXIT_CODE" >&2
    exit $EXIT_CODE
fi

exit 0
