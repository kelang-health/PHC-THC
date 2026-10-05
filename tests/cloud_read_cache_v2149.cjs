const fs=require('fs'),vm=require('vm'),assert=require('assert/strict');
(async()=>{const app=fs.readFileSync('app.js','utf8'),runtime=fs.readFileSync('shared-runtime-v2035.mjs','utf8');
const cache=runtime.slice(runtime.indexOf('export async function sharedCall('),runtime.indexOf('export function isPortalViewActive(')).replaceAll('export ','');
const start=app.indexOf('async function loadHealthHistory()'),end=app.indexOf('  if(error)',start);
const history=app.slice(start,end)+'return {data,error};}';let reads=0;
const query={select(){return this},order(){return this},limit(){return Promise.resolve({data:[],error:null})}};
const ctx={state:{cache:new Map(),inflight:new Map()},Date,Promise,portalView:'health',currentProfile:{user_id:'a'},supabase:{from(){reads++;return query}}};vm.createContext(ctx);vm.runInContext(cache+'\n'+history,ctx);
await Promise.all([ctx.loadHealthHistory(),ctx.loadHealthHistory()]);assert.equal(reads,1);await ctx.loadHealthHistory();assert.equal(reads,1);
ctx.invalidateShared('health-history-v2149:');await ctx.loadHealthHistory();assert.equal(reads,2);
ctx.portalView='work';await ctx.loadHealthHistory();assert.equal(reads,2);
ctx.portalView='health';ctx.currentProfile.user_id='b';await ctx.loadHealthHistory();assert.equal(reads,3);console.log('History concurrent reads deduplicated, cached, invalidated after write, inactive skipped, user isolated passed');})();

