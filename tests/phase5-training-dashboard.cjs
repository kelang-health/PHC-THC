const assert=require('node:assert/strict');
const puppeteer=require(process.env.PHC_PUPPETEER_PATH||'puppeteer');
const base=process.env.PHC_TEST_BASE||'http://127.0.0.1:8766/';
(async()=>{
 const browser=await puppeteer.launch({executablePath:process.env.PHC_CHROME_PATH||'C:/Program Files/Google/Chrome/Application/chrome.exe',headless:true,args:['--no-sandbox','--disable-gpu']});
 try{
  const page=await browser.newPage();
  await page.goto(base,{waitUntil:'domcontentloaded'});
  const value=await page.evaluate(async()=>{
   const mod=await import('./training-dashboard-v2077.mjs?v=2.0.77&p=2077');
   const roster=[{source_pid:1,community:'A',active:true},{source_pid:2,community:'A',active:true},
    {source_pid:3,community:'B',active:true},{source_pid:4,community:'A',active:false}];
   const history=[{volunteer_pid:1,event_date:'2026-09-01',hours:3,event_status:'active'},
    {volunteer_pid:1,event_date:'2026-09-02',hours:2,event_status:'cancelled'},
    {volunteer_pid:3,event_date:'2026-09-01',hours:4,event_status:'active'},
    {volunteer_pid:4,event_date:'2026-09-01',hours:5,event_status:'active'}];
   return {admin:mod.aggregateTrainingDashboard(roster,history,'admin'),
    staff:mod.aggregateTrainingDashboard(roster,history,'staff','A'),
    user:mod.aggregateTrainingDashboard(roster,history,'user','A',2)};
  });
  assert.equal(value.admin.roster,3);assert.equal(value.admin.trained,2);
  assert.equal(value.admin.records,2);assert.equal(value.admin.hours,7);
  assert.deepEqual({roster:value.staff.roster,trained:value.staff.trained,records:value.staff.records,hours:value.staff.hours},{roster:2,trained:1,records:1,hours:3});
  assert.deepEqual({roster:value.user.roster,trained:value.user.trained,records:value.user.records,hours:value.user.hours},{roster:1,trained:0,records:0,hours:0});
  assert.ok(value.staff.communities.every(x=>x.community==='A'));
  console.log(JSON.stringify({result:'PASS',admin:value.admin,staff:value.staff,user:value.user}));
 }finally{await browser.close()}
})().catch(e=>{console.error(e.stack||e);process.exitCode=1});
