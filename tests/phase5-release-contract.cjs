#!/usr/bin/env node
'use strict';
const fs=require('node:fs'),path=require('node:path'),assert=require('node:assert/strict');
const root=path.resolve(__dirname,'..');
const contractPath=path.join(root,'database/phase5/release-contract-summary-20260925.json');
const expected=JSON.parse(fs.readFileSync(contractPath,'utf8'));

assert.equal(expected.schema_version,1);
assert.equal(expected.recorded_migrations,191);
assert.equal(expected.contract_objects,Object.values(expected.categories).reduce((a,b)=>a+b,0));
assert.match(expected.contract_sha256,/^[a-f0-9]{64}$/);
for(const k of ['contains_object_names','contains_sql_bodies','contains_policy_expressions','contains_default_expressions','contains_personal_data'])
  assert.equal(expected[k],false,'Release contract must remain metadata-only: '+k);
assert.deepEqual(Object.keys(expected.categories).sort(),['constraint','function','grant','index','policy','table']);
assert.equal(expected.categories.table,59);
assert.equal(expected.categories.policy,42);

const idx=process.argv.indexOf('--observed');
if(idx>=0){
  assert(process.argv[idx+1],'Usage: --observed <metadata-contract-summary.json>');
  const observed=JSON.parse(fs.readFileSync(path.resolve(process.argv[idx+1]),'utf8'));
  assert.equal(observed.recorded_migrations,expected.recorded_migrations,'Migration-count parity failed');
  assert.deepEqual(observed.categories,expected.categories,'Schema object-count parity failed');
  assert.equal(observed.contract_sha256,expected.contract_sha256,'Schema metadata fingerprint parity failed');
  console.log('PASS: isolated replay metadata contract matches Production reference fingerprint');
}else{
  console.log('PASS: Phase 5 metadata-only Production release contract is structurally valid; full isolated replay parity is still required before a migration release');
}
