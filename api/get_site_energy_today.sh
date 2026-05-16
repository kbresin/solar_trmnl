source ~/.secrets/se.sh

YYYYMMDD=$(date '+%Y-%m-%d')

curl -s -o - "https://monitoringapi.solaredge.com/site/${SOLAREDGE_SITE_ID}/timeFrameEnergy?api_key=${SOLAREDGE_API_KEY}&startDate=${YYYYMMDD}&endDate=${YYYYMMDD}"

