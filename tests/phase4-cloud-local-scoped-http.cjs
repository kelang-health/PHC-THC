#!/usr/bin/env node
'use strict';
// Fake users/data on disposable CI PostgREST; does NOT validate real app role mapping.
const assert=require('node:assert/strict'),crypto=require('node:crypto');
const base=process.env.PHASE4_API_URL||'http://127.0.0.1:3000';
const secret=process.env.PHASE4_JWT_SECRET;
assert(secret&&secret.length>=32);
const b64=o=>Buffer.from(JSON.stringify(o)).toString('base64url');
function token(claims){
 const h=b64({alg:'HS256',typ:'JWT'}),p=b64({role:'authenticated',sub:'fixture-'+(claims.app_role||'unknown'),exp:Math.floor(Date.now()/1000)+600,...claims});
 return h+'.'+p+'.'+crypto.createHmac('sha256',secret).update(h+'.'+p).digest('base64url');
}
async function read(table,claims,filter=''){
 const path='/'+table+'?select=id,community,volunteer_pid'+filter;
 const start=process.hrtime.bigint();
 const res=await fetch(new URL(path,base),{headers:claims?{Authorization:'Bearer '+token(claims)}:{},signal:AbortSignal.timeout(12000)});
 const body=await res.text();
 return {status:res.status,rows:body.startsWith('[')?JSON.parse(body):null,elapsedMs:Number(process.hrtime.bigint()-start)/1e6,error:body.slice(0,160)};
}
const cases=[
 {name:'admin',claims:{app_role:'admin'},houses:48,members:144},
 {name:'staff',claims:{app_role:'staff',community:'community-2'},houses:3,members:9},
 {name:'user',claims:{app_role:'user',volunteer_pid:'vol-3'},houses:6,members:18},
 {name:'out-of-scope-user',claims:{app_role:'user',volunteer_pid:'vol-999'},houses:0,members:0},
];
(async()=>{
 for(const table of ['phase4_card_houses','phase4_card_people']){
  const anon=await read(table);
  assert([401,403].includes(anon.status),'Anonymous access to '+table+' unexpectedly allowed: '+anon.status);
 }
 const timings=[];
 for(let round=0;round<12;round++){
  for(const test of cases){
   const h=await read('phase4_card_houses',test.claims);
   const p=await read('phase4_card_people',test.claims);
   for(const [table,result,count] of [['houses',h,test.houses],['members',p,test.members]]){
    assert.equal(result.status,200,test.name+' '+table+' HTTP denied '+result.error);
    assert.equal(result.rows.length,count,test.name+' '+table+' leaked/missed scoped rows');
    if(test.name==='staff')assert(result.rows.every(x=>x.community==='community-2'));
    if(test.name==='user')assert(result.rows.every(x=>x.volunteer_pid==='vol-3'));
    timings.push(result.elapsedMs);
   }
   if(test.name==='staff'||test.name==='user'){
    const allowed=new Set(h.rows.map(x=>x.id));
    assert.equal(allowed.size,h.rows.length);
    const cross=await read('phase4_card_houses',test.claims,'&community=eq.community-15');
    assert.equal(cross.status,200);
    if(test.name==='staff')assert.equal(cross.rows.length,0,'Staff filtered cross-community rows leaked');
   }
  }
 }
 timings.sort((a,b)=>a-b);
 console.log('PASS: synthetic PostgREST scoped 48-house/144-member role cases (ADMIN/STAFF/USER/empty-scope/anon), repeated without HTTP errors or scoped-row exposure');
 console.log(JSON.stringify({fixture_only:true,not_real_frontend:true,not_live_cloud:true,requests_timed:timings.length,isolated_http_p95_ms:Number(timings[Math.ceil(timings.length*0.95)-1].toFixed(2)),cloud_storage_reclaimed_bytes:0}));
})().catch(e=>{console.error('FAIL: '+e.message);process.exitCode=1});
