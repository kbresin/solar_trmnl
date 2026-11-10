#!/usr/bin/env bash
# Shared helpers for the SolarEdge Monitoring API V2 (OAuth "Site Access").
# Source this file; it expects ~/.secrets/se.sh to provide SOLAREDGE_CLIENT_ID,
# SOLAREDGE_CLIENT_SECRET and SOLAREDGE_SITE_ID, and tokens.json to exist
# (created once by api/v2_authorize.sh).
#
#   se_get <path> [curl -G args...]   GET $SE_API_BASE<path>, JSON to stdout.
#                                     Returns non-zero (body on stderr) on HTTP error.
#
# Exit/return code SE_EXIT_REAUTH (3) means a human has to act: either the OAuth
# grant is dead and api/v2_authorize.sh must be re-run, or the client
# credentials in ~/.secrets/se.sh were rejected. run.sh turns it into a
# dedicated SNS notification. Anything else non-zero is treated as transient.

# shellcheck source=/dev/null
source "$HOME/.secrets/se.sh"
: "${SOLAREDGE_CLIENT_ID:?missing from ~/.secrets/se.sh}"
: "${SOLAREDGE_CLIENT_SECRET:?missing from ~/.secrets/se.sh}"
: "${SOLAREDGE_SITE_ID:?missing from ~/.secrets/se.sh}"

SE_API_BASE="https://monitoringapi.solaredge.com/v2"
SE_TOKEN_URL="$SE_API_BASE/oauth2/token"
SE_STATE_DIR="${SE_STATE_DIR:-$HOME/.local/state/solar_trmnl}"
SE_TOKEN_FILE="$SE_STATE_DIR/tokens.json"
SE_EXIT_REAUTH=3

# Refresh the access token if it expires within 5 minutes (or always, with
# --force). The refresh token
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
		echo "REAUTH: no token file at $SE_TOKEN_FILE — run api/v2_authorize.sh" >&2
		return $SE_EXIT_REAUTH
	fi
	local force=0
	[[ "${1:-}" == "--force" ]] && force=1
	(
		umask 077
		flock -w 60 9 || {
			echo "ERROR: timed out waiting for token lock" >&2
			exit 1
		}

		local now expires_at
		now=$(date -u +%s)
		expires_at=$(jq -r '((.obtained_at | fromdateiso8601) + (.expires_in // 0))' "$SE_TOKEN_FILE")
		((force == 0 && expires_at - now > 300)) && exit 0

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
			local err
			err=$(jq -r '"\(.error // "?"): \(.error_description // "")"' "$resp" 2>/dev/null || head -c 300 "$resp")
			# 400/401 from the token endpoint is a definitive rejection (seen:
			# "invalid_request: Invalid refresh_token", "invalid_client: ...").
			# Anything else (5xx, network) may clear up on its own.
			if [[ "$status" == 400 || "$status" == 401 ]]; then
				if [[ "$err" == invalid_client* ]]; then
					echo "REAUTH: SolarEdge rejected the client credentials (HTTP $status, $err)." >&2
					echo "Check SOLAREDGE_CLIENT_ID / SOLAREDGE_CLIENT_SECRET in ~/.secrets/se.sh." >&2
				else
					echo "REAUTH: SolarEdge rejected the refresh token (HTTP $status, $err)." >&2
					echo "A new browser login is needed: run api/v2_authorize.sh." >&2
				fi
				exit $SE_EXIT_REAUTH
			fi
			echo "ERROR: SolarEdge token refresh failed (HTTP $status, $err)" >&2
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
	local access resp status attempt rc refreshed=0
	_se_ensure_token || return $?
	access=$(jq -r .access_token "$SE_TOKEN_FILE")
	resp=$(mktemp)
	# Retry rate-limit (429) responses with backoff: 15s, 30s, 60s. On a 401,
	# force one token refresh and retry before giving up.
	for attempt in 0 1 2 3; do
		((attempt > 0)) && [[ "$status" == 429 ]] && sleep $((15 * 2 ** (attempt - 1)))
		status=$(curl -sS -G -o "$resp" -w '%{http_code}' \
			-H "Authorization: Bearer $access" -H 'Accept: application/json' \
			"$SE_API_BASE$path" "$@")
		if [[ "$status" == 401 && $refreshed -eq 0 ]]; then
			refreshed=1
			_se_ensure_token --force || {
				rc=$?
				rm -f "$resp"
				return $rc
			}
			access=$(jq -r .access_token "$SE_TOKEN_FILE")
			continue
		fi
		[[ "$status" == 429 ]] || break
	done
	if [[ "$status" == 401 || "$status" == 403 ]]; then
		echo "REAUTH: GET $path still returned HTTP $status after a fresh token:" >&2
		cat "$resp" >&2
		echo >&2
		echo "The site access grant was probably revoked or has expired. Run api/v2_authorize.sh." >&2
		rm -f "$resp"
		return $SE_EXIT_REAUTH
	fi
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
