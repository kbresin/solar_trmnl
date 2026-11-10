#!/usr/bin/env bash
# Print today's and lifetime production as JSON: {"todayWh": N, "lifetimeWh": N}
# Exits non-zero (with the API error on stderr) if either call fails.
set -euo pipefail

# shellcheck source=api/v2_lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/v2_lib.sh"

site="/sites/${SOLAREDGE_SITE_ID}"
# With no from/to, /energy covers today (site-local midnight to now).
today=$(se_get "$site/energy" --data-urlencode resolution=DAY)
lifetime=$(se_get "$site/lifetime-energy")

jq -n --argjson t "$today" --argjson l "$lifetime" '
	if ($t.unit != "WH" or $l.unit != "WH") then error("unexpected unit: \($t.unit) / \($l.unit)") else . end
	| {todayWh: ([$t.values[].value // 0] | add // 0 | floor), lifetimeWh: ($l.energy | floor)}'
