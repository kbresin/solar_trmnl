#!/bin/bash

set -e
PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

VENV="$PROJECT_DIR/.venv/bin/activate"
if [[ ! -f "$VENV" ]]; then
  echo "Error: venv not found at $VENV — run: ./setup.sh" >&2
  exit 1
fi
source "$VENV"

today_json=$(mktemp)
output_bmp=$(mktemp --suffix=.bmp)
trap 'rm -f "${today_json}" "${output_bmp}"' EXIT

$PROJECT_DIR/api/get_site_energy_today.sh > "${today_json}"

TODAY_WH=$(jq .timeFrameEnergy.energy "${today_json}")
LIFETIME_WH=$(jq .timeFrameEnergy.endLifetimeEnergy.energy "${today_json}")

ENERGY_TODAY=$(python3 $PROJECT_DIR/api/energy_units.py "${TODAY_WH}")
LIFETIME_ENERGY=$(python3 $PROJECT_DIR/api/energy_units.py "${LIFETIME_WH}")

python3 $PROJECT_DIR/gen_solar_status_bmp.py --daily-output "$ENERGY_TODAY" --lifetime-output "$LIFETIME_ENERGY" --output "${output_bmp}"

$PROJECT_DIR/upload.sh "${output_bmp}"
