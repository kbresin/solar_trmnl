#!/bin/bash

PATH=/usr/local/bin:$PATH

source ~/.secrets/se.sh

BASE_URL="https://monitoringapi.solaredge.com"
CACHE_DIR="${HOME}/.cache/solar_trmnl"
CACHE_FILE="${CACHE_DIR}/inverters.cache"
LOG_FILE="${CACHE_DIR}/inverter_weekly.log"
FAULT_MODES="FAULT|LOCKED_FORCE_SHUTDOWN|LOCKED_COMM_TIMEOUT|LOCKED_INV_TRIP|LOCKED_INV_ARC_DETECTED|LOCKED_INTERNAL"

api_get() {
	curl -sf "${BASE_URL}$1?api_key=${SOLAREDGE_API_KEY}"
}

api_get_inverter_data() {
	local sn="$1" start="$2" end="$3"
	curl -sf -G "${BASE_URL}/equipment/${SOLAREDGE_SITE_ID}/${sn}/data" \
		--data-urlencode "startTime=${start}" \
		--data-urlencode "endTime=${end}" \
		--data-urlencode "api_key=${SOLAREDGE_API_KEY}"
}

get_inverter_sns() {
	if [[ -f "$CACHE_FILE" ]]; then
		cut -f1 "$CACHE_FILE"
	else
		mkdir -p "$CACHE_DIR"
		local data
		data=$(api_get "/site/${SOLAREDGE_SITE_ID}/inventory")
		echo "$data" | jq -r '.Inventory.inverters[] | "\(.SN)\t\(.name)"' >"$CACHE_FILE"
		cut -f1 "$CACHE_FILE"
	fi
}

date_ago() {
	date "$1" "+%Y-%m-%d %H:%M:%S" 2>/dev/null || date --date="$2" "+%Y-%m-%d %H:%M:%S"
}

print_fault_detail() {
	local sn="$1" data="$2"
	echo ""
	echo "Inverter ${sn}:"
	echo "$data" | jq -r '.data.telemetries[-1] |
        "  latest [\(.date)]: mode=\(.inverterMode) dcV=\(.dcVoltage)V temp=\(.temperature)°C"'
	echo "$data" | jq -r --arg pat "${FAULT_MODES}" \
		'[.data.telemetries[] | select(.inverterMode | test($pat))] |
        if length > 0 then
          "  fault modes: " + (map("[\(.date)] \(.inverterMode)") | join(", "))
        else
          "  no fault modes in window"
        end'
}

log_inverter_data() {
	local sn="$1" data="$2" end_time="$3"
	mkdir -p "$LOG_DIR"
	{
		echo ""
		echo "=== Full check: ${end_time} | Inverter ${sn} ==="
		echo "date	mode	dcVoltage	tempC	activePowerW	totalEnergyWh"
		echo "$data" | jq -r '.data.telemetries[] |
            [
                .date,
                (.inverterMode // "null"),
                (.dcVoltage | tostring),
                (.temperature | tostring),
                (.totalActivePower | tostring),
                (.totalEnergy | tostring)
            ] | join("\t")'
	} >>"$LOG_FILE"
}

# --- arg parsing ---

FULL_CHECK=0
DEBUG=0
for arg in "$@"; do
	[[ "$arg" == "--full-check" ]] && FULL_CHECK=1
	[[ "$arg" == "--debug" ]] && DEBUG=1
done

# --- main ---

details=$(api_get "/site/${SOLAREDGE_SITE_ID}/details")
if [[ $? -ne 0 ]]; then
	echo "ERROR: could not reach SolarEdge API" >&2
	exit 2
fi

if [[ $DEBUG -eq 1 ]]; then
	echo "=== /site/${SOLAREDGE_SITE_ID}/details ==="
	echo "$details" | jq .

	echo ""
	echo "=== /site/${SOLAREDGE_SITE_ID}/inventory ==="
	inventory=$(api_get "/site/${SOLAREDGE_SITE_ID}/inventory")
	echo "$inventory" | jq .

	end_time=$(date "+%Y-%m-%d %H:%M:%S")
	start_time=$(date_ago "-v-24H" "24 hours ago")
	for sn in $(get_inverter_sns); do
		echo ""
		echo "=== /equipment/${SOLAREDGE_SITE_ID}/${sn}/data (last 24h) ==="
		api_get_inverter_data "$sn" "$start_time" "$end_time" | jq .
	done
	exit 0
fi

alert_qty=$(echo "$details" | jq '.details.alertQuantity // 0')
alert_sev=$(echo "$details" | jq -r '.details.highestImpact // "0"')

healthy=1
if [[ "$alert_sev" != "0" ]] || [[ "$alert_qty" -gt 0 ]]; then
	healthy=0
	echo "FAULT: ${alert_qty} open alert(s), max severity: ${alert_sev}"
else
	echo "OK: no site alerts"
fi

if [[ $healthy -eq 1 ]] && [[ $FULL_CHECK -eq 0 ]]; then
	exit 0
fi

inverter_sns=$(get_inverter_sns)
end_time=$(date "+%Y-%m-%d %H:%M:%S")

if [[ $FULL_CHECK -eq 1 ]]; then
	start_time=$(date_ago "-v-7d" "7 days ago")
else
	start_time=$(date_ago "-v-24H" "24 hours ago")
fi

for sn in $inverter_sns; do
	data=$(api_get_inverter_data "$sn" "$start_time" "$end_time")
	if [[ -z "$data" ]]; then
		echo ""
		echo "Inverter ${sn}: no data returned"
		continue
	fi
	[[ $healthy -eq 0 ]] && print_fault_detail "$sn" "$data"
	[[ $FULL_CHECK -eq 1 ]] && log_inverter_data "$sn" "$data" "$end_time"
done

if [[ $FULL_CHECK -eq 1 ]]; then
	echo "Full inverter data (${start_time} to ${end_time}) appended to ${LOG_FILE}"
fi

[[ $healthy -eq 0 ]] && exit 1 || exit 0
