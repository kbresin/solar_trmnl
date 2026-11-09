# SolarEdge Monitoring API V2 migration

SolarEdge shut down the V1 API on November 3, 2026. V1 calls now return HTTP 410, and the V1 key can't be reused on V2.

Both jobs are affected:

- `bmp_today_api.sh` fails, so the TRMNL gets no new images.
- `api/check4faults.sh` uses V1 as well, so there is no fault monitoring until this is fixed.

## Open question

Do we have the login that owns the Gethsemane site? OAuth approval has to come from the system owner, and the guide is written for homeowners, so a church account may work differently.

If the installer controls the site, ask them about associating it with an account that can use a Fleet API key instead. That route is simpler, with a static key and no token refresh.

## Manual steps (need the SolarEdge login)

These follow SolarEdge's homeowner guide.

- [ ] Sign in at https://developer.solaredge.com with the login that owns the site, then fill in the developer profile. The free tier is enough.
- [ ] Create a **Site Access** application for the Monitoring API, with both the `SITE_DATA` and `DEVICE_DATA` scopes.
- [ ] Set the redirect URI to `http://localhost:8080/oauth/callback` and the origin URL to `http://localhost:8080`. Nothing needs to be running there, because the code is copied from the browser's address bar.
- [ ] Add the credentials to `~/.secrets/se.sh`. The secret is only shown once.

  ```bash
  export SOLAREDGE_CLIENT_ID=...
  export SOLAREDGE_CLIENT_SECRET=...
  ```

## Code changes

- [ ] **Login:** add a one-time authorization script, plus a token refresh before each run. Refresh tokens change on every use, so save the latest one in `~/.local/state/solar_trmnl/` with owner-only permissions.
- [ ] **Daily image:** get today's energy from `/v2/sites/{id}/energy` and the lifetime total from `/v2/sites/{id}/lifetime-energy`. SolarEdge says the `TOTAL` figure can come out lower than V1's, so `/lifetime-energy` is the closer match.
- [ ] **Fault checks:** use `/v2/sites/{id}/alerts?only-open=true` for alerts and `/inverters/status` for inverter mode and temperature.
- [ ] **Error handling:** make the energy fetch fail on the HTTP error. It currently passes the error JSON along and only breaks later.

## What will be different

- **Weekly log:** `dcVoltage` no longer exists in V2, so that column has to go. SolarEdge says the Alerts API now reports those faults.
- **Re-authorizing:** the grant lasts up to 24 months, so the browser step has to be repeated about every two years. It also has to be repeated if the jobs stop for more than 14 days, because the refresh token expires.
- **Usage:** estimated at well under 200 of the 2,000 free monthly credits.

## Not tested yet

The docs read so far don't show the exact response fields for these endpoints. Check them against live responses once authorized.

## Sources

- [Migrating from V1 to V2](https://api-docs.solaredge.com/docs/developer-platform/mxj41549n0nxk-migrating-from-v1-to-v2)
- [Homeowner and Self-Access Guide](https://api-docs.solaredge.com/docs/developer-platform/df8kx5j4z9vi0-homeowner-and-self-access-guide)
- [Authentication](https://api-docs.solaredge.com/docs/developer-platform/g09jmvp5t2cok-authentication)
