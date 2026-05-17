#!/bin/bash

PATH=/usr/local/bin:$PATH

source ~/.secrets/se.sh

BASE_URL="https://monitoringapi.solaredge.com"
LOG_DIR="${HOME}/.cache/solar_trmnl"
LOG_FILE="${LOG_DIR}/inverter_weekly.log"

# inverterMode values that indicate a real problem
FAULT_MODES="FAULT|LOCKED_FORCE_SHUTDOWN|LOCKED_COMM_TIMEOUT|LOCKED_INV_TRIP|LOCKED_INV_ARC_DETECTED|LOCKED_INTERNAL"

FULL_CHECK=0
for arg in "$@"; do
	[[ "$arg" == "--full-check" ]] && FULL_CHECK=1
done

details=$(curl -sf "${BASE_URL}/site/${SOLAREDGE_SITE_ID}/details?api_key=${SOLAREDGE_API_KEY}")
if [[ $? -ne 0 ]]; then
	echo "ERROR: could not reach SolarEdge API" >&2
	exit 2
fi

alert_qty=$(echo "$details" | jq '.details.alertQuantity // 0')
alert_sev=$(echo "$details" | jq -r '.details.alertSeverity // "NONE"')

healthy=1
if [[ "$alert_sev" != "NONE" ]] || [[ "$alert_qty" -gt 0 ]]; then
	healthy=0
	echo "FAULT: ${alert_qty} open alert(s), max severity: ${alert_sev}"
else
	echo "OK: no site alerts"
fi

if [[ $healthy -eq 1 ]] && [[ $FULL_CHECK -eq 0 ]]; then
	exit 0
fi

# Fetch inverter serial numbers (needed for fault detail or full check)
inverter_sns=$(curl -sf "${BASE_URL}/site/${SOLAREDGE_SITE_ID}/inventory?api_key=${SOLAREDGE_API_KEY}" |
	jq -r '.Inventory.inverters[].SN')

end_time=$(date "+%Y-%m-%d %H:%M:%S")

if [[ $FULL_CHECK -eq 1 ]]; then
	# 7-day window for weekly deep dive
	start_time=$(date -v-7d "+%Y-%m-%d %H:%M:%S" 2>/dev/null ||
		date --date="7 days ago" "+%Y-%m-%d %H:%M:%S")
else
	# 24-hour window for fault detail only
	start_time=$(date -v-24H "+%Y-%m-%d %H:%M:%S" 2>/dev/null ||
		date --date="24 hours ago" "+%Y-%m-%d %H:%M:%S")
fi

for sn in $inverter_sns; do
	data=$(curl -sf -G "${BASE_URL}/equipment/${SOLAREDGE_SITE_ID}/${sn}/data" \
		--data-urlencode "startTime=${start_time}" \
		--data-urlencode "endTime=${end_time}" \
		--data-urlencode "api_key=${SOLAREDGE_API_KEY}")

	if [[ $healthy -eq 0 ]]; then
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
	fi

	if [[ $FULL_CHECK -eq 1 ]]; then
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
	fi
done

if [[ $FULL_CHECK -eq 1 ]]; then
	echo "Full inverter data (${start_time} to ${end_time}) appended to ${LOG_FILE}"
fi

[[ $healthy -eq 0 ]] && exit 1 || exit 0
