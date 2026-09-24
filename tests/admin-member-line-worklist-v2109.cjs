'use strict';
const {test}=require('node:test');
const assert=require('node:assert/strict');
const fs=require('node:fs');
const path=require('node:path');

const root=path.resolve(__dirname,'..');
const source=fs.readFileSync(path.join(root,'phc-five-features-v190.mjs'),'utf8');
const queue=source.slice(source.indexOf('async function renderAdminMemberQueue(){'),source.indexOf('async function reviewRequest('));

test('admin queue only loads requests awaiting a decision',()=>{
  assert.match(queue,/admin_pending_member_requests_v2109/);
  assert.doesNotMatch(queue,/admin_member_requests_with_submitter_v2090/);
  assert.match(source,/admin-work-member-v2109.*admin_pending_member_requests_v2109/);
});

test('LINE contact is gated by linked submitter and sends through the existing secure queue',()=>{
  assert.match(queue,/r\.requester_line_connected&&r\.requester_user_id/);
  assert.match(queue,/data-line-contact/);
  assert.match(queue,/admin_queue_line_message_v190/);
  assert.match(queue,/p_recipient_user_id:item\.requester_user_id/);
  assert.ok(queue.includes('/\\d{13}/'));
});

test('review invalidates the worklist and refreshes it',()=>{
  const review=source.slice(source.indexOf('async function reviewRequest('),source.indexOf('function openExistingNcd('));
  assert.match(review,/invalidateShared\('admin-work-member-v2109'\)/);
  assert.match(review,/await renderAdminMemberQueue\(\)/);
});
