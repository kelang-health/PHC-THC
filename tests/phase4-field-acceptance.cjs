const assert=require('node:assert/strict');
const fs=require('node:fs');
const puppeteer=require(process.env.PHC_PUPPETEER_PATH||'puppeteer');
const base=process.env.PHC_TEST_BASE||'http://127.0.0.1:8766/';
(async()=>{
 const browser=await puppeteer.launch({executablePath:process.env.PHC_CHROME_PATH||'C:/Program Files/Google/Chrome/Application/chrome.exe',headless:true,args:['--no-sandbox','--disable-gpu']});
 try{
  const page=await browser.newPage();
  await page.setViewport({width:390,height:844,deviceScaleFactor:3,isMobile:true,hasTouch:true});
  await page.goto(base,{waitUntil:'domcontentloaded',timeout:25000});
  await new Promise(r=>setTimeout(r,1800));
  const nav=await page.evaluate(()=>{
   document.querySelector('#login-card').hidden=true;document.querySelector('#portal').hidden=false;
   document.querySelectorAll('#portal-nav [data-portal-view]').forEach(b=>b.hidden=!['overview','communities','houses','health','work'].includes(b.dataset.portalView));
   const n=document.querySelector('#portal-nav'),buttons=[...n.querySelectorAll('[data-portal-view]')].filter(b=>!b.hidden);
   return {navHeight:n.getBoundingClientRect().height,buttonHeights:buttons.map(b=>b.getBoundingClientRect().height),
    names:buttons.map(b=>b.querySelector('.portal-nav-mobile-label')?.textContent),overflow:document.documentElement.scrollWidth>innerWidth+2};
  });
  assert.equal(nav.names.length,5);assert.equal(nav.overflow,false);assert.ok(nav.navHeight<=72,'mobile nav is compact');
  assert.ok(nav.buttonHeights.every(x=>x<=61),'mobile buttons stay compact');
  const src=fs.readFileSync('D:/Github/osm-phc-phase2/volunteer-profile-registry-v1825.mjs','utf8');
  assert.ok(src.includes('ประวัติการอบรม ▾'),'work training shortcut is explicit');
  assert.ok(src.includes('โปรไฟล์ / การอบรม ▾'),'user house profile includes training hint');
  assert.ok(src.includes('.vself25-more{display:block;grid-column:2'),'training shortcut remains visible at <=390px');
  console.log(JSON.stringify({result:'PASS',nav}));
 }finally{await browser.close();}
})().catch(e=>{console.error(e.stack||e);process.exitCode=1;});
