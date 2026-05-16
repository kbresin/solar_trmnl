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
# Normal run
./bmp_today_api.sh

# Upload to output_test.bmp on S3 instead of output.bmp
./bmp_today_api.sh --test

# Generate BMP directly with known values (useful for testing layout)
python3 gen_solar_status_bmp.py --daily-output '200.64 kWh' --lifetime-output '262.94 MWh' --output out.bmp

# Convert Wh to a readable string
python3 api/energy_units.py 265930000
```

## Environment — `~/.secrets/se.sh`

All secrets and site-specific config are sourced from `~/.secrets/se.sh`. Required exports:

```bash
export SOLAREDGE_API_KEY=...
export SOLAREDGE_SITE_ID=2764610
export S3_PROFILE=glcsolar_s3      # AWS CLI profile name
export S3_BUCKET=glcsolar          # S3 bucket name
```

Additional requirements: `jq` and the AWS CLI must be on `PATH`.

## Key details

- BMP output is written to a `mktemp` file and cleaned up after upload — nothing is written to the repo directory
- BMP is always monochrome 1-bit (`Image.new('1', (800, 480), ...)`) — Pillow dithers any grayscale automatically
- `upload.sh` takes two args: `<local-bmp-path> <s3-destination-filename>` — called by `bmp_today_api.sh`, rarely needed standalone
- Inverter serial number cache lives at `~/.cache/solar_trmnl/inverters.cache` (outside the repo)
- CO2 conversion: `411784.0 / 265930.0` lbs/kWh; cost: `$0.085/kWh`
- Unused scripts (scraping pipeline, health checks, etc.) are preserved in `UNUSED/`
