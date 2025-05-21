#!/bin/bash

PATH=/bin:/usr/bin

PROJECT_DIR=/home/kyle/projects/solar_trmnl

BROWSERLESS_UP=$(docker ps | grep browserless | grep -c 'Up')

if [[ "$BROWSERLESS_UP" -lt 1 ]]; then
  docker start -p 3000:3000 browserless/chrome
  sleep 15
fi
if [[ "$BROWSERLESS_UP" -lt 1 ]]; then
  echo "Error: cannot find browserless/chrome"
  exit 2
fi

TMP_HTML=$(mktemp)

curl -s -o - \
  -X POST http://localhost:3000/scrape \
  -H 'Content-Type: application/json' \
  -d '{
         "url": "https://monitoringpublic.solaredge.com/solaredge-web/p/site/public?name=Gethsemane%20Lutheran%20Church",
         "gotoOptions": { "waitUntil": "networkidle0" },
  "elements": [
    {
      "selector": "body"
    }
  ]
}' | jq .data[].results[].html > $TMP_HTML

#echo "wrote to $TMP_HTML"

# 294.34 kWh
ENERGY_TODAY=$(sed 's#^.*Energy today</div>##' "$TMP_HTML" | sed 's#<div[^>]*>##' | cut -c 1-100 | sed 's/<.*$//')
LIFETIME_ENERGY=$(sed 's#^.*Lifetime energy</div>##' "$TMP_HTML" | sed 's#<div[^>]*>##' | cut -c 1-100 | sed 's/<.*$//')

python3 $PROJECT_DIR/gen_solar_status_bmp.py --daily-output "$ENERGY_TODAY" --total-output "$LIFETIME_ENERGY"

$PROJECT_DIR/upload.sh

#rm "$TMP_HTML"
