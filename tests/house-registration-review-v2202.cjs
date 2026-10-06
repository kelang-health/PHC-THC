const fs=require('fs'),path=require('path'),assert=require('node:assert/strict');
const {chromium}=require('C:/Users/acer/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules/playwright');
const source=fs.readFileSync(path.join(__dirname,'..','house-registration-review-v2202.mjs'),'utf8').replace(/^import[^\n]*\n/,'').replaceAll('export ','');
(async()=>{const browser=await chromium.launch({channel:'msedge',headless:true});const page=await browser.newPage({viewport:{width:390,height:844}});try{
 await page.setContent('<div data-portal-panel="communities"></div><div data-portal-panel="houses"><button data-myh-house-pick="a">บ้าน 1</button><button data-myh-house-pick="outside">บ้านอื่น</button><button data-hq-house="b">บ้าน 2</button></div>');
 await page.addScriptTag({content:`let calls=[],mutations=0,duplicate=false;const records=[{id:'a',hcode:'1',house_no:'1',moo:'2',community:'ชุมชน ก',house_id_11:'123',updated_at:'2026-10-06T00:00:00Z',needs_id11:true,can_edit:true},{id:'b',hcode:'2',house_no:'2',moo:'2',needs_id11:true,unassigned_village:true,can_edit:true}];
 const mock={auth:{onAuthStateChange(){}},async rpc(name,args){calls.push({name,args});if(name.startsWith('correct')){if(duplicate)return {error:{message:'HOUSE_ID11_DUPLICATE'}};records[0].needs_id11=false;return {data:{ok:true}};}return {data:records.filter(r=>r.needs_id11||r.unassigned_village)}}};
 const getSharedSupabase=async()=>mock,getSharedProfile=async()=>({user_id:'admin',active:true}),sharedCall=async(k,f)=>f(),invalidateShared=()=>{},bindPortalActivation=(v,f)=>{if(v==='houses')f()};
 ${source}
 window.test={validHouseId11,reviewColor,setDuplicate:v=>duplicate=v,calls};new MutationObserver(()=>mutations++).observe(document.body,{subtree:true,childList:true});window.mutationCount=()=>mutations;initHouseRegistrationReview2202('','');`});
 await page.waitForSelector('.house-review-red');
 assert.equal(await page.locator('[data-myh-house-pick="a"].house-review-red').count(),1);
 assert.equal(await page.locator('[data-myh-house-pick="outside"].house-review-red').count(),0);
 assert.equal(await page.locator('[data-hq-house="b"].house-review-yellow').count(),1);
 const before=await page.evaluate(()=>mutationCount());await page.waitForTimeout(400);assert.equal(await page.evaluate(()=>mutationCount()),before,'observer must settle');
 await page.click('[data-review-open="a"]');await page.click('[data-edit]');await page.fill('[name=id11]','1234567890');assert.equal(await page.locator('[type=submit]').isDisabled(),true);
 await page.fill('[name=id11]','01234567890');await page.evaluate(()=>test.setDuplicate(true));await page.click('[type=submit]');await page.waitForFunction(()=>document.querySelector('[role=alert]').textContent.includes('ซ้ำ'));
 await page.evaluate(()=>test.setDuplicate(false));await page.click('[type=submit]');await page.waitForSelector('.house-review-overlay',{state:'detached'});
 assert.equal(await page.locator('[data-myh-house-pick="a"].house-review-red').count(),0);
 const saved=await page.evaluate(()=>test.calls.filter(c=>c.name.startsWith('correct')));assert.equal(saved.length,2);assert.equal(saved[1].args.p_id11,'01234567890');assert.equal(saved[1].args.p_house_id,'a');
 assert.equal(await page.evaluate(()=>test.reviewColor({needs_id11:true,unassigned_village:true})),'yellow');
 assert.equal(await page.evaluate(()=>document.documentElement.scrollWidth<=390),true);
 await page.evaluate(()=>{profile.role='admin';render()});assert.equal(await page.locator('[data-portal-panel="communities"] [data-house-review-section]').count(),1,'Admin uses existing Communities menu');
 console.log('PASS: audited red only, yellow precedence, observer settles, mobile fit, ID11 validation, duplicate recovery, save once, clear warning');
 }finally{await browser.close();}})().catch(e=>{console.error(e);process.exitCode=1});
