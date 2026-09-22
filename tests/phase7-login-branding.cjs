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
  for(const [width,height] of [[320,568],[375,812],[390,844],[430,932],[768,1024],[1024,768]]){
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
     landscapeVisible:getComputedStyle(document.querySelector('.phc-login-landscape')).display!=='none',
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
   assert.equal(r.landscapeVisible,true,'landscape visible '+width);
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
   checks.push({width,height,cardHeight:Math.round(r.cardRect.height),cardTop:Math.round(r.cardRect.top),brandHeight:Math.round(r.brandRect.height),lineInjected:r.lineInjected});
  }
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
   landscapeHidden:getComputedStyle(document.querySelector('.phc-login-landscape')).display==='none',
   hasPhotoBackground:getComputedStyle(document.body).backgroundImage.includes('phc-login-community.webp'),
  }));
  assert.deepEqual(signedIn,{brandHidden:true,landscapeHidden:true,hasPhotoBackground:false});
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
  console.log(JSON.stringify({result:'PASS',photoBytes:asset,checks,controls,signedIn,fallback:off}));
 }finally{await browser.close();}
})().catch(e=>{console.error(e.stack||e);process.exitCode=1});
