source ~/.secrets/se.sh
curl -s -o - https://monitoringapi.solaredge.com/site/2764610/overview?api_key=${SOLAREDGE_API_KEY}
