import fs from 'node:fs';import vm from 'node:vm';import assert from 'node:assert/strict';
const source=fs.readFileSync('house-registration-review-v2202.mjs','utf8');const helpers=source.slice(source.indexOf('export const validHouseId11'),source.indexOf('let client')).replaceAll('export const ','var ');const c=vm.createContext({});vm.runInContext(helpers,c);
const dup={needs_id11:true,original_id11:'52010516419',reopen_reason:'MAIN_DUPLICATE_ID11: 52010516419'};
assert.equal(c.needsId11Review(dup),false);assert.equal(c.reviewColor(dup),'');assert.equal(c.reviewColor({...dup,unassigned_village:true}),'yellow');
assert.equal(c.reviewColor({needs_id11:true,original_id11:'123'}),'red');assert.equal(c.reviewColor({unassigned_village:true,needs_id11:true}),'yellow');assert.equal(c.reviewColor({needs_id11:false}),'');assert(!c.reviewLabel(dup).includes('ซ้ำ'));
console.log('PASS complete duplicate hidden; incomplete red and unassigned yellow preserved');
