#!/usr/bin/env node
'use strict';
const fs=require('node:fs'),path=require('node:path'),assert=require('node:assert/strict');
const root=path.resolve(__dirname,'..');
const contractPath=path.join(root,'database/phase5/release-contract-summary-20260925.json');
const expected=JSON.parse(fs.readFileSync(contractPath,'utf8'));
const sanitized=JSON.parse(fs.readFileSync(path.join(root,'database/phase5/sanitized-baseline-summary-20260925.json'),'utf8'));

assert.equal(expected.schema_version,1);
assert.equal(expected.recorded_migrations,191);
assert.equal(expected.contract_objects,Object.values(expected.categories).reduce((a,b)=>a+b,0));
assert.match(expected.contract_sha256,/^[a-f0-9]{64}$/);
for(const k of ['contains_object_names','contains_sql_bodies','contains_policy_expressions','contains_default_expressions','contains_personal_data'])
  assert.equal(expected[k],false,'Release contract must remain metadata-only: '+k);
assert.deepEqual(Object.keys(expected.categories).sort(),['constraint','function','grant','index','policy','table']);
assert.equal(expected.categories.table,59);
assert.equal(expected.categories.policy,42);
assert.equal(sanitized.schema_version,1);
assert.equal(sanitized.phase,'5C.1');
assert.equal(sanitized.source_file_count,121);
assert.equal(sanitized.previous_manual_review_file_count,106);
assert.equal(Object.values(sanitized.manual_review_primary_buckets).reduce((a,b)=>a+b,0),106);
assert.equal(Object.values(sanitized.all_file_primary_buckets).reduce((a,b)=>a+b,0),121);
assert.equal(sanitized.included_schema_statements,1667);
assert.equal(sanitized.deferred_statements,190);
assert.match(sanitized.combined_baseline_sha256,/^[a-f0-9]{64}$/);
assert.deepEqual(sanitized.validation,{top_level_dml:0,possible_secret_literals:0,possible_personal_literals:0,external_integration_calls_or_urls:0});
for(const k of ['contains_sql_bodies','contains_personal_data','replay_performed','production_changed','release_approved']) assert.equal(sanitized[k],false,'Phase 5C.1 summary must remain metadata-only / non-release: '+k);

const idx=process.argv.indexOf('--observed');
if(idx>=0){
  assert(process.argv[idx+1],'Usage: --observed <metadata-contract-summary.json>');
  const observed=JSON.parse(fs.readFileSync(path.resolve(process.argv[idx+1]),'utf8'));
  assert.equal(observed.recorded_migrations,expected.recorded_migrations,'Migration-count parity failed');
  assert.deepEqual(observed.categories,expected.categories,'Schema object-count parity failed');
  assert.equal(observed.contract_sha256,expected.contract_sha256,'Schema metadata fingerprint parity failed');
  console.log('PASS: isolated replay metadata contract matches Production reference fingerprint');
}else{
  console.log('PASS: Phase 5 metadata-only Production release contract and Phase 5C.1 sanitized-baseline summary are structurally valid; full isolated replay parity is still required before a migration release');
}
