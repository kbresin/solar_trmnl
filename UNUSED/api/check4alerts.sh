#!/bin/bash

source ~/.secrets/se.sh

# Configuration
API_KEY="${SOLAREDGE_API_KEY}"
BASE_URL="https://monitoringapi.solaredge.com"
SITE_ID="${SOLAREDGE_SITE_ID}"

CACHE_DIR="${HOME}/.cache/solar_trmnl"
mkdir -p "$CACHE_DIR"
CACHE_FILE="${CACHE_DIR}/inverters.cache"

# Time window: Last 24 hours
# Format: YYYY-MM-DD hh:mm:ss
END_TIME=$(date +"%Y-%m-%d %H:%M:%S")
START_TIME=$(date -d "24 hours ago" +"%Y-%m-%d %H:%M:%S")

echo "==============================================="
echo "SITE $SITE_ID: PANEL HEALTH REPORT"
echo "Location: $SCRIPT_DIR"
echo "==============================================="

# 1. Handle Inverter SN Caching
if [ -f "$CACHE_FILE" ]; then
    echo "[INFO] Using cached serials from: $CACHE_FILE"
    INVERTERS=$(cat "$CACHE_FILE")
else
    echo "[INFO] Cache missing. Fetching inventory..."
    # The inventory endpoint lists all equipment on site.
    INVENTORY=$(curl -s -X GET "${BASE_URL}/site/${SITE_ID}/inventory?api_key=${API_KEY}")
    INVERTERS=$(echo "$INVENTORY" | jq -r '.Inventory.inverters[].SN')
    
    if [ -n "$INVERTERS" ]; then
        echo "$INVERTERS" > "$CACHE_FILE"
        echo "[INFO] Serial numbers saved to $CACHE_FILE."
    else
        echo "[ERROR] Could not fetch inventory. Verify API key and Site ID."
        exit 1
    fi
fi

# 2. Site-Level Alerts
# The details endpoint returns alert quantity and severity for the account.
echo -e "\n[1/2] Checking Site Alerts..."
DETAILS=$(curl -s -X GET "${BASE_URL}/site/${SITE_ID}/details?api_key=${API_KEY}")
echo "$DETAILS" | jq -r '.details | "Alerts: \(.alertQuantity) | Max Severity: \(.alertSeverity)"'

# 3. Panel-Level DC Analysis
echo -e "\n[2/2] Analyzing DC Production (4 Inverters)..."
for SN in $INVERTERS; do
    echo "--- Inverter: $SN ---"
    
    # Technical data provides DC voltage and operating modes[cite: 1].
    # Comparing DC voltage across your 4 inverters helps identify dead panels[cite: 1].
    TECH_DATA=$(curl -s -G "${BASE_URL}/equipment/${SITE_ID}/${SN}/data" \
        --data-urlencode "startTime=$START_TIME" \
        --data-urlencode "endTime=$END_TIME" \
        --data-urlencode "api_key=$API_KEY")

    # Filter for Fault modes or low DC voltage[cite: 1].
    # Faults like 'LOCKED_INV_TRIP' or 'FAULT' indicate hardware failures[cite: 1].
    echo "$TECH_DATA" | jq -r '.data.telemetries[] | 
        select(.inverterMode == "FAULT" or (.dcVoltage != null and .dcVoltage < 50)) |
        "ALERT: [\(.date)] Mode: \(.inverterMode) | DC: \(.dcVoltage)V"'

    # Display the most recent data point[cite: 1].
    echo "$TECH_DATA" | jq -r '.data.telemetries[-1] | "Latest Status: \(.date) | Mode: \(.inverterMode) | DC: \(.dcVoltage)V"'
done
