const assert=require('node:assert/strict');
(async()=>{
 const {EXPORT_DATASETS,validExportRange,buildExportQuery,fetchExportDatasets}=await import('../field-export-v2189.mjs');
 assert(validExportRange('2026-10-01','2026-10-31'));assert(!validExportRange('2026-02-30','2026-03-01'));assert(!validExportRange('2026-11-02','2026-11-01'));
 let calls=[];
 const client={from(table){const call={table,filters:[],order:[]};calls.push(call);return {select(v){call.columns=v;return this},eq(k,v){call.filters.push(['eq',k,v]);return this},gte(k,v){call.filters.push(['gte',k,v]);return this},lt(k,v){call.filters.push(['lt',k,v]);return this},order(k){call.order.push(k);return this},range(a,b){call.range=[a,b];return Promise.resolve({data:a===0&&table==='field_export_ncd_v200'?Array.from({length:500},(_,i)=>({id:i})):[],error:null})}}}};
 const options={keys:['ncd'],start:'2026-10-01',end:'2026-10-31',details:false};
 const scope={mode:'self',role:'user',volunteerPid:7};
 const sheets=await fetchExportDatasets(client,options,scope);assert.equal(sheets.length,1);assert.equal(sheets[0][1].length,500);assert.equal(calls.length,2);assert(calls.every(c=>c.table==='field_export_ncd_v200'));assert(!calls[0].columns.includes('*'));assert(calls[0].columns.includes('pulse'));assert(!calls[0].columns.split(',').includes('id'));
 assert.deepEqual(calls[0].filters,[['eq','volunteer_pid',7],['gte','screened_on','2026-10-01'],['lt','screened_on','2026-11-01']]);assert.deepEqual(calls.map(c=>c.range),[[0,499],[500,999]]);
 calls=[];await buildExportQuery(client,'child',{...options,details:true},{mode:'community',role:'staff',community:'fixture'});assert(calls[0].columns.includes('domains'));assert(calls[0].filters.some(f=>f[2]==='2026-10-01T00:00:00+07:00'));assert(calls[0].filters.some(f=>f[2]==='2026-11-01T00:00:00+07:00'));
 calls=[];await fetchExportDatasets(client,{...options,keys:['growth','growth']},{mode:'volunteer',role:'staff',ownerPid:22});assert.equal(calls.length,1);assert.deepEqual(calls[0].filters[0],['eq','volunteer_pid',22]);assert(!calls[0].columns.includes('nutrition_result'));
 await assert.rejects(()=>fetchExportDatasets(client,options,scope,()=>false),/ขอบเขตเปลี่ยน/);
 assert.throws(()=>buildExportQuery(client,'ncd',options,{mode:'self',role:'user'}),/อสม/);
 assert.throws(()=>buildExportQuery(client,'ncd',options,{mode:'all',role:'user'}),/ขอบเขต/);
 for(const d of Object.values(EXPORT_DATASETS))assert(!d.columns.includes('*'));
 console.log('PASS: chosen dataset only, bounded service dates/Bangkok timezone, optional detail columns, stable pagination, scope filtering, fail-closed missing owner, scope-change cancellation');
})().catch(e=>{console.error(e);process.exitCode=1});
