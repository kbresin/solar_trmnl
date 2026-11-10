#!/bin/bash

PATH=/usr/local/bin:$PATH
PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

source ~/.secrets/se.sh
source "$PROJECT_DIR/lib/tententen_aws_lib.sh"

# Must match api/v2_lib.sh.
SE_EXIT_REAUTH=3
SE_STATE_DIR="${SE_STATE_DIR:-$HOME/.local/state/solar_trmnl}"
GRANT_WARN_DAYS=30

if [[ $# -eq 0 ]]; then
	echo "Usage: run.sh <script> [args...]" >&2
	exit 1
fi

script="$1"
shift

if [[ "$script" != /* && -x "$PROJECT_DIR/$script" ]]; then
	script="$PROJECT_DIR/$script"
fi

reauth_instructions() {
	cat <<EOF
To fix, on $(hostname):
  1. cd $PROJECT_DIR && api/v2_authorize.sh
  2. Open the printed URL, sign in with the account that owns the site, approve.
  3. Copy the localhost:8080/oauth/callback?... URL from the address bar
     (the page itself won't load; that's expected).
  4. Within a few minutes: api/v2_authorize.sh '<that URL>'
EOF
}

# Send $2 at most once per $3 days, tracked by the marker file $1.
# v2_authorize.sh deletes the markers, so a fresh problem notifies right away.
notify_throttled() {
	local marker="$SE_STATE_DIR/$1" message="$2" days="$3"
	if [[ -f "$marker" ]] && (($(date +%s) - $(stat -c %Y "$marker") < days * 86400 - 3600)); then
		echo "(notification already sent within ${days}d; see $marker)"
		return
	fi
	if sns_warn "$message"; then
		mkdir -p "$SE_STATE_DIR"
		touch "$marker"
	fi
}

# Remind ahead of the 24-month OAuth grant ending, so the login can be redone
# before the display and fault checks go dark.
check_grant_expiry() {
	local token_file="$SE_STATE_DIR/tokens.json" authorized months expires days_left
	[[ -r "$token_file" ]] || return
	authorized=$(jq -r '.authorized_at // empty' "$token_file")
	months=$(jq -r '.access_duration_months // 24' "$token_file")
	[[ -n "$authorized" ]] || return
	expires=$(date -d "$authorized + $months months" +%s) || return
	days_left=$(((expires - $(date +%s) + 43200) / 86400))
	((days_left > GRANT_WARN_DAYS)) && return
	echo "WARNING: SolarEdge access grant ends in ${days_left} day(s), on $(date -d "@$expires" +%F)."
	notify_throttled grant_expiry_notified "solar_trmnl: SolarEdge access grant ends in ${days_left} day(s) ($(date -d "@$expires" +%F)).

After that, the TRMNL image and fault checks stop until the site is re-authorized.
$(reauth_instructions)" 7
}

# Bracket each run with timestamps so runs are easy to tell apart in the cron logs.
# (Wording avoids "error"/"fail": health-check greps these logs for those.)
ts() { date '+%F %T %Z'; }
start=$(date +%s)
echo "=== $(ts) start: $(basename "$script")${*:+ $*} ==="
# From a trap, so notification notes print inside the bracket and every exit path is covered.
trap 'echo "=== $(ts) end: exit ${exit_code:-?}, $(($(date +%s) - start))s ==="' EXIT

output=$("$script" "$@" 2>&1)
exit_code=$?

[[ -n "$output" ]] && echo "$output"

if [[ $exit_code -eq $SE_EXIT_REAUTH ]]; then
	notify_throttled reauth_notified "solar_trmnl: SolarEdge login needed on $(hostname)

$(basename "$script") can't reach the SolarEdge API until the site is re-authorized. The TRMNL image is not updating and fault checks are not running.
$(reauth_instructions)

Output:
${output}" 1
	exit $exit_code
fi

if [[ $exit_code -ne 0 ]]; then
	sns_warn "solar_trmnl: $(basename "$script") failed (exit ${exit_code}) on $(hostname).

Output:
${output}"
	exit $exit_code
fi

# Only after a successful run: a successful refresh means the grant is still live.
rm -f "$SE_STATE_DIR/reauth_notified"
check_grant_expiry
