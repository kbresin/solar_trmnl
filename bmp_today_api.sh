#!/bin/bash

set -e
PROJECT_DIR=/home/kyle/projects/solar_trmnl

today_json=$(mktemp)

$PROJECT_DIR/api/get_site_energy_today.sh > "${today_json}"

TODAY_WH=$(jq .timeFrameEnergy.energy "${today_json}")
LIFETIME_WH=$(jq .timeFrameEnergy.endLifetimeEnergy.energy "${today_json}")
source "$PROJECT_DIR/.venv/bin/activate"

ENERGY_TODAY=$(python3 $PROJECT_DIR/api/energy_units.py "${TODAY_WH}")
LIFETIME_ENERGY=$(python3 $PROJECT_DIR/api/energy_units.py "${LIFETIME_WH}")

python3 $PROJECT_DIR/gen_solar_status_bmp.py --daily-output "$ENERGY_TODAY" --lifetime-output "$LIFETIME_ENERGY"

$PROJECT_DIR/upload.sh

rm -f "${today_json}"
