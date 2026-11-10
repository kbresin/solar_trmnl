#!/usr/bin/env bash
# One-time SolarEdge V2 (Site Access / OAuth) authorization.
#
# Step 1:  api/v2_authorize.sh
#          Opens the SolarEdge consent page. Approve access; the browser then
#          fails to load localhost:8080 — that's expected.
# Step 2:  api/v2_authorize.sh '<full URL from the browser address bar>'
#          Exchanges the code for tokens, saves them, and makes a test call.
#
# Tokens are saved to ~/.local/state/solar_trmnl/tokens.json (mode 600).
# Repeat this about every 24 months, or after the jobs stop for 14+ days.

set -euo pipefail

# shellcheck source=/dev/null
source "$HOME/.secrets/se.sh"
: "${SOLAREDGE_CLIENT_ID:?missing from ~/.secrets/se.sh}"
: "${SOLAREDGE_CLIENT_SECRET:?missing from ~/.secrets/se.sh}"
: "${SOLAREDGE_SITE_ID:?missing from ~/.secrets/se.sh}"

AUTHORIZE_URL="https://connect.solaredge.com/authorize"
TOKEN_URL="https://monitoringapi.solaredge.com/v2/oauth2/token"
API_BASE="https://monitoringapi.solaredge.com/v2"
REDIRECT_URI="http://localhost:8080/oauth/callback"
STATE_DIR="$HOME/.local/state/solar_trmnl"
TOKEN_FILE="$STATE_DIR/tokens.json"

urlencode() { jq -rn --arg v "$1" '$v|@uri'; }

if [[ $# -eq 0 ]]; then
	url="${AUTHORIZE_URL}?response_type=code"
	url+="&client_id=$(urlencode "$SOLAREDGE_CLIENT_ID")"
	url+="&redirect_uri=$(urlencode "$REDIRECT_URI")"
	url+="&scope=$(urlencode "SITE_DATA DEVICE_DATA")"
	url+="&access_duration=24"
	echo "Open this URL, sign in with the account that owns the site, and approve:"
	echo
	echo "  $url"
	echo
	echo "Then copy the full localhost:8080 URL from the address bar and run:"
	echo "  $0 '<that URL>'"
	command -v open >/dev/null && open "$url"
	exit 0
fi

# Accept either the full callback URL or a bare code.
arg="$1"
if [[ "$arg" == *"code="* ]]; then
	query="${arg#*\?}"
	code=$(sed -nE 's/(^|.*&)code=([^&#]*).*/\2/p' <<<"$query")
	cb_site=$(sed -nE 's/(^|.*&)site_id=([^&#]*).*/\2/p' <<<"$query")
	code=$(python3 -c 'import sys,urllib.parse;print(urllib.parse.unquote(sys.argv[1]))' "$code")
else
	code="$arg"
	cb_site=""
fi
[[ -n "$code" ]] || {
	echo "No code found in argument." >&2
	exit 1
}

if [[ -n "$cb_site" && "$cb_site" != "$SOLAREDGE_SITE_ID" ]]; then
	echo "WARNING: callback site_id=$cb_site but SOLAREDGE_SITE_ID=$SOLAREDGE_SITE_ID" >&2
fi

body=$(jq -n --arg c "$code" --arg id "$SOLAREDGE_CLIENT_ID" --arg s "$SOLAREDGE_CLIENT_SECRET" \
	'{grant_type:"authorization_code", code:$c, client_id:$id, client_secret:$s}')

resp_file=$(mktemp)
trap 'rm -f "$resp_file"' EXIT
status=$(curl -sS -o "$resp_file" -w '%{http_code}' -X POST "$TOKEN_URL" \
	-H 'Content-Type: application/json' -H 'Accept: application/json' -d "$body")

if [[ "$status" != 2* ]] || ! jq -e '.access_token and .refresh_token' "$resp_file" >/dev/null 2>&1; then
	echo "Token exchange failed (HTTP $status):" >&2
	jq . "$resp_file" 2>/dev/null >&2 || cat "$resp_file" >&2
	exit 1
fi

umask 077
mkdir -p "$STATE_DIR"
# authorized_at marks the start of the 24-month grant; run.sh warns before it ends.
now=$(date -u +%FT%TZ)
jq --arg now "$now" '. + {obtained_at:$now, authorized_at:$now, access_duration_months:24}' "$resp_file" >"$TOKEN_FILE"
chmod 600 "$TOKEN_FILE"
rm -f "$STATE_DIR/reauth_notified" "$STATE_DIR/grant_expiry_notified"
echo "Tokens saved to $TOKEN_FILE"
echo "Token response fields (values hidden):"
jq -r 'to_entries[] | "  \(.key): \(if (.key|test("token")) then "<\(.value|tostring|length) chars>" else .value end)"' "$TOKEN_FILE"

echo
echo "Test call: GET /sites/$SOLAREDGE_SITE_ID"
access=$(jq -r .access_token "$TOKEN_FILE")
status=$(curl -sS -o "$resp_file" -w '%{http_code}' \
	-H "Authorization: Bearer $access" -H 'Accept: application/json' \
	"$API_BASE/sites/$SOLAREDGE_SITE_ID")
echo "HTTP $status"
jq . "$resp_file" 2>/dev/null || cat "$resp_file"
