#!/usr/bin/env bash

set -o errexit
set -o pipefail
set -o nounset

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=base.sh
source "$SCRIPT_DIR/base.sh"

# Load Elasticsearch credentials - will export ES_HOST, ES_USER, ES_PASS
load_es_creds

curl -X PUT -u "$ES_USER:$ES_PASS" --data "@update_series_mapping.json" -H 'Content-Type: application/json' "$ES_HOST/opencast_series/_mapping"
curl -X POST -u "$ES_USER:$ES_PASS" -H 'Content-Type: application/json' "$ES_HOST/opencast_series/_update_by_query?refresh&conflicts=proceed"
curl -X PUT -u "$ES_USER:$ES_PASS" --data "@update_event_mapping.json" -H 'Content-Type: application/json' "$ES_HOST/opencast_event/_mapping"
curl -X POST -u "$ES_USER:$ES_PASS" -H 'Content-Type: application/json' "$ES_HOST/opencast_event/_update_by_query?refresh&conflicts=proceed"
curl -X PUT -u "$ES_USER:$ES_PASS" --data "@update_theme_mapping.json" -H 'Content-Type: application/json' "$ES_HOST/opencast_theme/_mapping"
curl -X POST -u "$ES_USER:$ES_PASS" -H 'Content-Type: application/json' "$ES_HOST/opencast_theme/_update_by_query?refresh&conflicts=proceed"
