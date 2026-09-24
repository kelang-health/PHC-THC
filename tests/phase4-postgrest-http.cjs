#!/usr/bin/env node
'use strict';
// Isolated synthetic PostgREST fixture only. No project URL, live keys, or real records.
const assert=require('node:assert/strict');
const crypto=require('node:crypto');
const base=process.env.PHASE4_API_URL||'http://127.0.0.1:3000';
const secret=process.env.PHASE4_JWT_SECRET;
assert(secret&&secret.length>=32,'Isolated PostgREST fixture secret is missing');
const b64=data=>Buffer.from(JSON.stringify(data)).toString('base64url');
const token=sub=>{
 const h=b64({alg:'HS256',typ:'JWT'});
 const p=b64({role:'authenticated',sub,exp:Math.floor(Date.now()/1000)+600});
 const sig=crypto.createHmac('sha256',secret).update(h+'.'+p).digest('base64url');
 return h+'.'+p+'.'+sig;
};
const get=async (table,bearer)=>{
 const url=new URL('/'+table+'?select=id&order=id',base);
 const headers=bearer?{Authorization:'Bearer '+bearer}:{};
 const r=await fetch(url,{headers,signal:AbortSignal.timeout(12000)});
 const body=await r.text();
 return {status:r.status,rows:body.startsWith('[')?JSON.parse(body):null,error:body.slice(0,160)};
};
(async()=>{
 const anon=await get('phase4_health_fixture');
 assert([401,403].includes(anon.status),'Anonymous private-table GET should be rejected: '+JSON.stringify(anon));
 const a=await get('phase4_health_fixture',token('test-user-a'));
 assert.equal(a.status,200,'Signed-in test user A HTTP GET failed: '+JSON.stringify(a));
 assert.deepEqual(a.rows.map(x=>x.id),['fixture-1'],'User A could see other synthetic user');
 const b=await get('phase4_health_fixture',token('test-user-b'));
 assert.equal(b.status,200,'Signed-in test user B HTTP GET failed: '+JSON.stringify(b));
 assert.deepEqual(b.rows.map(x=>x.id),['fixture-2'],'User B could see other synthetic user');
 const privAnon=await get('phase4_server_only');
 assert([401,403].includes(privAnon.status),'Anon server-only table request must be rejected');
 const privAuth=await get('phase4_server_only',token('test-user-a'));
 assert([401,403].includes(privAuth.status),'Authenticated server-only table request must be rejected');
 console.log('PASS: synthetic PostgREST HTTP anon denial, two scoped authenticated reads, and server-only denial');
})().catch(e=>{console.error('FAIL: '+e.message);process.exitCode=1});
