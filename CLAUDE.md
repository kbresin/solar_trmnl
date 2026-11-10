# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this project does

Monitors a solar array (Gethsemane Lutheran Church / GLC Solar) and displays data on a TRMNL e-ink device. The pipeline:

1. Fetches energy data (today's output + lifetime production) from the SolarEdge Monitoring API V2 (OAuth; helpers in `api/v2_lib.sh`)
2. Converts units via `api/energy_units.py`
3. Renders a 800×480 monochrome BMP image via `gen_solar_status_bmp.py`
4. Uploads the BMP to a public S3 bucket via `upload.sh`
5. TRMNL device polls S3 and displays the image

## Setup

```bash
./setup.sh   # creates .venv and pip-installs requirements.txt
```

The font file `Gidole-Regular.ttf` must also be present in the repo root (not committed — in `.gitignore`).

## Running

```bash
# Production run (with SNS alerting on failure)
./run.sh

# Direct run (no alerting)
./bmp_today_api.sh

# Upload to output_test.bmp on S3 instead of output.bmp
./bmp_today_api.sh --test

# Generate BMP directly with known values (useful for testing layout)
python3 gen_solar_status_bmp.py --daily-output '200.64 kWh' --lifetime-output '262.94 MWh' --output out.bmp

# Convert Wh to a readable string
python3 api/energy_units.py 265930000
```

## Cron

```
# Daily BMP generation at 10:35 PM
35 22 * * * $HOME/projects/solar_trmnl/run.sh bmp_today_api.sh >>$HOME/.local/logs/glcsolar_api.log 2>&1

# Daily fault check at 10:00 AM — SNS warning sent automatically on non-zero exit
0 10 * * 1-4,6 $HOME/projects/solar_trmnl/run.sh api/check4faults.sh >>$HOME/.local/logs/glcsolar_healthcheck.log 2>&1

# Friday full check — same fault check plus 7-day inverter telemetry logged to ~/.cache/solar_trmnl/inverter_weekly.log
0 10 * * 5 $HOME/projects/solar_trmnl/run.sh api/check4faults.sh --full-check >>$HOME/.local/logs/glcsolar_healthcheck.full.log 2>&1
```

The daily run also keeps the V2 refresh token alive. It expires after 14 days unused, so don't leave the jobs disabled longer than that.

`run.sh` always echoes output to stdout so both success and failure runs are captured in the log. On non-zero exit it fires an SNS warning before exiting — `check4faults.sh` exits 0 when clean, 1 when alerts are found, 2 if the API is unreachable.

**Re-login notifications.** Exit code 3 (`SE_EXIT_REAUTH` in `api/v2_lib.sh`) means a person has to act. It covers:
- the token endpoint rejecting the refresh token or the client credentials (HTTP 400/401)
- an API call still returning 401/403 after a forced refresh
- a missing `tokens.json`

Network errors and 5xx responses are not code 3. On code 3, `run.sh` sends a dedicated "SolarEdge login needed" SNS message with the `v2_authorize.sh` steps, at most once a day. After a successful run, it sends a reminder when the 24-month grant (`authorized_at` in `tokens.json`) is 30 or fewer days from ending, at most once a week. The throttle markers live in `~/.local/state/solar_trmnl/` and are cleared by `v2_authorize.sh`. `SE_STATE_DIR` overrides that directory, which makes it possible to test with fake tokens.

## Environment — `~/.secrets/se.sh`

All secrets and site-specific config are sourced from `~/.secrets/se.sh`. Required exports:

```bash
export SOLAREDGE_CLIENT_ID=...       # V2 Site Access app
export SOLAREDGE_CLIENT_SECRET=...
export SOLAREDGE_SITE_ID=2764610
export S3_PROFILE=glcsolar_s3      # AWS CLI profile name
export S3_BUCKET=glcsolar          # S3 bucket name
```

Additional requirements: `jq` and the AWS CLI must be on `PATH`.

## API Reference

A condensed reference covering the endpoints used in this project is in `api/solaredge_api.txt`.

## Key details

- BMP output is written to a `mktemp` file and cleaned up after upload — nothing is written to the repo directory
- BMP is always monochrome 1-bit (`Image.new('1', (800, 480), ...)`) — Pillow dithers any grayscale automatically
- `upload.sh` takes two args: `<local-bmp-path> <s3-destination-filename>` — called by `bmp_today_api.sh`, rarely needed standalone
- OAuth tokens live in `~/.local/state/solar_trmnl/tokens.json` (mode 600), created once by `api/v2_authorize.sh`. `api/v2_lib.sh` refreshes them before each call; the refresh token rotates on every use and dies after 14 days unused, so only one machine may hold it
- `api/v2_lib.sh` disables xtrace inside its functions so the bearer token never lands in a `set -x` log
- `api/check4faults.sh --debug` dumps the raw V2 responses
- `check4faults.sh` checks the optimizer roster on every run. It compares the active optimizers (110, one per panel) with `~/.local/state/solar_trmnl/optimizers.tsv`. Fewer active is a FAULT. A replacement (same count, new serial) updates the roster, and the change is printed in the run's output.
- `--full-check` also runs `api/inverter_balance.py`: each inverter's output per panel as a share of the median inverter, last 7 days vs the 21 days before. A drop of 8+ points is a PERF warning (exit 1). Inverters are judged against themselves because Inverter 4 normally runs 80–98% of the median (shading) and Inverter 1 runs ~104%. A single dead panel (3–4 points) is below the noise; the optimizer check and SolarEdge alerts cover that
- CO2 conversion: `411784.0 / 265930.0` lbs/kWh; cost: `$0.085/kWh`
- Unused scripts (scraping pipeline, health checks, etc.) are preserved in `UNUSED/`
