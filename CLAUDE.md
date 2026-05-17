# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this project does

Monitors a solar array (Gethsemane Lutheran Church / GLC Solar) and displays data on a TRMNL e-ink device. The pipeline:

1. Fetches energy data (today's output + lifetime production) from the SolarEdge API
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
# Daily BMP generation at 10:05 PM
5 22 * * * /home/$USER/projects/solar_trmnl/run.sh bmp_today_api.sh >>/home/$USER/projects/solar_trmnl/glcsolar_api.log 2>&1

# Daily fault check at 10:00 AM — SNS warning sent automatically on non-zero exit
0 10 * * 1-4,6 /home/$USER/projects/solar_trmnl/run.sh api/check4faults.sh >>/home/$USER/projects/solar_trmnl/glcsolar_api.log 2>&1

# Friday full check — same fault check plus 7-day inverter telemetry logged to ~/.cache/solar_trmnl/inverter_weekly.log
0 10 * * 5 /home/$USER/projects/solar_trmnl/run.sh api/check4faults.sh --full-check >>/home/$USER/projects/solar_trmnl/glcsolar_api.log 2>&1
```

`run.sh` always echoes output to stdout so both success and failure runs are captured in the log. On non-zero exit it fires an SNS warning before exiting — `check4faults.sh` exits 0 when clean, 1 when alerts are found, 2 if the API is unreachable.

## Environment — `~/.secrets/se.sh`

All secrets and site-specific config are sourced from `~/.secrets/se.sh`. Required exports:

```bash
export SOLAREDGE_API_KEY=...
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
- Inverter serial number cache lives at `~/.cache/solar_trmnl/inverters.cache` (outside the repo)
- CO2 conversion: `411784.0 / 265930.0` lbs/kWh; cost: `$0.085/kWh`
- Unused scripts (scraping pipeline, health checks, etc.) are preserved in `UNUSED/`
