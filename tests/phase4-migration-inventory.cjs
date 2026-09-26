#!/usr/bin/env node
'use strict';
// Inventory-only Phase 4 gate. Reads SQL FILENAMES, never SQL contents or secrets.
const fs=require('node:fs'),path=require('node:path'),assert=require('node:assert/strict');
const manifest=JSON.parse(fs.readFileSync(path.resolve(__dirname,'../database/phase2/migration-history-required-20260924.json'),'utf8'));
const required=manifest.required.map(x=>String(x.version));
assert(required.length>0,'Required migration history is empty');
assert(required.every(x=>/^\d{14}$/.test(x)),'Invalid required migration version');
assert.equal(required.length,new Set(required).size,'Duplicate required migration version');
const evaluate=names=>{
 const versionFiles=new Map(),invalid=[];
 for(const name of names){
   if(!name.toLowerCase().endsWith('.sql'))continue;
   const m=name.match(/^(\d{14})_.+\.sql$/i);
   if(!m){invalid.push(name);continue;}
   if(versionFiles.has(m[1]))invalid.push('duplicate version: '+m[1]);
   versionFiles.set(m[1],name);
 }
 const needed=new Set(required);
 return {required:required.length,local:versionFiles.size,
  matched:required.filter(v=>versionFiles.has(v)).length,
  missing:manifest.required.filter(x=>!versionFiles.has(String(x.version))).map(x=>({version:x.version,name:x.name})),
  extra:[...versionFiles.entries()].filter(([v])=>!needed.has(v)).map(([version,name])=>({version,name})),invalid};
};
const synthetic=evaluate(['20260101000000_alpha.sql','20260101000001_beta.sql','not_a_version.sql']);
assert.equal(synthetic.invalid.length,1);
assert(synthetic.extra.length>=0);
const empty=evaluate([]);
assert.equal(empty.missing.length,required.length);
if(process.argv.includes('--self-test')||process.argv.includes('--manifest-only')){
 console.log('PASS: manifest format, unique required versions, safe filename-only inventory fixtures ('+required.length+' recorded migrations)');
 process.exit(0);
}
const idx=process.argv.indexOf('--source');
assert(idx>=0&&process.argv[idx+1],'Usage: node tests/phase4-migration-inventory.cjs --source <local-migrations-directory>');
const directory=path.resolve(process.argv[idx+1]);
assert(fs.existsSync(directory)&&fs.statSync(directory).isDirectory(),'BLOCKED: local migrations directory not found: '+directory);
const findings=evaluate(fs.readdirSync(directory));
console.log(JSON.stringify({source:directory,...findings},null,2));
if(findings.missing.length||findings.extra.length||findings.invalid.length){
 console.error('BLOCKED: migration history differs from recorded project history. Do not db reset or deploy.');
 process.exitCode=2;
}else console.log('PASS: version manifest complete; actual SQL content/replay/API tests are STILL required.');
