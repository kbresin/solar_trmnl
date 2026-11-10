#!/bin/bash
# Check the site for open alerts and inverter fault modes (SolarEdge API V2).
#
#   check4faults.sh               open alerts, inverter fault modes (24h), optimizer roster;
#                                 inverter detail only if unhealthy
#   check4faults.sh --full-check  also: inverter balance (api/inverter_balance.py), and
#                                 7 days of inverter data appended to the weekly log
#   check4faults.sh --debug       dump the raw API responses and exit
#
# Exit codes: 0 clean, 1 alerts or fault modes found, 2 API unreachable,
#             3 SolarEdge login needed (see SE_EXIT_REAUTH in v2_lib.sh).

PATH=/usr/local/bin:$PATH

# shellcheck source=api/v2_lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/v2_lib.sh"

SITE="/sites/${SOLAREDGE_SITE_ID}"
CACHE_DIR="${HOME}/.cache/solar_trmnl"
LOG_FILE="${INVERTER_LOG_FILE:-${CACHE_DIR}/inverter_weekly.log}"
OPTIMIZER_BASELINE="${OPTIMIZER_BASELINE:-${SE_STATE_DIR}/optimizers.tsv}"
FAULT_MODES="FAULT|LOCKED_FORCE_SHUTDOWN|LOCKED_COMM_TIMEOUT|LOCKED_INV_TRIP|LOCKED_INV_ARC_DETECTED|LOCKED_INTERNAL"

# Pass a re-auth failure (3) straight through so run.sh sends the login
# notice; report anything else as "API unreachable" (2).
fetch_failed() {
	local rc="$1"
	[[ "$rc" -eq "$SE_EXIT_REAUTH" ]] && exit "$rc"
	echo "ERROR: $2" >&2
	exit 2
}

# Compare the active optimizers (one per panel) with the last known-good roster
# in $OPTIMIZER_BASELINE. Fewer active than before is a fault. A swap (same
# count, different serials, i.e. a replaced optimizer) or a new one updates the
# roster. Sets healthy=0 on a fault.
check_optimizers() {
	local opts current missing added n_cur n_base
	opts=$(se_get "$SITE/devices" --data types=OPTIMIZER) || fetch_failed $? "could not fetch optimizer list"
	OPTIMIZERS_JSON="$opts"
	current=$(jq -r '.[] | select(.active == true) |
		[.serialNumber, .name, (.connectedToName // .connectedTo)] | @tsv' <<<"$opts" | sort)
	n_cur=$(grep -c . <<<"$current")

	if [[ ! -s "$OPTIMIZER_BASELINE" ]]; then
		mkdir -p "$(dirname "$OPTIMIZER_BASELINE")"
		echo "$current" >"$OPTIMIZER_BASELINE"
		echo "OK: ${n_cur} optimizers active (roster recorded in ${OPTIMIZER_BASELINE})"
		return
	fi
	n_base=$(grep -c . "$OPTIMIZER_BASELINE")
	missing=$(awk -F'\t' 'NR==FNR {cur[$1]; next} !($1 in cur)' <(echo "$current") "$OPTIMIZER_BASELINE")
	added=$(awk -F'\t' 'NR==FNR {base[$1]; next} !($1 in base)' "$OPTIMIZER_BASELINE" <(echo "$current"))

	if [[ -n "$missing" && $n_cur -lt $n_base ]]; then
		healthy=0
		echo "FAULT: ${n_cur} of ${n_base} optimizers active. No longer active:"
		awk -F'\t' '{printf "  %s (%s) on %s\n", $2, $1, $3}' <<<"$missing"
		return # keep the roster, so this repeats until fixed
	fi
	if [[ -n "$missing" || -n "$added" ]]; then
		echo "NOTE: optimizer roster changed (replacement?), now ${n_cur} active:"
		[[ -n "$missing" ]] && awk -F'\t' '{printf "  removed %s (%s) on %s\n", $2, $1, $3}' <<<"$missing"
		[[ -n "$added" ]] && awk -F'\t' '{printf "  added   %s (%s) on %s\n", $2, $1, $3}' <<<"$added"
		echo "$current" >"$OPTIMIZER_BASELINE"
		return
	fi
	echo "OK: all ${n_cur} optimizers active"
}

# Weekly: each inverter's output per panel vs its own last 3 weeks.
check_inverter_balance() {
	local from to daily tmp_tel tmp_opt out rc
	from=$(date -d "28 days ago" "+%Y-%m-%dT00:00:00%:z")
	to=$(date "+%Y-%m-%dT00:00:00%:z")
	daily=$(se_get "$SITE/inverters/telemetry" --data-urlencode resolution=DAY \
		--data-urlencode "from=$from" --data-urlencode "to=$to") || fetch_failed $? "could not fetch daily inverter telemetry"
	tmp_tel=$(mktemp) tmp_opt=$(mktemp)
	echo "$daily" >"$tmp_tel"
	echo "$OPTIMIZERS_JSON" >"$tmp_opt"
	out=$(python3 "$(dirname "${BASH_SOURCE[0]}")/inverter_balance.py" "$tmp_tel" "$tmp_opt" 2>&1)
	rc=$?
	rm -f "$tmp_tel" "$tmp_opt"
	echo ""
	echo "$out"
	BALANCE_REPORT="$out"
	((rc == 1)) && healthy=0
	((rc > 1)) && { echo "ERROR: inverter balance check could not run" >&2; exit 2; }
}

iso_ago() {
	date --date="$1" "+%Y-%m-%dT%H:%M:%S%:z"
}

# Turn /inverters/status (and optionally /inverters/telemetry) into rows of
#   sn  timestamp  mode  tempC  powerW  energyWh
# keyed on the status timestamps. Telemetry fields are blank if not supplied.
inverter_rows() {
	# Fed through stdin: a week of data is too big for jq's argument list.
	printf '%s\n%s\n' "$1" "${2:-{\}}" | jq -rs '
		def series($obj; $f): ($obj[$f].values // []) | map({key: .timestamp, value: .value}) | from_entries;
		.[0] as $s | .[1] as $t
		| $s.inverters | to_entries[] | .key as $sn | .value as $st
		| ($t.inverters[$sn] // {}) as $tel
		| series($st; "inverterMode") as $mode
		| series($st; "temperature") as $temp
		| series($tel; "power") as $pow
		| series($tel; "energy") as $en
		| ($mode | keys_unsorted)[]
		| select($mode[.] != null or $temp[.] != null or $pow[.] != null)
		| [$sn, ., ($mode[.] // "null"),
		   ($temp[.] // "" | tostring), ($pow[.] // "" | tostring), ($en[.] // "" | tostring)]
		| join("\t")'
}

# --- arg parsing ---

FULL_CHECK=0
DEBUG=0
for arg in "$@"; do
	[[ "$arg" == "--full-check" ]] && FULL_CHECK=1
	[[ "$arg" == "--debug" ]] && DEBUG=1
done

# --- main ---

alerts=$(se_get "$SITE/alerts" --data-urlencode only-open=true) || fetch_failed $? "could not reach SolarEdge API"

if [[ $DEBUG -eq 1 ]]; then
	echo "=== $SITE/alerts?only-open=true ==="
	echo "$alerts" | jq .
	for p in "" /devices "/devices?types=OPTIMIZER" /inverters/status /inverters/telemetry; do
		echo ""
		echo "=== $SITE$p ==="
		se_get "$SITE$p" | jq .
	done
	exit 0
fi

healthy=1
alert_qty=$(echo "$alerts" | jq 'length')
if [[ "$alert_qty" -gt 0 ]]; then
	healthy=0
	echo "FAULT: ${alert_qty} open alert(s), max impact: $(echo "$alerts" | jq 'map(.impact) | max')"
	echo "$alerts" | jq -r '.[] |
		"  \(.type) (impact \(.impact), \(.category)) on \(.component.name // "" | if . == "" then "-" else . end) \(.component.serialNumber // "") since \(.firstTrigger), last \(.lastTrigger)"'
else
	echo "OK: no open site alerts"
fi

check_optimizers

# Inverter modes are checked every run, since they're a cheap second signal.
if [[ $FULL_CHECK -eq 1 ]]; then
	window="7 days ago"
else
	window="24 hours ago"
fi
start_time=$(iso_ago "$window")
end_time=$(iso_ago "now")

status=$(se_get "$SITE/inverters/status" --data-urlencode "from=$start_time" --data-urlencode "to=$end_time") || fetch_failed $? "could not fetch inverter status"

if ! rows=$(inverter_rows "$status"); then
	echo "ERROR: could not parse inverter status" >&2
	exit 2
fi
faults=$(awk -F'\t' -v pat="^(${FAULT_MODES})$" '$3 ~ pat' <<<"$rows")
if [[ -n "$faults" ]]; then
	healthy=0
	echo ""
	echo "FAULT: inverter fault modes since ${start_time}:"
	echo "$faults" | awk -F'\t' '{printf "  %s [%s] %s temp=%s°C\n", $1, $2, $3, $4}'
fi

if [[ $healthy -eq 0 ]]; then
	echo ""
	echo "Latest inverter readings:"
	echo "$status" | jq -r '.inverters | to_entries[] |
		.key as $sn |
		([.value.inverterMode.values[] | select(.value != null)] | last) as $m |
		([.value.temperature.values[] | select(.value != null)] | last) as $t |
		"  \($sn) [\($m.timestamp // "-")]: mode=\($m.value // "none") temp=\($t.value // "-")°C"'
fi

[[ $FULL_CHECK -eq 1 ]] && check_inverter_balance

if [[ $FULL_CHECK -eq 1 ]]; then
	telemetry=$(se_get "$SITE/inverters/telemetry" --data-urlencode "from=$start_time" --data-urlencode "to=$end_time") || fetch_failed $? "could not fetch inverter telemetry"
	mkdir -p "$CACHE_DIR"
	if ! rows=$(inverter_rows "$status" "$telemetry"); then
		echo "ERROR: could not parse inverter telemetry" >&2
		exit 2
	fi
	{
		echo ""
		echo "=== Full check: ${end_time} | Inverter balance ==="
		echo "$BALANCE_REPORT"
	} >>"$LOG_FILE"
	for sn in $(echo "$status" | jq -r '.inverters | keys[]'); do
		echo ""
		echo "=== Full check: ${end_time} | Inverter ${sn} ==="
		printf 'date\tmode\ttempC\tactivePowerW\tintervalEnergyWh\n'
		awk -F'\t' -v sn="$sn" 'BEGIN{OFS="\t"} $1 == sn {print $2, $3, $4, $5, $6}' <<<"$rows"
	done >>"$LOG_FILE"
	echo "Full inverter data (${start_time} to ${end_time}) appended to ${LOG_FILE}"
fi

[[ $healthy -eq 0 ]] && exit 1 || exit 0
