# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this project does

Monitors a solar array (Gethsemane Lutheran Church / GLC Solar) and displays data on a TRMNL e-ink device. The pipeline:

1. Fetches energy data (today's output + lifetime production)
2. Converts units via `api/energy_units.py`
3. Renders a 800×480 monochrome BMP image via `gen_solar_status_bmp.py`
4. Uploads the BMP to S3 (`s3://glcsolar/public/CE243659F38BF956/output.bmp`) via `upload.sh`
5. TRMNL device polls S3 and displays the image

## Two data pipelines

**API pipeline** (preferred): `bmp_today_api.sh`
- Calls SolarEdge Monitoring API directly
- Requires `~/.secrets/se.sh` exporting `SOLAREDGE_API_KEY`
- Uses `api/get_site_energy_today.sh` → pipes Wh through `api/energy_units.py` → renders BMP → uploads

**Scraping pipeline** (fallback): `scrape_glcsolar.sh`
- Uses `browserless/chrome` Docker container on port 3000
- Runs `solaredge.GOLD.js` via the browserless `/function` endpoint to scrape the public SolarEdge dashboard
- Parses "Energy today" and "Lifetime energy" from returned HTML with `sed`/`grep`

## Running

```bash
# API pipeline (primary)
./bmp_today_api.sh

# Scraping pipeline (requires Docker + browserless running)
./scrape_glcsolar.sh

# Generate BMP directly with known values (for testing layout)
python3 gen_solar_status_bmp.py --daily-output '200.64 kWh' --lifetime-output '262.94 MWh'

# Upload to test slot instead of prod
./upload_test.sh   # writes to test.bmp instead of output.bmp

# SolarEdge API utilities (require SOLAREDGE_API_KEY in env)
./api/get_site_energy_today.sh  # JSON: today + lifetime Wh
./api/check_health.sh           # 24h system health report
./api/check_panel_health.sh     # per-inverter DC analysis (caches serials in api/inverters.cache)
python3 api/energy_units.py 265930000  # convert Wh → readable string
```

## Environment requirements

- Python venv at `/home/kyle/projects/solar_trmnl/.venv` (contains Pillow)
- Font file `Gidole-Regular.ttf` must exist at `project_dir` (hardcoded in `gen_solar_status_bmp.py`)
- AWS CLI configured with profile `glcsolar_s3`
- `~/.secrets/se.sh` sourced for `SOLAREDGE_API_KEY`
- `jq` for JSON parsing in shell scripts
- Docker (only for scraping pipeline)

## Key details

- BMP output is always monochrome 1-bit (`Image.new('1', (800, 480), ...)`) — Pillow dithers any grayscale automatically
- `project_dir` is hardcoded as `/home/kyle/projects/solar_trmnl` in `gen_solar_status_bmp.py` — update this if the path changes
- CO2 conversion factor: `411784.0 / 265930.0` lbs/kWh; cost factor: `$0.085/kWh`
- `api/check_panel_health.sh` uses GNU `date -d` syntax (Linux) — won't work on macOS without `gdate`
