#!/usr/bin/env node
'use strict';
// Audit-only PR path firewall. Does not fetch remote content or change deployment.
const assert=require('node:assert/strict');
const {spawnSync}=require('node:child_process');
const allowed=(path)=>
 /^\.github\/workflows\/data-api-[a-z0-9-]+\.ya?ml$/i.test(path) ||
 /^database\/phase2\/[a-zA-Z0-9_.\/-]+$/.test(path) ||
 /^docs\/data-api-[a-zA-Z0-9_.\/-]+$/.test(path) ||
 /^tests\/(?:data-api-[a-zA-Z0-9_.-]+|phase4-[a-zA-Z0-9_.-]+)$/.test(path);
const fixtures=[
 ['M','index.html',false],['M','app.js',false],['M','script.js',false],
 ['M','supabase/migrations/20260924000000_change.sql',false],
 ['M','.github/workflows/deploy.yml',false],['M','database/phase2/sql_candidate.sql',true],
 ['A','tests/phase4-postgrest-http.cjs',true],['A','.github/workflows/data-api-deployment-readiness.yml',true],
 ['D','tests/phase4-postgrest-http.cjs',false]
];
for(const [status,path,expected] of fixtures)
 assert.equal(status!=='D'&&allowed(path),expected,'PR path rule regression: '+path);
if(process.argv.includes('--self-test')){
 console.log('PASS: PR path firewall rejects frontend, deploy, real migrations and deleted safety files');
 process.exit(0);
}
const [base,head]=process.argv.slice(2);
for(const sha of [base,head])
 assert(/^[a-f0-9]{40}$/i.test(sha||''),'Provide exact pull request base/head commit SHAs');
const out=spawnSync('git',['diff','--name-status','--no-renames',base,head],{encoding:'utf8',maxBuffer:1024*1024});
assert.equal(out.status,0,'Unable to verify PR diff; fail closed: '+(out.stderr||'git diff failed'));
const changes=out.stdout.trim()?out.stdout.trim().split(/\r?\n/).map(line=>{
 const tab=line.indexOf('\t');
 assert(tab>0,'Invalid git diff entry');
 return {status:line.slice(0,tab),path:line.slice(tab+1)};
}):[];
const forbidden=changes.filter(x=>!['A','M'].includes(x.status)||!allowed(x.path));
assert.deepEqual(forbidden,[],'BLOCKED: PR modifies UI/deploy/runtime/migrations or deletes protected files: '+JSON.stringify(forbidden));
assert(changes.length>0,'BLOCKED: no changes verified on PR');
console.log('PASS: '+changes.length+' PR paths limited to review-only Data API tests/docs/workflows; no frontend, runtime, real migration or deployment change');
