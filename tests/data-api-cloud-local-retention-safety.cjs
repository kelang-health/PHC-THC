#!/usr/bin/env node
'use strict';
// Planning-only, metadata-only guard. Never connects to Cloud/JHCIS or deletes rows.
const assert=require('node:assert/strict');
const policy=Object.freeze({
 cloudReferenceTables:['health_persons','houses','profiles','volunteers','health_ncd_screenings','household_member_requests'],
 currentCloudCaches:['health_screening_target_cache_v2030','report_snapshot_cache_v2031','health_screening_plan_v2023'],
 candidateRetentionReview:['performance_monitor_samples_v2067','house_reconcile_audit_v2048'],
 localArchiveTables:['jr_cloud_archive_registry_v1','jr_cloud_archive_batches_v1']
});
function decide(table,evidence={}){
 if(policy.cloudReferenceTables.includes(table))
  return {classification:'retain-cloud-reference',purgeAllowed:false,reason:'active/reference/FK or user-facing dependency'};
 if(policy.currentCloudCaches.includes(table))
  return {classification:'redesign-before-moving',purgeAllowed:false,reason:'still queried by active Cloud paths; test local precompute and scoped projection first'};
 if(policy.candidateRetentionReview.includes(table))
  return {classification:'review-only',purgeAllowed:false,reason:'audit/monitor retention, restore, compliance and live reader dependencies unverified'};
 if(policy.localArchiveTables.includes(table))
  return {classification:'existing-local-archive',purgeAllowed:false,reason:'the local archive is a source for restoration, not a Cloud delete instruction'};
 return {classification:'unclassified',purgeAllowed:false,reason:'unknown table: explicit dependency and retention review required'};
}
const syntheticEvidence=[
 {table:'health_persons',localRecordCount:10380,cloudRecordCount:10380,keysMatch:true,oneReadbackSample:true},
 {table:'houses',localRecordCount:94,cloudRecordCount:94,keysMatch:true,oneReadbackSample:true}
];
for(const e of syntheticEvidence){
 assert.equal(decide(e.table,e).purgeAllowed,false,'Archive key-count agreement MUST NOT authorize Cloud deletion');
}
for(const table of Object.values(policy).flat()){
 const decision=decide(table,{verified:true,explicitUserPolicy:true});
 assert.equal(decision.purgeAllowed,false,'No destructive Cloud action belongs in metadata-only planning gate: '+table);
}
assert.equal(decide('private.line_oauth_requests_v2012').purgeAllowed,false,'Unknown/sensitive retention cannot be inferred');
console.log('PASS: metadata-only Cloud→Local tiering policy rejects all automatic Cloud deletes, including verified archive fixtures');
