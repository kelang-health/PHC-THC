const fs=require('fs'),path=require('path'),assert=require('node:assert/strict');
const {chromium}=require('C:/Users/acer/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules/playwright');
const read=n=>fs.readFileSync(path.join(__dirname,'..',n),'utf8');
const moduleBody=n=>read(n).replace(/^import[^\n]*\n/,'').replaceAll('export ','');
const runtime=read('shared-runtime-v2035.mjs');
const cacheCode=runtime.slice(runtime.indexOf('export async function sharedCall'),runtime.indexOf('export function sharedDiagnostics')).replaceAll('export ','');
const fixture=[{id:'care',house_no:'1',moo:'7',community:'หนองวัวเฒ่า',house_group:'care',target_count:2,type2_count:0,reason:'มีเป้าหมาย'},
 {id:'review',house_no:'2',moo:'7',community:'หนองวัวเฒ่า',house_group:'review',target_count:0,type2_count:0,reason:'ตรวจทะเบียน',review:{id:'review',house_no:'2',moo:'7',community:'หนองวัวเฒ่า',needs_id11:true,can_edit:true}}];
(async()=>{const browser=await chromium.launch({channel:'msedge',headless:true});try{
 const page=await browser.newPage({viewport:{width:390,height:663}}),errors=[],pending=[];
 page.on('pageerror',e=>errors.push(e.message));
 await page.route('http://fixture.test/**',async route=>{
  if(route.request().url().includes('/rest/v1/rpc/house_groups_v2225')){pending.push(route);return;}
  await route.fulfill({contentType:'text/html',body:'<html data-auth-view="portal"><head><meta name="phc-release" content="2.0.184"></head><body><nav id="portal-nav"><button data-portal-view="overview">Overview</button><button data-portal-view="houses">Houses</button></nav><section data-portal-panel="overview"><div id="stats"><b>Ready</b></div></section><section data-portal-panel="houses" data-house-groups-mode="grouped" hidden><div class="myh-card">Legacy card</div><table id="my-house-body"><tr><td>Legacy placeholder</td></tr></table></section></body></html>'});
 });
 await page.goto('http://fixture.test/?perf=1');
 await page.addScriptTag({content:`(()=>{const state={cache:new Map(),inflight:new Map()};${cacheCode}
 Object.assign(window,{sharedCall,invalidateShared,bindPortalActivation,testExpire:()=>{for(const row of state.cache.values())row.expires=0;}});})();
 window.testCalls=[];window.testProfile={user_id:'fixture-user',role:'user',active:true};
 window.testClient={auth:{onAuthStateChange(){}},rpc:async(name)=>{testCalls.push(name);if(name==='house_groups_v2225')return (await fetch('/rest/v1/rpc/'+name)).json();if(name==='house_registration_review_cards_v2202')return {data:${JSON.stringify(fixture.filter(r=>r.review).map(r=>r.review))}};throw Error(name);}};
 window.getSharedSupabase=async()=>testClient;window.getSharedProfile=async()=>testProfile;
 document.querySelectorAll('[data-portal-view]').forEach(b=>b.onclick=()=>{document.querySelectorAll('[data-portal-panel]').forEach(p=>p.hidden=p.dataset.portalPanel!==b.dataset.portalView);document.dispatchEvent(new CustomEvent('phc:portal-view-changed',{detail:{view:b.dataset.portalView}}));});`});
 await page.addScriptTag({content:read('perf-diagnostics-v2034.mjs')});
 await page.addScriptTag({content:`(()=>{${moduleBody('house-registration-review-v2202.mjs')} initHouseRegistrationReview2202('','');})();`});
 await page.addScriptTag({content:`(()=>{${moduleBody('house-groups-v2225.mjs')} initHouseGroupsV2225('','');})();`});
 const settle=()=>page.waitForFunction(()=>!PHCPerfDiagnostics.report().activeNav);
 const report=()=>page.evaluate(()=>PHCPerfDiagnostics.report());
 async function respond(data){await page.waitForFunction(()=>testCalls.filter(n=>n==='house_groups_v2225').length>0);assert.ok(pending.length);await pending.shift().fulfill({json:data});}
 await page.click('[data-portal-view="houses"]');await page.waitForSelector('[data-hg-loading]:visible');
 await page.waitForTimeout(300);
 assert.equal((await report()).activeNav.dataReadyMs,null,'legacy DOM must not mark new data ready');
 await respond({data:fixture});await settle();let r=await report(),n=r.nav.at(-1);
 assert.ok(n.dataReadyMs>=250);assert.equal(n.dataReadyState,'data-rendered');assert.ok(n.freshDataReadyMs>=250);assert.equal(n.rpcRequests,1);
 assert.equal(await page.evaluate(()=>testCalls.filter(n=>n==='house_registration_review_cards_v2202').length),0,'no duplicate review RPC on activation');
 assert.equal(r.release,'2.0.184');assert.equal(r.phase,'1.2');assert.equal(typeof r.boot.longTaskSupported,'boolean');
 await page.click('[data-group="review"]');await page.waitForSelector('[data-hg-open="review"].house-review-red');
 await page.click('[data-hg-open="review"]');await page.waitForSelector('.house-review-overlay');
 assert.equal(await page.evaluate(()=>testCalls.filter(n=>n==='house_registration_review_cards_v2202').length),1,'fresh review still checked when opening');
 await page.click('.house-review-overlay [data-close]');
 await page.click('[data-portal-view="overview"]');await settle();
 await page.click('[data-portal-view="houses"]');await settle();n=(await report()).nav.at(-1);
 assert.equal(n.cachedAtTap,true);assert.equal(n.dataReadyMs,0);assert.equal(n.dataReadyState,'cached-at-tap');assert.equal(n.rpcRequests,0);
 await page.evaluate(()=>testExpire());await page.click('[data-portal-view="overview"]');await settle();
 await page.click('[data-portal-view="houses"]');await page.waitForSelector('[data-hg-loading]:visible');
 assert.equal(await page.locator('[data-hg-open="review"]').isVisible(),true,'preserve cards during refresh');
 await page.waitForTimeout(300);await respond({data:fixture});await settle();n=(await report()).nav.at(-1);
 assert.equal(n.dataReadyMs,0);assert.ok(n.freshDataReadyMs>=250);assert.equal(n.rpcRequests,1);
 // Error responses must not poison the 60-second shared cache.
 await page.click('[data-hg-refresh]');await page.waitForSelector('[data-hg-loading]:visible');await respond({error:{message:'temporary'}});
 await page.waitForSelector('[data-hg-error]:has-text("ไม่สำเร็จ")');
 await page.click('[data-portal-view="overview"]');await settle();await page.click('[data-portal-view="houses"]');
 await page.waitForSelector('[data-hg-loading]:visible');await respond({data:[]});await settle();
 assert.equal(await page.locator('[data-house-groups]').getAttribute('data-hg-ready'),'true','empty response is ready');
 assert.equal(await page.locator('[data-hg-list] [data-hg-open]').count(),0);
 assert.equal((await report()).nav.at(-1).rpcRequests,1,'retry after failure made a new request');
 assert.deepEqual(errors,[]);
 fs.writeFileSync(path.join(__dirname,'..','..','loading-perf-v2227.json'),JSON.stringify(await report(),null,2));
 console.log('PASS: delayed/empty data readiness, cached hidden panel, expired cache preserves cards, fresh timing, no duplicate review, review open, error retry, release and browser capability metadata');
}finally{await browser.close();}})().catch(e=>{console.error(e);process.exitCode=1;});
