const fs=require('node:fs');
const path=require('node:path');
const assert=require('node:assert/strict');
const {chromium}=require('C:/Users/acer/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules/playwright');
const source=fs.readFileSync(path.join(__dirname,'..','phc-five-features-v190.mjs'),'utf8');
const code=source.slice(source.indexOf('function elderlyBothDmHtV2140'),source.indexOf('async function loadElderlyWizardV207'));
(async()=>{
 const browser=await chromium.launch({channel:'msedge',headless:true});
 const page=await browser.newPage({viewport:{width:390,height:844}});
 try{
  await page.setContent('<div id="root"></div>');
  await page.addScriptTag({content:`
   const esc=v=>String(v??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
   const fmt=v=>v,thaiDayV208=()=> '2026-10-06';
   let saved=[],wizard=0,mode='normal',existing=null;
   const supabase={from(table){let q={select(){return q},eq(){return q},single(){return Promise.resolve({data:{screening_date:mode==='historical'?'2026-10-05':'2026-10-06'}})},maybeSingle(){if(mode==='failure')return Promise.resolve({error:{message:'network error'}});return Promise.resolve({data:table==='health_persons'?{previous_height_cm:155}:existing})}};return q},async rpc(name,args){saved.push({name,args});return {data:{ok:true}}}};
   async function ensureScreeningSessionV2023(s){s.session_id='mock-session';return s}
   async function loadElderlyWizardV207(){wizard++}
   function showPhcToast(){} function friendlyError(e){return e.message} function closeModal(){}
   function ncdRequirementTextV2117(){return 'NCD'} function ncdActionLabelV2117(){return 'NCD'} function openExistingNcd(){}
   ${code}
   window.setup=async(options={})=>{wizard=0;saved=[];mode=options.mode||'normal';existing=options.existing||null;window.person={source_pcucode:'test',source_pid:1,has_dm:true,has_ht:true,ncd_status:'not_required',...options.person};await renderElderlyRoute(document.querySelector('#root'),person,'test')};
   window.state=()=>({wizard,saved});
  `});
  await page.evaluate(()=>setup());
  await page.click('[data-elderly-continue]');
  assert.equal(await page.locator('[data-elderly-basic-health]').count(),1);
  assert.equal(await page.locator('[data-elderly-basic-health] input[type=number]').count(),8);
  assert.equal(await page.locator('input[name=height_cm]').inputValue(),'');
  await page.click('button[type=submit]');
  assert.equal((await page.evaluate(()=>state())).saved.length,0);
  for(const [name,value] of Object.entries({height_cm:155,weight_kg:56,waist_cm:84,sbp:122,dbp:76,pulse:80,respiratory_rate:20,temperature_c:36.6}))await page.fill(`[name=${name}]`,String(value));
  await page.click('button[type=submit]');
  assert.match(await page.locator('[data-basic-error]').innerText(),/ยืนยัน/);
  await page.check('[data-basic-confirm]');
  await page.fill('[name=pulse]','121');
  await page.click('button[type=submit]');
  assert.equal((await page.evaluate(()=>state())).saved.length,0);
  assert.equal(await page.locator('[data-basic-warning]').isVisible(),true);
  await page.click('button[type=submit]');
  let result=await page.evaluate(()=>state());
  assert.equal(result.saved.length,1);assert.equal(result.wizard,1);
  assert.equal(result.saved[0].args.p_pulse,121);
  for(const person of [{has_dm:false,has_ht:false},{has_dm:true,has_ht:false},{has_dm:false,has_ht:true}]){
   await page.evaluate(person=>setup({person:{...person,ncd_status:'complete',dm_target:!person.has_dm,ht_target:!person.has_ht}}),person);
   await page.click('[data-elderly-continue]');
   assert.equal((await page.evaluate(()=>state())).wizard,1);
   assert.equal(await page.locator('[data-elderly-basic-health]').count(),0);
  }
  await page.evaluate(()=>setup({existing:{pulse:80}}));await page.click('[data-elderly-continue]');
  assert.equal((await page.evaluate(()=>state())).wizard,1);
  await page.evaluate(()=>setup({mode:'historical'}));await page.click('[data-elderly-continue]');
  assert.equal((await page.evaluate(()=>state())).wizard,1);
  await page.evaluate(()=>setup({mode:'failure'}));await page.click('[data-elderly-continue]');
  assert.equal(await page.locator('[data-elderly-choice]').isVisible(),true);
  assert.equal(await page.locator('[data-elderly-continue]').isEnabled(),true);
  await page.evaluate(()=>setup({person:{elderly9_status:'complete',session_id:'mock-session'}}));
  assert.equal(await page.locator('[data-elderly-complete]').isVisible(),true);
  await page.click('[data-elderly-review]');assert.equal((await page.evaluate(()=>state())).wizard,1);
  console.log('PASS: required measurements, historical reference blank, confirmation, pulse warning, save once, all disease routes, saved exam resume, historical resume, network recovery, completed-result review');
 }finally{await browser.close()}
})().catch(e=>{console.error(e);process.exitCode=1});
