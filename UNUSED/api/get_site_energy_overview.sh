source ~/.secrets/se.sh
curl -s -o - "https://monitoringapi.solaredge.com/site/${SOLAREDGE_SITE_ID}/overview?api_key=${SOLAREDGE_API_KEY}"
