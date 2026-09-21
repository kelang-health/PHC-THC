const assert = require('node:assert/strict');
const puppeteer = require(process.env.PHC_PUPPETEER_PATH || 'puppeteer');
const base = process.env.PHC_TEST_BASE || 'http://127.0.0.1:8766/';
(async () => {
 const browser = await puppeteer.launch({executablePath:process.env.PHC_CHROME_PATH || 'C:/Program Files/Google/Chrome/Application/chrome.exe',headless:true,args:['--no-sandbox','--disable-gpu']});
 try {
  const page = await browser.newPage();
  await page.goto(base,{waitUntil:'domcontentloaded',timeout:25000});
  await new Promise(resolve=>setTimeout(resolve,2500));
  await page.evaluate(() => {
   document.querySelector('#login-card').hidden=true;
   document.querySelector('#portal').hidden=false;
   document.querySelectorAll('#portal-nav [data-portal-view]').forEach(b=>{b.hidden= !['overview','communities','houses','health','work'].includes(b.dataset.portalView);});
  });
  const checks=[];
  for (const width of [320,375,390,430,768,1024]) {
   await page.setViewport({width,height:844,deviceScaleFactor:3,isMobile:width<=430,hasTouch:width<=430});
   await page.evaluate(() => {document.querySelector('#portal').hidden=false;document.querySelector('#login-card').hidden=true;document.querySelectorAll('#portal-nav [data-portal-view]').forEach(b=>b.hidden=!['overview','communities','houses','health','work'].includes(b.dataset.portalView));});
   const r=await page.evaluate(() => {
    const bar=document.querySelector('#portal-nav');
    const buttons=[...bar.querySelectorAll('[data-portal-view]')].filter(b=>getComputedStyle(b).display!=='none');
    const rects=buttons.map(b=>b.getBoundingClientRect());
    const labels=buttons.map(b=>b.querySelector('.portal-nav-mobile-label'));
    return {innerWidth,media:matchMedia('(max-width:900px)').matches,barPosition:getComputedStyle(bar).position,bodyScroll:document.documentElement.scrollWidth>innerWidth+2,count:buttons.length,names:buttons.map(b=>b.dataset.portalView),
     widths:rects.map(x=>x.width),overlap:rects.some((r,i)=>i&&((matchMedia('(max-width:900px)').matches&&r.left<rects[i-1].right-1)||(!matchMedia('(max-width:900px)').matches&&r.top<rects[i-1].bottom-1))),
     labels:labels.map(x=>({text:x.textContent,scroll:x.scrollWidth,client:x.clientWidth,display:getComputedStyle(x).display})),
     barBottom:Math.round(bar.getBoundingClientRect().bottom),viewport:innerHeight};
   });   assert.equal(r.count,5,'five role-visible menu items: '+JSON.stringify(r));
   assert.equal(r.overlap,false,'navigation items do not overlap: '+JSON.stringify(r));
   assert.equal(r.bodyScroll,false,'no unintended document horizontal overflow');
   if(width<=900){assert.ok(r.labels.every(x=>x.display!=='none'&&x.scroll<=x.client+1),'mobile labels fit');}
   checks.push({width,overlap:r.overlap,overflow:r.bodyScroll,mobileLabelFit:width>900||r.labels.every(x=>x.scroll<=x.client+1)});
  }
  const helper=await page.evaluate(async()=>{
   const {mergeHouseholdCards,houseCards,volunteerCards,selectCommunityView}=await import('./community-workspace-v2074.mjs');
   const base=[{id:'house-a',hcode:'H1',house_no:'1',moo:'7',community:'TEST',volunteer_pid:null,review_required:true,review_reason:'รอตรวจพิกัด'},
    {id:'house-b',hcode:'H2',house_no:'2',moo:'7',community:'TEST',volunteer_pid:55,review_required:false}];
   const combined=mergeHouseholdCards(base,[{id:'house-a',member_count:3,health_access:true},{id:'house-b',member_count:4,health_access:true}]);
   const host=document.querySelector('#community-workspace');
   host.hidden=false;host.innerHTML='<div class="community-actions"><button data-community-action="review">ตรวจข้อมูล</button><button data-community-action="volunteers">อสม.</button></div>'+
    '<section class="community-view" data-community-view="review" hidden>'+houseCards(combined.filter(h=>h.review_required))+'</section>'+
    '<section class="community-view" data-community-view="volunteers" hidden>'+volunteerCards([{source_pid:55,display_name:'อสม.ทดสอบ',house_count:1,community:'TEST'}],combined)+'</section>';
   selectCommunityView(host,'review',{scroll:false});const reviewVisible=!host.querySelector('[data-community-view="review"]').hidden;
   selectCommunityView(host,'volunteers',{scroll:false});const volVisible=!host.querySelector('[data-community-view="volunteers"]').hidden;
   return {reviewVisible,volVisible,reviewCount:combined.filter(h=>h.review_required).length,
     volCount:host.querySelectorAll('[data-community-volunteer]').length,populationShown:host.textContent.includes('4 คน'),
     uuidMatch:combined[0].member_count===3 && combined[1].member_count===4};
  });
  assert.deepEqual(helper,{reviewVisible:true,volVisible:true,reviewCount:1,volCount:1,populationShown:true,uuidMatch:true});
  const perf=await page.evaluate(async()=>{
   const {houseCards,volunteerCards,mergeHouseholdCards}=await import('./community-workspace-v2074.mjs?v=2.0.75&p=2075');
   const houses=Array.from({length:126},(_,i)=>({id:'house-'+i,hcode:'H'+i,house_no:String(i+1),moo:'7',community:'TEST',volunteer_pid:i%5===0?null:i%20+1,review_required:i%7===0}));
   const data=mergeHouseholdCards(houses,houses.map(h=>({id:h.id,health_access:true,member_count:3})));
   const t=performance.now();
   const html=houseCards(data);
   const holder=document.createElement('div');holder.innerHTML=html;
   const houseMs=Math.round((performance.now()-t)*100)/100;
   const volunteers=Array.from({length:20},(_,i)=>({source_pid:i+1,display_name:'Volunteer '+i,house_count:5,community:'TEST'}));
   const v=performance.now();const vh=volunteerCards(volunteers,data);
   const vholder=document.createElement('div');vholder.innerHTML=vh;
   const volunteerMs=Math.round((performance.now()-v)*100)/100;
   const zero=houseCards([{...houses[0],member_count:0,health_access:true}]);
   return {houseMs,volunteerMs,houseCount:holder.querySelectorAll('.community-record-card').length,
    volunteerCount:vholder.querySelectorAll('[data-community-volunteer]').length,zeroExplicit:zero.includes('ไม่ได้หมายความว่าบ้านไม่มีผู้อยู่อาศัย')};
  });
  assert.equal(perf.houseCount,126);
  assert.equal(perf.volunteerCount,20);
  assert.equal(perf.zeroExplicit,true);  const roles={};
  await page.setViewport({width:390,height:844,deviceScaleFactor:3,isMobile:true,hasTouch:true});
  for(const role of ['admin','staff','user']){
    const check=await page.evaluate(role=>{
      document.querySelector('#portal').hidden=false;
      const buttons=[...document.querySelectorAll('#portal-nav [data-portal-view]')];
      buttons.forEach(button=>button.hidden=!button.dataset.roles.split(' ').includes(role));
      return buttons.filter(button=>!button.hidden).map(button=>button.dataset.portalView);
    },role);
    assert.equal(check.length,5,role+' has five navigation items');
    assert.equal(check.includes('volunteers'),role==='admin',role+' volunteer navigation scope');
    assert.equal(check.includes('houses'),role!=='admin',role+' household navigation scope');
    roles[role]=check;
  }  console.log(JSON.stringify({result:'PASS',viewportChecks:checks,communityView:helper,perf,roles}));
 } finally {await browser.close();}
})().catch(error=>{console.error(error.stack||error);process.exitCode=1;});
