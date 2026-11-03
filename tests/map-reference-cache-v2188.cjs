const fs=require('node:fs'),vm=require('node:vm'),assert=require('node:assert/strict'),path=require('node:path');
const root=path.join(__dirname,'..'),read=n=>fs.readFileSync(path.join(root,n),'utf8');
(async()=>{
 let now=0,reads=0;
 const context={window:{},sessionStorage:{removeItem(){},setItem(){}},Date:{now:()=>now},Promise,Map,Error};
 vm.createContext(context);
 vm.runInContext(read('shared-runtime-v2035.mjs').replaceAll('export ',''),context);
 vm.runInContext(read('map-reference-cache-v2188.mjs').replace(/^import[^\n]*\n/,'').replaceAll('export ',''),context);
 context.client={auth:{getSession:async()=>({data:{session:null}})}};
 const session=id=>context.setSharedSession({user:{id}});
 const payload={data:{geometry_geojson:{type:'Polygon',coordinates:[Array(200).fill([99,18])]}}};
 context.loader=async()=>{reads++;return payload};
 const load=(resource='community:fixture')=>context.readMapReference(context.client,resource,context.loader);
 session('actor-a');
 const replies=await Promise.all(Array.from({length:20},()=>load()));
 assert.equal(reads,1,'simultaneous opens share one geometry request');assert(replies.every(r=>r===payload));
 now+=60000;await load();assert.equal(reads,1,'reopen after one minute stays cached');
 await load('community:other');assert.equal(reads,2,'different community has a separate response');
 await load('community-boundaries-legacy');await load('community-boundaries-v1854');assert.equal(reads,4,'RPCs with different permission scopes stay separate');
 session('actor-b');await load();assert.equal(reads,5,'account switch cannot reuse another account geometry');
 now+=600001;await load();assert.equal(reads,6,'expired geometry is fetched again');
 context.invalidateShared('map-reference-v2188:');await load();assert.equal(reads,7,'explicit invalidation reloads');
 let fail=true;context.loader=async()=>{reads++;return fail?{data:null,error:new Error('temporary')}:payload};
 assert((await load('retry')).error);fail=false;assert.equal((await load('retry')).error,undefined);assert.equal(reads,9,'errors are not cached');
 context.clearSharedAuth();assert((await load()).error);assert.equal(reads,9,'signed-out reads never fetch geometry');
 for(const name of ['community-gis-v1822.mjs','community-workflow-v1822.mjs','my-houses-mobile-v1820.mjs']){
  const source=read(name);assert(source.includes('readMapReference('));
  assert(!/readMapReference\([^;\n]*(?:check_house_location|update_house_coordinates)/.test(source),'validation and writes must stay live');
 }
 assert(read('app.js').includes('const HOUSEHOLD_CACHE_MS_V2039 = 300000;'));
 const bytes=Buffer.byteLength(JSON.stringify(payload));
 console.log(JSON.stringify({passed:true,repeat_open_fixture:{opens:20,before_requests:20,after_requests:1,before_bytes:20*bytes,after_bytes:bytes,reduction_percent:95},account_isolation:true,expiry:true,error_retry:true,logout:true,live_validation:true}));
})().catch(e=>{console.error(e);process.exitCode=1});
