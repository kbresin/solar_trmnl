#!/bin/bash

PATH=/usr/local/bin:$PATH

source ~/.secrets/se.sh

BASE_URL="https://monitoringapi.solaredge.com"
CACHE_DIR="${HOME}/.cache/solar_trmnl"
CACHE_FILE="${CACHE_DIR}/inverters.cache"

end_time=$(date "+%Y-%m-%d %H:%M:%S")
start_time=$(date -v-24H "+%Y-%m-%d %H:%M:%S" 2>/dev/null ||
	date --date="24 hours ago" "+%Y-%m-%d %H:%M:%S")

if [[ ! -f "$CACHE_FILE" ]]; then
	mkdir -p "$CACHE_DIR"
	curl -sf "${BASE_URL}/site/${SOLAREDGE_SITE_ID}/inventory?api_key=${SOLAREDGE_API_KEY}" |
		jq -r '.Inventory.inverters[] | "\(.SN)\t\(.name)"' >"$CACHE_FILE"
fi

while IFS=$'\t' read -r sn name; do
	echo "=== ${name} (${sn}) ==="
	curl -sf -G "${BASE_URL}/equipment/${SOLAREDGE_SITE_ID}/${sn}/data" \
		--data-urlencode "startTime=${start_time}" \
		--data-urlencode "endTime=${end_time}" \
		--data-urlencode "api_key=${SOLAREDGE_API_KEY}" | jq .
	echo ""
done <"$CACHE_FILE"
