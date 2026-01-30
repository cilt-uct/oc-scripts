#!/usr/bin/env bash

set -o errexit
set -o pipefail
set -o nounset

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=base.sh
source "$SCRIPT_DIR/base.sh"

# Load Elasticsearch credentials - will export ES_HOST, ES_USER, ES_PASS
load_es_creds

docker exec -it elasticsearch curl -u $ES_USER:$ES_PASS http://localhost:9200/_cat/indices?v