#!/usr/bin/env bash
# base.sh — shared helper functions for Opencast admin scripts

set -o errexit
set -o pipefail
set -o nounset

load_es_creds() {
    local file="/opt/opencast/etc/custom.properties"

    if [[ ! -r "$file" ]]; then
        echo "ERROR: Credentials file not readable: $file" >&2
        return 1
    fi

    ES_HOSTNAME=$(sed -n 's/^[[:space:]]*org\.opencastproject\.elasticsearch\.server\.hostname[[:space:]]*=[[:space:]]*\(.*\)/\1/p' "$file")
    ES_SCHEME=$(sed -n 's/^[[:space:]]*org\.opencastproject\.elasticsearch\.server\.scheme[[:space:]]*=[[:space:]]*\(.*\)/\1/p' "$file")
    ES_PORT=$(sed -n 's/^[[:space:]]*org\.opencastproject\.elasticsearch\.server\.port[[:space:]]*=[[:space:]]*\(.*\)/\1/p' "$file")
    ES_USER=$(sed -n 's/^[[:space:]]*org\.opencastproject\.elasticsearch\.username[[:space:]]*=[[:space:]]*\(.*\)/\1/p' "$file")
    ES_PASS=$(sed -n 's/^[[:space:]]*org\.opencastproject\.elasticsearch\.password[[:space:]]*=[[:space:]]*\(.*\)/\1/p' "$file")

    if [[ -z "${ES_USER:-}" || -z "${ES_PASS:-}" ]]; then
        echo "ERROR: Elasticsearch credentials not found in $file" >&2
        return 1
    fi

    ES_HOST="$ES_SCHEME://$ES_HOSTNAME:$ES_PORT"
    export ES_HOST ES_USER ES_PASS
}
