# SolarEdge Monitoring API V2 migration

SolarEdge shut down the V1 API on November 3, 2026. V1 calls now return HTTP 410, and the V1 key can't be reused on V2.

Both jobs are affected:

- `bmp_today_api.sh` fails, so the TRMNL gets no new images.
- `api/check4faults.sh` uses V1 as well, so there is no fault monitoring until this is fixed.

## Status

Authorized on 2026-11-09. **V2 is done and live on deepthought: the code is tested and cron is re-enabled.** The church's login owns the site, so the homeowner OAuth (Site Access) route works and no Fleet API key is needed. `GET /v2/sites/2764610` returns HTTP 200.

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
- [x] **Token refresh:** `api/v2_lib.sh` refreshes the access token when it has under 5 minutes left. The rotated refresh token is written to `tokens.json` atomically, under a flock. A failed refresh makes the job exit non-zero, so `run.sh` sends the SNS warning. Tested on 2026-11-09: the refresh grant works, and the refresh token does rotate.
- [x] **Daily image:** `api/get_site_energy_today.sh` outputs `{todayWh, lifetimeWh}` from `/energy?resolution=DAY` and `/lifetime-energy`. A `--test` run uploaded `output_test.bmp` (201.82 kWh / 405.82 MWh).
- [x] **Fault checks:** `api/check4faults.sh` uses `/alerts?only-open=true` and `/inverters/status`. Inverter fault modes are now checked on every run, not only when alerts are open. `--full-check` adds `/inverters/telemetry` to the weekly log.
- [x] **Error handling:** `se_get` fails on any non-2xx response and retries 429s with backoff.
- [x] Removed `set -x` from `bmp_today_api.sh`. `v2_lib.sh` also suppresses xtrace around token use.
- [x] Moved the V1-only `api/check4alerts.sh` and `api/test_inverter_data.sh` to `UNUSED/api/`.

## Remaining

- [x] **Cron re-enabled on deepthought** on 2026-11-09, after both jobs passed a test run in a cron-like minimal environment. The daily image runs at 22:35, so the token gets refreshed every day.
- [ ] Delete any other copy of `tokens.json` (laptop) if one exists. Deepthought's copy has now been refreshed, so any other copy is already dead.
- [ ] Decide whether to delete the stale V1 `~/.cache/solar_trmnl/inverters.cache`, which is no longer read.

## Re-login notifications (added 2026-11-09)

- [x] Scripts exit 3 when a new OAuth login is needed. `run.sh` then sends a "SolarEdge login needed" SNS message with the steps, at most once a day.
- [x] `run.sh` sends a reminder 30 days before the 24-month grant ends, then at most weekly. The existing token was backfilled with `authorized_at` 2026-11-09, so the grant ends 2028-11-09 and the reminders start around 2028-10-10.
- [x] Tested with fake tokens: a dead refresh token, a 401 on the access token, a bad client secret, a missing token file, the throttling, and the expiry reminder.
- **Not covered:** if cron itself stops, nothing runs to send a warning, and the refresh token dies after 14 days.

## What is different from V1

- **Weekly log columns:** `date mode tempC activePowerW intervalEnergyWh`. `dcVoltage` is gone in V2, and `energy` is now per 15-minute interval rather than lifetime. Empty overnight slots are skipped.
- **Inverter modes:** V2 reports `STARTING`, not `MPPT`, during production, even at 6 kW. This is harmless, because the check only alerts on FAULT and LOCKED_* modes.
- **Alerts:** each alert carries `type`, `impact` and the component serial, and these are printed in the warning.
- **Lifetime energy:** V2 reports 405.82 MWh.
- **Re-authorizing:** needed every 24 months, or after 14 days without a refresh.
- **API details:** confirmed endpoints and response shapes are in `api/solaredge_api.txt`.

## Sources

- [Migrating from V1 to V2](https://api-docs.solaredge.com/docs/developer-platform/mxj41549n0nxk-migrating-from-v1-to-v2)
- [Homeowner and Self-Access Guide](https://api-docs.solaredge.com/docs/developer-platform/df8kx5j4z9vi0-homeowner-and-self-access-guide)
- [Authentication](https://api-docs.solaredge.com/docs/developer-platform/g09jmvp5t2cok-authentication)
- The docs site renders with JavaScript and can't be fetched as text. The OAuth details above were cross-checked against [trooperthorn/ha_int_solaredge](https://github.com/trooperthorn/ha_int_solaredge) and [aarondrabeck/ha-solaredge-api-connector](https://github.com/aarondrabeck/ha-solaredge-api-connector).
