#!/usr/bin/env node
'use strict';
// Disposable CI PostgREST + fabricated users/rows. NOT live Auth, LINE, real frontend or production RLS.
const assert=require('node:assert/strict'),crypto=require('node:crypto');
const base=process.env.PHASE4_API_URL||'http://127.0.0.1:3000';
const secret=process.env.PHASE4_JWT_SECRET;
assert(secret&&secret.length>=32,'Disposable fixture JWT secret required');
const b64=o=>Buffer.from(JSON.stringify(o)).toString('base64url');
function bearer(claims){
 const h=b64({alg:'HS256',typ:'JWT'});
 const p=b64({role:'authenticated',sub:'fixture-'+(claims.app_role||'unknown'),
  exp:Math.floor(Date.now()/1000)+600,...claims});
 return h+'.'+p+'.'+crypto.createHmac('sha256',secret).update(h+'.'+p).digest('base64url');
}
async function request(table,claims,{method='GET',id=null,body=null,fields='id'}={}){
 const url=new URL('/'+table,base);
 url.searchParams.set('select',fields);
 if(id)url.searchParams.set('id','eq.'+id);
 const headers=claims?{Authorization:'Bearer '+bearer(claims)}:{};
 if(body){headers['Content-Type']='application/json';headers.Prefer='return=representation';}
 const start=process.hrtime.bigint();
 const res=await fetch(url,{method,headers,body:body?JSON.stringify(body):undefined,signal:AbortSignal.timeout(12000)});
 const txt=await res.text();
 return {status:res.status,rows:txt.startsWith('[')?JSON.parse(txt):null,
  error:txt.slice(0,150),ms:Number(process.hrtime.bigint()-start)/1e6};
}
const tables=['phase4_moo_houses','phase4_moo_members'];
const users=[
 {name:'admin',claims:{app_role:'admin'},houses:32,members:64},
 {name:'staff_same_moo',claims:{app_role:'staff',community:'moo-1-community-1',moo:'1'},houses:4,members:8},
 {name:'staff_bad_community_moo',claims:{app_role:'staff',community:'moo-1-community-1',moo:'2'},houses:0,members:0},
 {name:'user_one_assigned_house',claims:{app_role:'user',volunteer_pid:'vol-1-1'},houses:1,members:2},
 {name:'user_unassigned',claims:{app_role:'user',volunteer_pid:'not-assigned'},houses:0,members:0},
];
(async()=>{
 for(const table of tables){
  const anonymous=await request(table,null);
  assert([401,403].includes(anonymous.status),'Anonymous direct table access must fail: '+table);
 }
 const timings=[];
 for(let iteration=0;iteration<8;iteration++){
  for(const actor of users){
   for(const [table,expected] of [[tables[0],actor.houses],[tables[1],actor.members]]){
    const result=await request(table,actor.claims,{fields:table===tables[0]?'id,moo,community,volunteer_pid,house_no':'id,house_id'});
    assert.equal(result.status,200,actor.name+' '+table+' HTTP failure '+result.error);
    assert.equal(result.rows.length,expected,actor.name+' '+table+' scope/count mismatch');
    if(actor.name==='staff_same_moo')assert(result.rows.every(x=>x.moo===1),'Staff saw another moo');
    if(actor.name==='user_one_assigned_house'&&table===tables[0])
     assert(result.rows.every(x=>x.volunteer_pid==='vol-1-1'));
    timings.push(result.ms);
   }
  }
 }
 const staff=users[1].claims, user=users[3].claims;
 const forged=await request(tables[1],staff,{id:'member-h-2-1-1-1'});
 assert.equal(forged.status,200);
 assert.equal(forged.rows.length,0,'Forged member community bypassed true house FK scope');
 const siblingBefore=await request(tables[0],staff,{id:'h-1-2-1',fields:'id,house_no'});
 assert.equal(siblingBefore.rows.length,1,'Same-moo sibling house must be viewable to staff');
 const siblingWrite=await request(tables[0],staff,{method:'PATCH',id:'h-1-2-1',
  body:{house_no:'UNAUTHORIZED-SIBLING-EDIT'},fields:'id,house_no'});
 assert([200,204].includes(siblingWrite.status),'Unexpected sibling HTTP status: '+siblingWrite.error);
 assert.equal((siblingWrite.rows||[]).length,0,'Staff modified a different community in same moo');
 const siblingAfter=await request(tables[0],staff,{id:'h-1-2-1',fields:'id,house_no'});
 assert.deepEqual(siblingAfter.rows,siblingBefore.rows,'Sibling household changed despite read-only policy');
 const own=await request(tables[0],staff,{method:'PATCH',id:'h-1-1-1',
  body:{house_no:'SYNTHETIC-STAFF-OWN-EDIT'},fields:'id,house_no'});
 assert.equal(own.status,200,'Staff cannot modify OWN community fixture: '+own.error);
 assert.equal(own.rows.length,1,'Staff own-community update did not affect exactly one row');
 const userWrite=await request(tables[0],user,{method:'PATCH',id:'h-1-1-1',
  body:{house_no:'UNAUTHORIZED-USER-EDIT'},fields:'id,house_no'});
 assert([200,204].includes(userWrite.status));
 assert.equal((userWrite.rows||[]).length,0,'User changed a staff-only test field');
 const ownAfter=await request(tables[0],staff,{id:'h-1-1-1',fields:'id,house_no'});
 assert.equal(ownAfter.rows[0].house_no,'SYNTHETIC-STAFF-OWN-EDIT');
 timings.sort((a,b)=>a-b);
 console.log('PASS: isolated signed fake roles preserve same-moo staff read-only sibling, own-community update, USER assigned-house read and FK-based member privacy');
 console.log(JSON.stringify({fixture_only:true,real_frontend_test:false,authenticated_real_test_accounts_used:false,
  synthetic_communities:16,synthetic_houses:32,synthetic_members:64,measured_http_calls:timings.length,
  isolated_http_p95_ms:Number(timings[Math.ceil(timings.length*.95)-1].toFixed(2)),
  no_production_writes:true,cloud_storage_reclaimed_bytes:0}));
})().catch(e=>{console.error('FAIL: '+e.message);process.exitCode=1});
