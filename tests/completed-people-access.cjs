const fs=require('node:fs'),assert=require('node:assert/strict');
const app=fs.readFileSync('app.js','utf8'),html=fs.readFileSync('index.html','utf8');
assert.match(app,/allOption.hidden=false;allOption.disabled=false/);
assert.ok(!app.includes("if(filter==='all'&&currentProfile?.role!=='admin')"));
assert.match(app,/health-view-history.*setHealthTargetFilter\('all'\)/);
assert.match(app,/health_worklist_assignment_json_v2054/);
assert.match(html,/id="health-view-history"/);
console.log('Completed-person lookup uses existing scoped RPC for all roles');
