const assert=require('node:assert/strict');
const puppeteer=require(process.env.PHC_PUPPETEER_PATH||'puppeteer');
const root=process.env.PHC_TEST_BASE||'http://127.0.0.1:8766/';
(async()=>{
 const browser=await puppeteer.launch({
   executablePath:process.env.PHC_CHROME_PATH||'C:/Program Files/Google/Chrome/Application/chrome.exe',
   headless:true,args:['--no-sandbox','--disable-gpu'],
 });
 try {
  const page=await browser.newPage();
  const results=[];
  for(const [width,height] of [[320,568],[390,844],[430,932],[1024,768],[1440,900]]){
   await page.setViewport({width,height,deviceScaleFactor:width<500?3:1,isMobile:width<500,hasTouch:width<500});
   await page.goto(root,{waitUntil:'domcontentloaded',timeout:25000});
   await page.waitForSelector('#line-login-v201',{timeout:12000});
   const r=await page.evaluate(()=>{
     const host=document.querySelector('#line-login-v201');
     // CSS-only fixture mirrors existing LINE module DOM; it does not invoke OAuth.
     host.innerHTML='<p class="line-login-or">หรือ</p>'+
       '<div class="line-login-ready"><a class="line-login-button" id="line-login-start">เปิดแอป LINE</a>'+
       '<a class="line-login-web" id="line-login-web">LINE ผ่านเว็บ</a>'+
       '<button type="button" class="line-login-legacy" id="line-login-legacy">LINE เดิม (LINE OA)</button>'+
       '<p class="line-login-browser-note">หากแอป LINE ไม่เปิด ให้เลือก LINE ผ่านเว็บ หรือ LINE เดิม</p></div>'+
       '<p class="line-login-help">เลือกวิธี LINE ที่สะดวกกับอุปกรณ์</p>';
     const rect=sel=>{const q=document.querySelector(sel).getBoundingClientRect();return {
      left:q.left,right:q.right,top:q.top,bottom:q.bottom,width:q.width,height:q.height,
     };};
     const image=document.querySelector('#cloud-login-logo');
     return {
      viewport:innerWidth,viewportHeight:innerHeight,docWidth:document.documentElement.scrollWidth,
      docHeight:document.documentElement.scrollHeight,
      card:rect('#login-card'),footer:rect('.phc-login-footer'),
      usernameIcon:!!document.querySelector('label:has(#login-name) .phc-login-field-icon'),
      passwordIcon:!!document.querySelector('label:has(#login-password) .phc-login-field-icon'),
      logoId:image.id,
      versions:document.querySelectorAll('.login-version').length,
      version:document.querySelector('.login-version').textContent,
      a:rect('.line-login-button'),b:rect('.line-login-web'),c:rect('.line-login-legacy'),
      lineCount:document.querySelectorAll('#line-login-v201 .line-login-ready>a,#line-login-v201 .line-login-ready>button').length,
      linked:document.querySelector('link[href*="login-theme-v2081.css"]')!==null,
      noOldCss:!document.querySelector('link[href*="2.0.80-login-layout"]'),
     };
   });
   assert.equal(r.docWidth,r.viewport,'no horizontal scrolling '+width);
   assert.equal(r.lineCount,3,'all three existing LINE choices can be displayed '+width);
   assert.equal(r.usernameIcon&&r.passwordIcon,true,'input icons visible '+width);
   assert.equal(r.logoId,'cloud-login-logo');
   assert.equal(r.versions,1);
   assert.equal(r.linked&&r.noOldCss,true);
   assert.ok(r.card.right<=r.viewport+1&&r.card.left>=-1,'login card fits '+width);
   assert.ok(r.b.width>=44&&r.c.width>=44,'secondary LINE buttons accessible '+width);
   assert.ok(Math.abs(r.b.top-r.c.top)<3 || width>=1024,'mobile fallback buttons use one row '+width);
   assert.ok(r.footer.top>=r.card.bottom,'footer does not overlap login '+width);
   if(width===390||width===1440)assert.ok(r.docHeight<=r.viewportHeight+5,
       'complete mock LINE login and footer fit in typical viewport '+width);
   results.push({width,height,cardHeight:Math.round(r.card.height),
     footerTop:Math.round(r.footer.top),docHeight:r.docHeight,version:r.version});
  }
  const toggles=await page.evaluate(()=>{
    const field=document.querySelector('#login-password'),button=document.querySelector('#toggle-login-password');
    const before=field.type;button.click();const after=field.type;button.click();const returned=field.type;
    const staff=document.querySelector('[data-login-mode="staff"]');
    staff.click();const staffActive=staff.classList.contains('active');
    const user=document.querySelector('[data-login-mode="user"]');
    user.click();return {before,after,returned,staffActive,userActive:user.classList.contains('active')};
  });
  assert.deepEqual(toggles,{before:'password',after:'text',returned:'password',staffActive:true,userActive:true});
  console.log(JSON.stringify({result:'PASS',results,toggles}));
 }finally{await browser.close();}
})().catch(e=>{console.error(e.stack||e);process.exitCode=1});
