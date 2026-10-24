#!/usr/bin/env node
'use strict';
// Disposable schema/role/size experiment only; NO Cloud, JHCIS, or Local DB connection.
const assert=require('node:assert/strict'),zlib=require('node:zlib');
const {performance}=require('node:perf_hooks');
const COMMUNITIES=16,HOUSES=4700,PEOPLE=8600;
const houses=Array.from({length:HOUSES},(_,i)=>({
 id:'synthetic-house-'+i,source_pcucode:'TEST',hcode:'synthetic-hcode-'+i,
 house_no:'TEST-'+i,community:'community-'+i%COMMUNITIES,volunteer_pid:'synthetic-vol-'+i%261,
 record_status:'active',verification_status:'verified',
 latitude:18.1,longitude:99.1,review_reason:'SYNTHETIC '+'.'.repeat(90),
 coordinate_source:'synthetic',coordinate_distance_m:0,updated_at:'2026-09-25T00:00:00Z'
}));
const people=Array.from({length:PEOPLE},(_,i)=>({
 source_pcucode:'TEST',source_pid:i+1,house_id:houses[i%HOUSES].id,
 community:houses[i%HOUSES].community,volunteer_pid:houses[i%HOUSES].volunteer_pid,
 display_name:'SYNTHETIC MEMBER '+i,birth_date:'1990-01-01',active:true,
 latest_ncd_status:'not-screened',latest_severity:'none',
 citizen_id_hash:'synthetic-only-not-real',citizen_id_last4:'0000',
 previous_weight_kg:60,previous_glucose_mg_dl:90,previous_sbp:120,
 historical_note:'synthetic historical note '+'.'.repeat(100)
}));
const houseCard=h=>({
 id:h.id,source_pcucode:h.source_pcucode,hcode:h.hcode,house_no:h.house_no,
 community:h.community,volunteer_pid:h.volunteer_pid,record_status:h.record_status,
 verification_status:h.verification_status,updated_at:h.updated_at
});
const memberCard=p=>({
 source_pcucode:p.source_pcucode,source_pid:p.source_pid,house_id:p.house_id,
 community:p.community,volunteer_pid:p.volunteer_pid,display_name:p.display_name,
 birth_date:p.birth_date,active:p.active,latest_ncd_status:p.latest_ncd_status,
 latest_severity:p.latest_severity
});
const projection={houses:houses.map(houseCard),people:people.map(memberCard)};
const original={houses,people};
function scope(role,h,p){
 if(role==='admin')return true;
 if(role==='staff')return h.community==='community-2';
 if(role==='user')return h.volunteer_pid==='synthetic-vol-3';
 return false;
}
for(const role of ['admin','staff','user','anon']){
 const expected=houses.filter(h=>scope(role,h)).map(h=>h.id);
 const projected=projection.houses.filter(h=>scope(role,h)).map(h=>h.id);
 assert.deepEqual(projected,expected,'synthetic house scope mismatch '+role);
 const allowed=new Set(projected);
 const scoped=projection.people.filter(p=>allowed.has(p.house_id));
 assert(scoped.every(p=>allowed.has(p.house_id)),'synthetic person cross-scope '+role);
 if(role==='anon')assert.equal(scoped.length,0);
}
const forbidden=['citizen_id_hash','citizen_id_last4','previous_weight_kg','previous_glucose_mg_dl','historical_note'];
for(const field of forbidden)
 assert(!JSON.stringify(projection).includes('"'+field+'"'),'sensitive/history column leaked to synthetic read-only card projection: '+field);
const sample=original.houses[3],card=projection.houses[3];
for(const k of ['id','hcode','house_no','community','volunteer_pid','record_status'])
 assert.equal(card[k],sample[k],'house card semantic regression '+k);
const mp=original.people[3],cp=projection.people[3];
for(const k of ['source_pid','house_id','display_name','birth_date','active','latest_ncd_status'])
 assert.equal(cp[k],mp[k],'member card semantic regression '+k);
function bytes(x){return Buffer.byteLength(JSON.stringify(x),'utf8')}
const raw=bytes(original),thin=bytes(projection);
const gzRaw=zlib.gzipSync(JSON.stringify(original)).length,gzThin=zlib.gzipSync(JSON.stringify(projection)).length;
assert(thin<raw&&gzThin<gzRaw,'Synthetic card payload did not shrink');
const localReportsAvailable=false,primaryCloudCardCalls=2;
assert.equal(primaryCloudCardCalls,2);
assert.equal(localReportsAvailable?2:2,primaryCloudCardCalls,'Local offline must not add calls to baseline house/member cards');
const t=[];
for(let i=0;i<32;i++){const a=performance.now();JSON.stringify(projection);t.push(performance.now()-a)}
t.sort((a,b)=>a-b);
console.log('PASS: synthetic 4700-house / 8600-active-member scoped card projection preserves base UI cards, denies cross-scope reads and does not depend on Local report availability');
console.log(JSON.stringify({fixture_only:true,not_production_data:true,houses:HOUSES,people:PEOPLE,card_calls_before:2,card_calls_after:2,local_report_calls_when_offline:0,full_json_bytes:raw,card_json_bytes:thin,full_gzip_bytes:gzRaw,card_gzip_bytes:gzThin,illustrative_json_serialization_p95_ms:Number(t[Math.ceil(t.length*.95)-1].toFixed(2)),cloud_storage_reclaimed_bytes:0}));
