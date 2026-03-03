#python3 gen_solar_status_bmp.py --daily-output '200.64 kWh' --lifetime-output '262.94 MWh'

TMP_HTML=angry_debugging.html

curl -s -o - \
  -X POST 'http://localhost:3000/function?stealth=true' \
  -H 'Content-Type: application/json' \
  -d "{
    \"code\": \"async ({ page }) => { await page.goto('https://monitoringpublic.solaredge.com/solaredge-web/p/site/public?name=Gethsemane%20Lutheran%20Church', { waitUntil: 'load', timeout: 90000 }); await new Promise(r => setTimeout(r, 10000)); return { data: await page.content(), contentType: 'text/html' }; }\"
  }" > "$TMP_HTML"

