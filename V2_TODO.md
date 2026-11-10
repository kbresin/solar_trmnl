# SolarEdge Monitoring API V2 migration

SolarEdge shut down the V1 API on November 3, 2026. V1 calls now return HTTP 410, and the V1 key can't be reused on V2.

Both jobs are affected:

- `bmp_today_api.sh` fails, so the TRMNL gets no new images.
- `api/check4faults.sh` uses V1 as well, so there is no fault monitoring until this is fixed.

## Status

Authorized on 2026-11-09. The church's login owns the site, so the homeowner OAuth (Site Access) route works and no Fleet API key is needed. `GET /v2/sites/2764610` returns HTTP 200.

## Manual steps (done)

- [x] Sign in at https://developer.solaredge.com with the login that owns the site, then fill in the developer profile. The free tier is enough.
- [x] Create a **Site Access** application for the Monitoring API, with both the `SITE_DATA` and `DEVICE_DATA` scopes.
- [x] Set the redirect URI to `http://localhost:8080/oauth/callback` and the origin URL to `http://localhost:8080`. Nothing needs to be running there: `api/v2_authorize.sh` reads the code from the URL you paste.
- [x] Add the credentials to `~/.secrets/se.sh`. The secret is only shown once.

  ```bash
  export SOLAREDGE_CLIENT_ID=...
  export SOLAREDGE_CLIENT_SECRET=...
  ```

- [x] Run the authorization on the laptop with `api/v2_authorize.sh`. Tokens are in `~/.local/state/solar_trmnl/tokens.json`.

## Move the token to the server

**Deadline: 2026-11-23.** The refresh token was issued on 2026-11-09 and expires if it isn't used for 14 days. Until the refresh script exists and runs on the server, nothing is using it.

Only **one** machine may hold and use the token. Each refresh replaces the refresh token, so a second copy stops working after the first refresh. Once the server has it, the laptop copy must be deleted.

1. On the server, pull this branch:

   ```bash
   cd ~/projects/solar_trmnl && git fetch && git checkout v2_rewrite && git pull
   ```

2. On the server, add the V2 credentials to `~/.secrets/se.sh`. Copy the `SOLAREDGE_CLIENT_ID` and `SOLAREDGE_CLIENT_SECRET` lines from the laptop's file. Remove the old `SOLAREDGE_API_KEY` line, because V1 is dead. Then lock the file down:

   ```bash
   chmod 600 ~/.secrets/se.sh
   ```

3. On the server, create the state directory:

   ```bash
   mkdir -p ~/.local/state/solar_trmnl && chmod 700 ~/.local/state/solar_trmnl
   ```

4. On the laptop, copy the token file. Replace `SERVER` with the server's ssh host:

   ```bash
   scp -p ~/.local/state/solar_trmnl/tokens.json SERVER:.local/state/solar_trmnl/tokens.json
   ```

5. On the server, check the file's permissions and that the token is there, without printing it:

   ```bash
   chmod 600 ~/.local/state/solar_trmnl/tokens.json
   jq -r '"refresh_token: \(.refresh_token|length) chars, obtained \(.obtained_at)"' ~/.local/state/solar_trmnl/tokens.json
   ```

6. On the laptop, delete the copy so it can never be refreshed from two places:

   ```bash
   rm ~/.local/state/solar_trmnl/tokens.json
   ```

**If the token expires or the copy goes wrong**, re-authorize directly on the server with `api/v2_authorize.sh`:

1. Run it with no arguments and open the printed URL in any browser.
2. Approve access.
3. Copy the `localhost:8080/oauth/callback?...` URL from the address bar, even though the page shows "refused to connect".
4. Within a few minutes, on the server, run `api/v2_authorize.sh '<that URL>'`.

## Code changes

- [x] **Login:** one-time authorization script, `api/v2_authorize.sh`.
- [ ] **Token refresh:** refresh before each run, and send an SNS warning if the refresh fails. Refresh tokens change on every use, so save the latest one in `~/.local/state/solar_trmnl/` with owner-only permissions.
- [ ] **Daily image:** get today's energy from `/v2/sites/{id}/energy` and the lifetime total from `/v2/sites/{id}/lifetime-energy`. SolarEdge says the `TOTAL` figure can come out lower than V1's, so `/lifetime-energy` is the closer match.
- [ ] **Fault checks:** use `/v2/sites/{id}/alerts?only-open=true` for alerts and `/inverters/status` for inverter mode and temperature.
- [ ] **Error handling:** make the energy fetch fail on the HTTP error. It currently passes the error JSON along and only breaks later.

## What will be different

- **Weekly log:** `dcVoltage` no longer exists in V2, so that column has to go. SolarEdge says the Alerts API now reports those faults.
- **Re-authorizing:** the grant lasts up to 24 months, so the browser step has to be repeated about every two years. It also has to be repeated if the jobs stop for more than 14 days, because the refresh token expires.
- **Usage:** estimated at well under 200 of the 2,000 free monthly credits.

## Not tested yet

The docs read so far don't show the exact response fields for the energy, alerts and inverter endpoints. Check them against live responses.

Confirmed so far:

- The authorize URL is `https://connect.solaredge.com/authorize`, with `scope=SITE_DATA DEVICE_DATA` and `access_duration=24`. The callback returns `code` and `site_id`, but no `state`.
- The token endpoint is `POST https://monitoringapi.solaredge.com/v2/oauth2/token`. It takes a JSON body with `grant_type`, `code`, `client_id` and `client_secret`, and no `redirect_uri`. It returns `access_token`, `refresh_token`, `token_type` and `expires_in` (7200 seconds).
- API calls use `Authorization: Bearer <access_token>` against `https://monitoringapi.solaredge.com/v2`.
- The refresh grant (`grant_type: refresh_token`) hasn't been tested yet.

## Sources

- [Migrating from V1 to V2](https://api-docs.solaredge.com/docs/developer-platform/mxj41549n0nxk-migrating-from-v1-to-v2)
- [Homeowner and Self-Access Guide](https://api-docs.solaredge.com/docs/developer-platform/df8kx5j4z9vi0-homeowner-and-self-access-guide)
- [Authentication](https://api-docs.solaredge.com/docs/developer-platform/g09jmvp5t2cok-authentication)
- The docs site renders with JavaScript and can't be fetched as text. The OAuth details above were cross-checked against [trooperthorn/ha_int_solaredge](https://github.com/trooperthorn/ha_int_solaredge) and [aarondrabeck/ha-solaredge-api-connector](https://github.com/aarondrabeck/ha-solaredge-api-connector).
