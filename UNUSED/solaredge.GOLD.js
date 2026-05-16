module.exports = async ({ page }) => {
  await page.setUserAgent('Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/121.0.0.0 Safari/537.36');

  try {
    await page.goto('https://monitoringpublic.solaredge.com/solaredge-web/p/site/public?name=Gethsemane%20Lutheran%20Church', {
      waitUntil: 'domcontentloaded',
      timeout: 30000 
    });

    // Static wait for the JS to populate the data
    await new Promise(r => setTimeout(r, 20000));

    // Equivalent to "elements": [{ "selector": "body" }]
    // This grabs the HTML inside the body tag
    const bodyHtml = await page.$eval('body', el => el.innerHTML);

    return { 
      data: bodyHtml, 
      type: 'text/html' 
    };
  } catch (err) {
    return { data: 'ERROR: ' + err.message, type: 'text/plain' };
  }
};
