const assert=require('node:assert/strict');
const puppeteer=require(process.env.PHC_PUPPETEER_PATH||'puppeteer');
const fs=require('node:fs');
const path=require('node:path');
const base=process.env.PHC_TEST_BASE||'http://127.0.0.1:8766/';
(async()=>{
 const browser=await puppeteer.launch({
  executablePath:process.env.PHC_CHROME_PATH||'C:/Program Files/Google/Chrome/Application/chrome.exe',
  headless:true,args:['--no-sandbox','--disable-gpu']
 });
 try{
  const page=await browser.newPage();
  const checks=[];
  for(const [width,height] of [[320,568],[375,812],[390,844],[430,932],[768,1024],[1024,768],[1125,850],[1440,900]]){
   await page.setViewport({width,height,deviceScaleFactor:3,isMobile:width<=430,hasTouch:width<=430});
   await page.goto(base,{waitUntil:'domcontentloaded',timeout:25000});
   await new Promise(resolve=>setTimeout(resolve,900));
   const r=await page.evaluate(()=>{
    const card=document.querySelector('#login-card'),brand=document.querySelector('.phc-login-brand');
    const f=document.querySelector('#login-form');
    const rec=e=>{const r=e.getBoundingClientRect();return {left:r.left,right:r.right,top:r.top,bottom:r.bottom,height:r.height,width:r.width};};
    const image=new Image();image.src='/phc-login-community.webp';
    const brandRect=rec(brand),cardRect=rec(card);
    return {
     viewport:innerWidth,documentWidth:document.documentElement.scrollWidth,
     loginVisible:!card.hidden && getComputedStyle(card).display!=='none',
     brandVisible:getComputedStyle(brand).display!=='none',
     landscapeAbsent:!document.querySelector('.phc-login-landscape'),
     backgroundSizing:getComputedStyle(document.body).backgroundSize,
     lineReadyButtons:card.querySelectorAll('.line-login-ready .line-login-button,.line-login-ready .line-login-web,.line-login-ready .line-login-legacy').length,
     brandRect,cardRect,
     photoBackground:getComputedStyle(document.body).backgroundImage.includes('phc-login-community.webp'),
     brandText:brand.textContent,loginTitle:card.querySelector('h2').textContent,
     loginMethod:f.method,formId:f.id,formInputs:[...f.querySelectorAll('input')].map(x=>({id:x.id,type:x.type,name:x.name,autocomplete:x.autocomplete})),
     staffMode:!!card.querySelector('[data-login-mode="staff"]'),
     submit:!!card.querySelector('.login-submit'),
     passwordToggle:!!card.querySelector('#toggle-login-password'),
     lineInjected:!!card.querySelector('#line-login-v201'),
     logo:!!brand.querySelector('#cloud-login-logo'),
     topbarHidden:getComputedStyle(document.querySelector('.topbar')).display==='none',
    };
   });
   assert.equal(r.loginVisible,true,'login visible '+width);
   assert.equal(r.brandVisible,true,'brand visible '+width);
   assert.equal(r.landscapeAbsent,true,'no separate landscape panel '+width);
   assert.ok(r.backgroundSizing.includes('cover, cover, cover'),'photo covers viewport '+width);
   assert.ok(Math.abs(r.brandRect.bottom-r.cardRect.top)<3,'header and card form one panel '+width);
   if(width>=1024)assert.ok(r.cardRect.width>=550,'desktop login card not miniature '+width);
   assert.equal(r.photoBackground,true,'photo background '+width);
   assert.equal(r.topbarHidden,true,'topbar hidden '+width);
   assert.equal(r.logo,true,'brand logo '+width);
   assert.equal(r.staffMode,true,'existing login mode '+width);
   assert.equal(r.submit,true,'existing submit '+width);
   assert.equal(r.passwordToggle,true,'existing password toggle '+width);
   assert.equal(r.formInputs.find(x=>x.id==='login-name')?.type,'tel');
   assert.equal(r.formInputs.find(x=>x.id==='login-password')?.type,'password');
   assert.ok(r.documentWidth<=r.viewport+2,'no horizontal overflow '+width);
   assert.ok(r.cardRect.left>=-1 && r.cardRect.right<=r.viewport+1,'card inside viewport '+width);
   assert.ok(r.brandRect.left>=-1 && r.brandRect.right<=r.viewport+1,'brand inside viewport '+width);
   checks.push({width,height,cardHeight:Math.round(r.cardRect.height),cardWidth:Math.round(r.cardRect.width),cardTop:Math.round(r.cardRect.top),brandHeight:Math.round(r.brandRect.height),lineInjected:r.lineInjected,lineButtons:r.lineReadyButtons});
  }
  // The three existing mobile LINE methods remain present, with secondary options side by side.
  await page.setViewport({width:390,height:844,deviceScaleFactor:3,isMobile:true,hasTouch:true});
  await page.goto(base,{waitUntil:'domcontentloaded',timeout:25000});
  await page.waitForSelector('#line-login-v201',{timeout:10000});
  const lineLayout=await page.evaluate(()=>{
    const host=document.querySelector('#line-login-v201');
    const fixture=document.createElement('div');fixture.className='line-login-ready';
    fixture.innerHTML='<a class="line-login-button">??????? LINE</a>'+
      '<a class="line-login-web">LINE ????????</a>'+
      '<button type="button" class="line-login-legacy">LINE ???? (LINE OA)</button>'+
      '<p class="line-login-browser-note">??????????????????????</p>';
    host.appendChild(fixture);
    const rect=selector=>fixture.querySelector(selector).getBoundingClientRect();
    const first=rect('.line-login-button'),web=rect('.line-login-web'),legacy=rect('.line-login-legacy');
    fixture.remove();
    return {primaryWidth:Math.round(first.width),webWidth:Math.round(web.width),
      legacyWidth:Math.round(legacy.width),secondarySameRow:Math.abs(web.top-legacy.top)<2,
      buttonHeight:Math.round(web.height)};
  });
  assert.equal(lineLayout.secondarySameRow,true,'secondary LINE options appear on same row');
  assert.ok(lineLayout.primaryWidth>lineLayout.webWidth+40,'main LINE method spans full width');
  assert.ok(lineLayout.buttonHeight>=44,'LINE buttons remain touch accessible');
  // At an unusually wide CSS viewport (e.g. browser zoomed out), the desktop card grows.
  await page.setViewport({width:2250,height:1700,deviceScaleFactor:1,isMobile:false,hasTouch:false});
  const zoomed=await page.evaluate(()=>document.querySelector('#login-card').getBoundingClientRect().width);
  assert.ok(zoomed>=900,'desktop layout avoids tiny card at wide CSS viewports');
  await page.setViewport({width:390,height:844,deviceScaleFactor:3,isMobile:true,hasTouch:true});
  await page.goto(base,{waitUntil:'domcontentloaded',timeout:25000});
  await page.waitForSelector('#line-login-start',{timeout:10000});
  // Existing auth inputs, mode selectors and visibility handlers remain functional.
  const controls=await page.evaluate(()=>{
   const pass=document.querySelector('#login-password');
   const toggle=document.querySelector('#toggle-login-password');
   const original=pass.type;
   toggle.click();const visible=pass.type;
   toggle.click();const restored=pass.type;
   const staff=document.querySelector('[data-login-mode="staff"]');
   staff.click();
   const staffSelected=staff.classList.contains('active')&&staff.getAttribute('aria-pressed')==='true';
   const user=document.querySelector('[data-login-mode="user"]');
   user.click();
   const userSelected=user.classList.contains('active')&&user.getAttribute('aria-pressed')==='true';
   return {original,visible,restored,staffSelected,userSelected,
    lineButtonPresent:!!document.querySelector('#line-login-start')};
  });
  assert.equal(controls.original,'password');
  assert.equal(controls.visible,'text');
  assert.equal(controls.restored,'password');
  assert.equal(controls.staffSelected,true);
  assert.equal(controls.userSelected,true);
  assert.equal(controls.lineButtonPresent,true);
  await page.evaluate(()=>{
   document.querySelector('#login-card').hidden=true;
   document.querySelector('#portal').hidden=false;
  });
  const signedIn=await page.evaluate(()=>({
   brandHidden:getComputedStyle(document.querySelector('.phc-login-brand')).display==='none',
   landscapeAbsent:!document.querySelector('.phc-login-landscape'),
   hasPhotoBackground:getComputedStyle(document.body).backgroundImage.includes('phc-login-community.webp'),
  }));
  assert.deepEqual(signedIn,{brandHidden:true,landscapeAbsent:true,hasPhotoBackground:false});
  const asset=fs.statSync(path.join('D:/Github/osm-phc-phase2','phc-login-community.webp')).size;
  assert.ok(asset<10000,'building background under 10 KB');
  const fallback=await browser.newPage();
  await fallback.setRequestInterception(true);
  fallback.on('request',request=>{
   if(request.url().includes('phc-login-community.webp'))request.abort();
   else request.continue();
  });
  await fallback.setViewport({width:390,height:844,isMobile:true,hasTouch:true,deviceScaleFactor:3});
  await fallback.goto(base+'?no-photo=1',{waitUntil:'domcontentloaded',timeout:25000});
  const off=await fallback.evaluate(()=>({
   usable:!document.querySelector('#login-card').hidden && !!document.querySelector('#login-submit, .login-submit'),
   hasGradient:getComputedStyle(document.body).backgroundImage.includes('linear-gradient'),
  }));
  assert.equal(off.usable,true,'login remains usable without photo');
  assert.equal(off.hasGradient,true,'fallback gradient remains');
  await fallback.close();
  console.log(JSON.stringify({result:'PASS',photoBytes:asset,checks,lineLayout,zoomed,controls,signedIn,fallback:off}));
 }finally{await browser.close();}
})().catch(e=>{console.error(e.stack||e);process.exitCode=1});
