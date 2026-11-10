#!/usr/bin/env bash
# Shared helpers for the SolarEdge Monitoring API V2 (OAuth "Site Access").
# Source this file; it expects ~/.secrets/se.sh to provide SOLAREDGE_CLIENT_ID,
# SOLAREDGE_CLIENT_SECRET and SOLAREDGE_SITE_ID, and tokens.json to exist
# (created once by api/v2_authorize.sh).
#
#   se_get <path> [curl -G args...]   GET $SE_API_BASE<path>, JSON to stdout.
#                                     Returns non-zero (body on stderr) on HTTP error.

# shellcheck source=/dev/null
source "$HOME/.secrets/se.sh"
: "${SOLAREDGE_CLIENT_ID:?missing from ~/.secrets/se.sh}"
: "${SOLAREDGE_CLIENT_SECRET:?missing from ~/.secrets/se.sh}"
: "${SOLAREDGE_SITE_ID:?missing from ~/.secrets/se.sh}"

SE_API_BASE="https://monitoringapi.solaredge.com/v2"
SE_TOKEN_URL="$SE_API_BASE/oauth2/token"
SE_STATE_DIR="$HOME/.local/state/solar_trmnl"
SE_TOKEN_FILE="$SE_STATE_DIR/tokens.json"

# Refresh the access token if it expires within 5 minutes. The refresh token
# rotates on every use, so the new one is written (atomically) before anything
# else happens. A flock guards against two jobs refreshing at once.
se_ensure_token() {
	_se_quiet _se_ensure_token "$@"
}

se_get() {
	_se_quiet _se_get "$@"
}

# Run a function with xtrace off so tokens never land in a `set -x` log.
_se_quiet() {
	local had_x=0 rc
	[[ $- == *x* ]] && had_x=1
	{ set +x; } 2>/dev/null
	"$@"
	rc=$?
	((had_x)) && set -x
	return $rc
}

_se_ensure_token() {
	if [[ ! -s "$SE_TOKEN_FILE" ]]; then
		echo "ERROR: no token file at $SE_TOKEN_FILE — run api/v2_authorize.sh" >&2
		return 1
	fi
	(
		umask 077
		flock -w 60 9 || {
			echo "ERROR: timed out waiting for token lock" >&2
			exit 1
		}

		local now expires_at
		now=$(date -u +%s)
		expires_at=$(jq -r '((.obtained_at | fromdateiso8601) + (.expires_in // 0))' "$SE_TOKEN_FILE")
		((expires_at - now > 300)) && exit 0

		local body resp status tmp
		body=$(jq -n --arg r "$(jq -r .refresh_token "$SE_TOKEN_FILE")" \
			--arg id "$SOLAREDGE_CLIENT_ID" --arg s "$SOLAREDGE_CLIENT_SECRET" \
			'{grant_type:"refresh_token", refresh_token:$r, client_id:$id, client_secret:$s}')
		resp=$(mktemp "$SE_STATE_DIR/.resp.XXXXXX")
		tmp=$(mktemp "$SE_STATE_DIR/.tokens.XXXXXX")
		trap 'rm -f "$resp" "$tmp"' EXIT
		status=$(curl -sS -o "$resp" -w '%{http_code}' -X POST "$SE_TOKEN_URL" \
			-H 'Content-Type: application/json' -H 'Accept: application/json' -d "$body")

		if [[ "$status" != 2* ]] || ! jq -e '.access_token' "$resp" >/dev/null 2>&1; then
			echo "ERROR: SolarEdge token refresh failed (HTTP $status):" >&2
			jq 'with_entries(select(.key|test("token")|not))' "$resp" >&2 2>/dev/null || cat "$resp" >&2
			echo "If the refresh token has expired, re-run api/v2_authorize.sh." >&2
			exit 1
		fi

		# Keep the old refresh token if the response doesn't include a new one.
		jq -s --arg now "$(date -u +%FT%TZ)" \
			'.[0] + .[1] + {obtained_at:$now}' "$SE_TOKEN_FILE" "$resp" >"$tmp"
		chmod 600 "$tmp"
		mv -f "$tmp" "$SE_TOKEN_FILE"
	) 9>"$SE_STATE_DIR/.tokens.lock"
}

_se_get() {
	local path="$1"
	shift
	_se_ensure_token || return 1
	local access resp status attempt
	access=$(jq -r .access_token "$SE_TOKEN_FILE")
	resp=$(mktemp)
	# Retry rate-limit (429) responses with backoff: 15s, 30s, 60s.
	for attempt in 0 1 2 3; do
		((attempt > 0)) && sleep $((15 * 2 ** (attempt - 1)))
		status=$(curl -sS -G -o "$resp" -w '%{http_code}' \
			-H "Authorization: Bearer $access" -H 'Accept: application/json' \
			"$SE_API_BASE$path" "$@")
		[[ "$status" == 429 ]] || break
	done
	if [[ "$status" != 2* ]]; then
		echo "ERROR: GET $path returned HTTP $status:" >&2
		cat "$resp" >&2
		echo >&2
		rm -f "$resp"
		return 1
	fi
	cat "$resp"
	rm -f "$resp"
}
