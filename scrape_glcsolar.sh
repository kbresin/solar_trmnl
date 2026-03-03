#!/bin/bash
set -x

PATH=/bin:/usr/bin

PROJECT_DIR=/home/kyle/projects/solar_trmnl

BROWSERLESS_UP=$(docker ps | grep browserless | grep -c 'Up')

if [[ "$BROWSERLESS_UP" -lt 1 ]]; then
  docker run -d -p 3000:3000 browserless/chrome
  sleep 15
  BROWSERLESS_UP=$(docker ps | grep browserless | grep -c 'Up')
fi
if [[ "$BROWSERLESS_UP" -lt 1 ]]; then
  echo "Error: cannot find browserless/chrome"
  exit 2
fi

TMP_HTML=$(mktemp)

curl -s -o - -X POST 'http://localhost:3000/function?stealth=true&timeout=120000'   -H 'Content-Type: application/javascript'   --data-binary @$PROJECT_DIR/solaredge.GOLD.js > "$TMP_HTML"

echo "wrote to $TMP_HTML"

# 294.34 kWh
ENERGY_TODAY=$(grep 'Energy today' "$TMP_HTML" | sed 's#^.*Energy today</div>##' | sed 's#<div[^>]*>##' | cut -c 1-100 | sed 's/<.*$//')
LIFETIME_ENERGY=$(grep 'Lifetime energy' "$TMP_HTML" | sed 's#^.*Lifetime energy</div>##' | sed 's#<div[^>]*>##' | cut -c 1-100 | sed 's/<.*$//')

python3 $PROJECT_DIR/gen_solar_status_bmp.py --daily-output "$ENERGY_TODAY" --lifetime-output "$LIFETIME_ENERGY"

$PROJECT_DIR/upload.sh

#rm "$TMP_HTML"
