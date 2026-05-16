#!/bin/bash

set -e

source ~/.secrets/se.sh

# Configuration
API_KEY="${SOLAREDGE_API_KEY}"
BASE_URL="https://monitoringapi.solaredge.com"
SITE_ID="2764610"

# Time setup for the last 24 hours (Formatted: YYYY-MM-DD hh:mm:ss)
END_TIME=$(date +"%Y-%m-%d %H:%M:%S")
START_TIME=$(date --date="24 hours ago" +"%Y-%m-%d %H:%M:%S")

echo "-----------------------------------------------"
echo "SYSTEM HEALTH & PERFORMANCE REPORT"
echo "Period: $START_TIME to $END_TIME"
echo "-----------------------------------------------"

# 1. Check for Site Alerts
# This checks the number and severity of open issues.
echo "[1/3] Checking Site Alerts (Account Key Required)..."
DETAILS=$(curl -s -X GET "${BASE_URL}/site/${SITE_ID}/details?api_key=${API_KEY}")
ALERTS=$(echo "$DETAILS" | jq -r '.details | "Alerts: \(.alertQuantity) | Max Severity: \(.alertSeverity)"')
echo "Status: $ALERTS"

echo "-----------------------------------------------"

# 2. Identify Inverters
# We need the Serial Numbers to query technical data.
INVERTER_SNS=$(curl -s -X GET "${BASE_URL}/site/${SITE_ID}/inventory?api_key=${API_KEY}" | jq -r '.Inventory.inverters[].SN')

# 3. Panel-Level Technical Data
# This endpoint provides detailed performance metrics including DC Voltage and Temperature.
echo "[3/3] Analyzing Inverter Technical Data (Last 24h)..."
for SN in $INVERTER_SNS; do
    echo "Inverter: $SN"
    
    # Fetching telemetries for the specific inverter.
    DATA=$(curl -s -G "${BASE_URL}/equipment/${SITE_ID}/${SN}/data" \
        --data-urlencode "startTime=$START_TIME" \
        --data-urlencode "endTime=$END_TIME" \
        --data-urlencode "api_key=$API_KEY")

    # Display key production indicators to spot drops[cite: 1].
    echo "$DATA" | jq -r '.data.telemetries[] | 
        "[\(.date)] DC Volts: \(.dcVoltage)V | Temp: \(.temperature)°C | Mode: \(.inverterMode)"' | tail -n 5
    echo "---"
done

