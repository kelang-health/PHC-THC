#!/usr/bin/env node
'use strict';
// HTTP checks use only disposable PostgREST, synthetic JWTs and synthetic booking records.
const assert=require('node:assert/strict');
const crypto=require('node:crypto');
const base=process.env.PHASE4_API_URL||'http://127.0.0.1:3000';
const secret=process.env.PHASE4_JWT_SECRET;
assert(secret&&secret.length>=32,'Missing isolated fixture JWT key');
const b64=o=>Buffer.from(JSON.stringify(o)).toString('base64url');
const jwt=(sub,app_role,community_id)=>{
 const h=b64({alg:'HS256',typ:'JWT'}),p=b64({role:'authenticated',sub,app_role,community_id,exp:Math.floor(Date.now()/1000)+600});
 return h+'.'+p+'.'+crypto.createHmac('sha256',secret).update(h+'.'+p).digest('base64url');
};
const send=async(method,bearer,body)=>{
 const headers={'Accept':'application/json'};
 if(bearer)headers.Authorization='Bearer '+bearer;
 if(body!==undefined)headers['Content-Type']='application/json';
 const r=await fetch(new URL('/phase4_booking_fixture?select=id&order=id',base),{
  method,headers,body:body===undefined?undefined:JSON.stringify(body),signal:AbortSignal.timeout(12000)});
 const raw=await r.text();
 return {status:r.status,rows:raw.startsWith('[')?JSON.parse(raw):null,preview:raw.slice(0,130)};
};
const expectIds=async(token,ids,label)=>{
 const r=await send('GET',token);
 assert.equal(r.status,200,label+' read status '+JSON.stringify(r));
 assert.deepEqual(r.rows.map(x=>x.id),ids,label+' incorrect scope');
};
const forbidden=r=>assert([401,403,405].includes(r.status),'Should reject the request: '+JSON.stringify(r));
(async()=>{
 forbidden(await send('GET'));
 const userA=jwt('test-user-a','user','community-a'),userB=jwt('test-user-b','user','community-a');
 const staffA=jwt('test-staff-a','staff','community-a'),staffB=jwt('test-staff-b','staff','community-b');
 const admin=jwt('test-admin','admin','');
 await expectIds(userA,['booking-a'],'USER A');
 await expectIds(userB,['booking-b'],'USER B');
 await expectIds(staffA,['booking-a','booking-b'],'STAFF community A');
 await expectIds(staffB,['booking-c'],'STAFF community B');
 await expectIds(admin,['booking-a','booking-b','booking-c'],'ADMIN');
 const invalid=jwt('test-user-a','user','community-b');
 await expectIds(invalid,['booking-a'],'USER cannot change assignment by supplying a different community');
 forbidden(await send('POST',userA,{id:'booking-x',slot_id:'slot-x',subject_ref:'synthetic-person-x',owner_id:'test-user-a',community_id:'community-a'}));
 forbidden(await send('PATCH',staffA,{booking_status:'cancelled'}));
 forbidden(await send('DELETE',admin));
 console.log('PASS: isolated synthetic booking API role scoping (USER/STAFF/ADMIN), anonymous denial, paused direct writes');
})().catch(e=>{console.error('FAIL: '+e.message);process.exitCode=1});
