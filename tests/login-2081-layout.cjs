const assert=require('node:assert/strict');
const puppeteer=require(process.env.PHC_PUPPETEER_PATH||'puppeteer');
const root=process.env.PHC_TEST_BASE||'http://127.0.0.1:8766/';
(async()=>{
 const browser=await puppeteer.launch({
  executablePath:process.env.PHC_CHROME_PATH||'C:/Program Files/Google/Chrome/Application/chrome.exe',
  headless:true,args:['--no-sandbox','--disable-gpu']
 });
 try{
  const page=await browser.newPage();
  const results=[];
  for(const [width,height] of [[320,568],[375,812],[390,844],[430,932],[768,1024],[1024,768],[1125,850],[1440,900],[2250,1700]]){
   await page.setViewport({width,height,deviceScaleFactor:width<500?3:1,isMobile:width<500,hasTouch:width<500});
   await page.goto(root,{waitUntil:'domcontentloaded',timeout:25000});
   await page.waitForSelector('#line-login-v201',{timeout:12000});
   const value=await page.evaluate(()=>{
    const get=sel=>{
     const el=document.querySelector(sel);if(!el)return null;
     const r=el.getBoundingClientRect(),css=getComputedStyle(el);
     return {left:Math.round(r.left),right:Math.round(r.right),top:Math.round(r.top),
      bottom:Math.round(r.bottom),width:Math.round(r.width),height:Math.round(r.height),
      visible:css.display!=='none'&&!el.hidden};
    };
    return {
     viewport:innerWidth,height:innerHeight,documentWidth:document.documentElement.scrollWidth,
     documentHeight:document.documentElement.scrollHeight,
     brand:get('.phc-login-brand'),card:get('#login-card'),footer:get('.phc-login-footer'),
     version:get('.login-version'),line:get('.line-login-v201'),logo:get('#cloud-login-logo'),
     photo:getComputedStyle(document.body).backgroundImage.includes('phc-login-community.webp'),
     bodyStyle:getComputedStyle(document.body).backgroundSize,
     mainForm:get('#login-form'),
     lineButtons:[...document.querySelectorAll('#line-login-v201 button,#line-login-v201 a')].map(e=>({
      id:e.id,text:e.textContent.slice(0,30),width:Math.round(e.getBoundingClientRect().width),
      top:Math.round(e.getBoundingClientRect().top)})),
    };
   });
   results.push({width,height,...value});
   assert.equal(value.photo,true,'building photo on login '+width);
   assert.ok(value.brand?.visible&&value.card?.visible&&value.footer?.visible,'three structural sections '+width);
   assert.ok(value.logo?.visible,'municipal logo '+width);
   assert.ok(value.documentWidth<=width+2,'no horizontal overflow '+width);
   assert.ok(value.card.left>=-1&&value.card.right<=width+1,'card within viewport '+width);
   assert.ok(value.brand.left>=-1&&value.brand.right<=width+1,'brand within viewport '+width);
   assert.ok(value.version?.visible,'version badge '+width);
   assert.ok(value.footer.top>=value.card.bottom-1,'footer after card '+width);
   assert.ok(value.line?.visible,'LINE inside card '+width);
   if(width>=1024)assert.ok(value.card.width>=650,'desktop card not tiny '+width);
  }
  console.log(JSON.stringify({result:'PASS',results}));
 }finally{await browser.close();}
})().catch(e=>{console.error(e.stack||e);process.exitCode=1});
