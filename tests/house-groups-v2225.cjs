const fs=require('fs'),path=require('path'),assert=require('node:assert/strict');
const {chromium}=require('C:/Users/acer/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules/playwright');
const source=fs.readFileSync(path.join(__dirname,'..','house-groups-v2225.mjs'),'utf8').replace(/^import[^\n]*\n/,'').replaceAll('export ','');
const html=fs.readFileSync(path.join(__dirname,'..','index.html'),'utf8'),nav=html.match(/<nav id="portal-nav"[\s\S]*?<\/nav>/)[0];
const css=fs.readFileSync(path.join(__dirname,'..','style.css'),'utf8');
(async()=>{const browser=await chromium.launch({channel:'msedge',headless:true});try{
 for(const role of ['user','staff','admin']){
  const page=await browser.newPage({viewport:{width:371,height:844}});
  await page.setContent('<main class="shell"><section id="portal">'+nav+'<section class="card" data-portal-panel="houses"><div data-house-review-section>OLD REVIEW</div><div class="myh"><div class="myh-top"><div class="myh-title">OLD TITLE</div><button class="primary" data-myh-add>เพิ่มบ้านใหม่</button></div><div data-myh-pending>คำขอบ้านรอตรวจ JHCIS</div><div class="myh-search">OLD LIST</div></div></section></section></main>');
  await page.addStyleTag({content:css});
  await page.evaluate(role=>{document.querySelector('#portal-nav').dataset.visibleCount=role==='admin'?'6':'5';document.querySelectorAll('[data-roles]').forEach(b=>b.hidden=!b.dataset.roles.split(' ').includes(role));},role);
  await page.addScriptTag({content:`(()=>{
   let calls=[],authCallback,fail=false,delayNames=false,resolveNames;const events=[];
   let testProfile={user_id:'fixture-${role}',role:'${role}',active:true};
   const fixture=[...Array.from({length:35},(_,i)=>({id:'c'+i,house_no:String(i+1),moo:'3',community:'ชุมชนทดสอบ',house_group:'care',target_count:2,type2_count:0,reason:'มีเป้าหมายดูแลสุขภาพ'})),
    {id:'r',house_no:'162',moo:'3',community:'ชุมชนทดสอบ',house_group:'review',target_count:1,type2_count:0,review:{needs_id11:true},reason:'รอตรวจสอบทะเบียน'},
    {id:'e',house_no:'250',moo:'3',community:'ชุมชนทดสอบ',house_group:'empty',target_count:0,type2_count:4,reason:'มีชื่อทะเบียน type 2 · ไม่นับเป็นเป้าหมาย'},
    {id:'z',house_no:'251',moo:'3',community:'ชุมชนทดสอบ',house_group:'empty',target_count:0,type2_count:0,reason:'ไม่พบรายชื่อใน Cloud · ยังไม่ยืนยันการพักอาศัย'},
    {id:'s',house_no:'84',moo:'6',community:'จิตต์อารีย์',house_group:'special',target_count:0,type2_count:0,reason:'โรงเรียน · เก็บเฉพาะทะเบียนบ้าน'}];
   const mock={auth:{onAuthStateChange:f=>authCallback=f},async rpc(name,args){calls.push({name,args});
    if(name==='house_groups_v2225')return fail?{error:{message:'network'}}:{data:fixture};
    if(name==='house_type2_notice_v2225')return {data:{house_no:args.p_house_id==='e'?'250':args.p_house_id==='z'?'251':'84',moo:'3',community:'ชุมชนทดสอบ',type2_count:args.p_house_id==='e'?4:0,can_view_names:testProfile.role!=='user'&&args.p_house_id==='e',school_house_only:args.p_house_id==='s'}};
    if(name==='house_type2_names_v2225'){if(delayNames)return new Promise(r=>resolveNames=()=>r({data:[{display_name:'LATE PRIVATE NAME'}]}));return {data:[{display_name:'ชื่อสมมติ <script>bad()</script>',jhcis_typelive:2,counted_as_target:false}]};}
   }};
   const getSharedSupabase=async()=>mock,getSharedProfile=async()=>testProfile,sharedCall=async(k,f)=>f(),invalidateShared=()=>{},bindPortalActivation=(v,f)=>queueMicrotask(f);
   for(const name of ['phc:open-field-house','phc:open-house-registration-review','phc:open-house-detail'])document.addEventListener(name,e=>events.push({name,detail:e.detail}));
   ${source}
   window.test={calls,events,auth:event=>authCallback(event),setFail:v=>fail=v,setDelay:v=>delayNames=v,resolve:()=>resolveNames?.(),reload:()=>load(true)};
   initHouseGroupsV2225('','');
  })();`});
  await page.waitForSelector('[data-hg-count="care"]:has-text("35")');
  assert.equal(await page.locator('[data-hg-open]:visible').count(),30);
  assert.equal(await page.locator('.myh-search').isVisible(),false);
  assert.equal(await page.locator('[data-house-review-section]').isVisible(),false);
  assert.equal(await page.locator('[data-myh-pending]').isVisible(),false);
  await page.click('[data-hg-more]');assert.equal(await page.locator('[data-hg-list] [data-hg-open]').count(),35);
  assert.equal(await page.locator('[data-hg-more]').isVisible(),false);
  await page.click('[data-hg-open="c0"]');assert.equal((await page.evaluate(()=>test.events.at(-1))).name,'phc:open-field-house');
  await page.click('[data-group="review"]');assert.equal(await page.locator('[data-hg-list] [data-hg-open]').count(),1);assert.equal(await page.locator('[data-myh-pending]').isVisible(),true);
  await page.click('[data-hg-open="r"]');assert.equal((await page.evaluate(()=>test.events.at(-1))).name,'phc:open-house-registration-review');
  await page.click('[data-group="empty"]');assert.equal(await page.locator('[data-myh-pending]').isVisible(),false);
  await page.fill('[data-hg-search]','250');assert.equal(await page.locator('[data-hg-list] [data-hg-open]').count(),1);
  await page.click('[data-hg-open="e"]');await page.waitForSelector('[data-hg-notice]:has-text("4 คน")');
  assert.equal(await page.evaluate(()=>test.calls.filter(c=>c.name.includes('names')).length),0,'no prefetch names');
  if(role==='user'){assert.equal(await page.locator('[data-hg-names]').count(),0);}
  else{
   await page.click('[data-hg-names]');await page.waitForSelector('[data-hg-name-list]:has-text("ชื่อสมมติ")');
   assert.equal(await page.locator('[data-hg-name-list] script').count(),0,'escape names');
   await page.click('[data-hg-names]');assert.equal(await page.locator('[data-hg-name-list]').textContent(),'','clear hidden names');
  }
  await page.keyboard.press('Escape');assert.equal(await page.locator('.hg25-overlay').count(),0);
  assert.equal(await page.locator('[data-group="empty"]').getAttribute('aria-pressed'),'true');assert.equal(await page.locator('[data-hg-search]').inputValue(),'250');
  await page.fill('[data-hg-search]','');await page.click('[data-hg-open="z"]');await page.waitForSelector('[data-hg-notice]:has-text("ยังไม่ยืนยัน")');assert.equal(await page.locator('[data-hg-names]').count(),0);await page.click('[data-hg-close]');
  if(role!=='user'){
   await page.evaluate(()=>test.setDelay(true));await page.click('[data-hg-open="e"]');await page.waitForSelector('[data-hg-names]');await page.click('[data-hg-names]');await page.click('[data-hg-close]');await page.evaluate(()=>test.resolve());assert.equal(await page.locator('body').textContent().then(t=>t.includes('LATE PRIVATE NAME')),false);
  }
  await page.screenshot({path:path.join(__dirname,'..','..',role+'-mobile.png'),fullPage:true});
  assert.equal(await page.evaluate(()=>document.documentElement.scrollWidth<=371),true,'mobile width');
  await page.evaluate(()=>test.setFail(true));await page.click('[data-hg-refresh]');await page.waitForSelector('[data-hg-error]:has-text("ไม่สำเร็จ")');
  await page.evaluate(()=>test.setFail(false));await page.click('[data-hg-refresh]');await page.waitForFunction(()=>document.querySelector('[data-hg-error]').textContent==='');
  await page.evaluate(()=>test.auth('SIGNED_OUT'));assert.equal(await page.locator('[data-house-groups]').count(),0);assert.equal(await page.locator('.hg25-overlay').count(),0);
  await page.close();console.log('PASS '+role+': three groups, default, counts, paging, search, care/review events, count-only and lazy names, escaping, close races, retry, mobile, signout');
 }
}finally{await browser.close();}})().catch(e=>{console.error(e);process.exitCode=1;});
