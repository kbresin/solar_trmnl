source ~/.secrets/se.sh
curl -o - "https://monitoringapi.solaredge.com/site/${SOLAREDGE_SITE_ID}/energy?api_key=${SOLAREDGE_API_KEY}"
