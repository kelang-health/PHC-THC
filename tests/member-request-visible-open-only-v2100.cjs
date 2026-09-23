'use strict';
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const {test} = require('node:test');

const root = path.resolve(__dirname, '..');
const source = fs.readFileSync(path.join(root,'phc-five-features-v190.mjs'),'utf8');
const start = source.indexOf('function userVisibleMemberRequestsV2100(records){');
const end = source.indexOf('async function renderHouseMemberRequests(',start);
assert(start>=0&&end>start,'Cloud User must have a worklist visibility filter');
const segment = source.slice(start,end).trim();
const filter = vm.runInNewContext('('+segment+')');

test('verified and linked request is hidden from user request cards',()=>{
  const original=[
    {id:'pending',status:'pending',linked:false},
    {id:'correction',status:'needs_correction',linked:false},
    {id:'validated_not_linked',status:'verified',linked:false,linked_person_id:null},
    {id:'complete',status:'verified',linked:true,linked_person_id:2097},
    {id:'complete_by_pid',status:'verified',linked_person_id:18779},
    {id:'rejected',status:'rejected',linked:false},
  ];
  const listed=filter(original);
  assert.deepEqual(Array.from(listed,r=>r.id),
    ['pending','correction','validated_not_linked','rejected']);
  assert.equal(original.length,6,'do not modify source request history');
});

test('handles empty, malformed and status spacing without dropping open work',()=>{
  assert.deepEqual(Array.from(filter(null)),[]);
  assert.deepEqual(Array.from(filter([null,undefined])),[]);
  const value=[
    {id:'complete',status:' VERIFIED ',linked:true},
    {id:'open',status:'pending',linked_person_id:123},
    {id:'wrong',status:'verified',linked:false,linked_person_id:0},
  ];
  assert.deepEqual(Array.from(filter(value),r=>r.id),['open']);
});

test('only user request cards use filtered list; keep member roster/Admin queue',()=>{
  assert.match(source,/household_member_requests_v2043/);
  assert.match(source,/household_member_requests_v190/);
  assert.match(source,/const rows=userVisibleMemberRequestsV2100\(data\);sec\.innerHTML=/);
  assert.match(source,/async function renderAdminMemberQueue/);
  assert.doesNotMatch(source,/\.delete\(\)/);
  const html=fs.readFileSync(path.join(root,'index.html'),'utf8');
  const config=fs.readFileSync(path.join(root,'config.js'),'utf8');
  assert.match(html,/name="phc-release" content="2\.0\.101"/);
  assert.match(html,/config\.js\?v=2\.0\.101&p=2101/);
  assert.match(config,/phc-five-features-v190\.mjs\?v=2\.0\.101&p=2101/);
});



test('Admin linked-person safety count is not mislabeled as pending work',()=>{
  assert.match(source,/คำขอ\/สมาชิกที่ผูกกับบ้าน \(รวมตรวจแล้ว\)/);
  assert.doesNotMatch(source,/คำขอสมาชิกที่ยังต้องจัดการ/);
  assert.match(source,/ยกเลิกบ้านไม่ได้: มีคำขอหรือสมาชิกที่เชื่อมทะเบียนอยู่/);
  assert.match(source,/ดูคำขอที่ยังจัดการได้/);
});
