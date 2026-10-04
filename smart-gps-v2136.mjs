const DEFAULT_TIMEOUT_MS=20000;
const WARMUP_MS=3000;
const TARGET_ACCURACY_M=15;
const MAX_GPS_ACCURACY_M=30;
const CLUSTER_RADIUS_M=20;

function finite(v){return Number.isFinite(Number(v));}
function distanceM(a,b){
  const rad=Math.PI/180,R=6371000;
  const p1=Number(a.lat)*rad,p2=Number(b.lat)*rad;
  const dp=(Number(b.lat)-Number(a.lat))*rad,dl=(Number(b.lng)-Number(a.lng))*rad;
  const x=Math.sin(dp/2)**2+Math.cos(p1)*Math.cos(p2)*Math.sin(dl/2)**2;
  return 2*R*Math.atan2(Math.sqrt(x),Math.sqrt(Math.max(0,1-x)));
}
function qualityFor(accuracy,stable){
  if(!finite(accuracy))return'unknown';
  const a=Number(accuracy);
  if(stable&&a<=10)return'excellent';
  if(stable&&a<=20)return'good';
  if(stable&&a<=30)return'fair';
  return'poor';
}
function analyze(samples,startedAt){
  const usable=samples.filter(s=>finite(s.lat)&&finite(s.lng)&&finite(s.accuracy)&&Number(s.accuracy)>=0&&Number(s.accuracy)<=1000);
  if(!usable.length)return{lat:null,lng:null,accuracy:null,sampleCount:0,stableCount:0,stabilityRadiusM:null,durationMs:Date.now()-startedAt,stable:false,accepted:false,quality:'unknown'};
  let bestCluster=[usable[0]];
  for(const s of usable){
    const cluster=usable.filter(x=>distanceM(s,x)<=CLUSTER_RADIUS_M);
    const bestAcc=Math.min(...cluster.map(x=>Number(x.accuracy)));
    const oldBestAcc=Math.min(...bestCluster.map(x=>Number(x.accuracy)));
    if(cluster.length>bestCluster.length||(cluster.length===bestCluster.length&&bestAcc<oldBestAcc))bestCluster=cluster;
  }
  const selected=bestCluster.slice().sort((a,b)=>Number(a.accuracy)-Number(b.accuracy)||Number(b.ts)-Number(a.ts))[0];
  const radius=bestCluster.reduce((m,x)=>Math.max(m,distanceM(selected,x)),0);
  const accuracy=Number(selected.accuracy);
  const durationMs=Date.now()-startedAt;
  const stable=(bestCluster.length>=3&&radius<=CLUSTER_RADIUS_M)||(accuracy<=10&&bestCluster.length>=2&&radius<=15);
  const excellentSingleFallback=!stable&&durationMs>=12000&&accuracy<=8;
  const accepted=(stable&&accuracy<=MAX_GPS_ACCURACY_M)||excellentSingleFallback;
  return{
    lat:Number(selected.lat),lng:Number(selected.lng),accuracy,
    sampleCount:usable.length,stableCount:bestCluster.length,
    stabilityRadiusM:Math.round(radius*10)/10,
    durationMs,stable,accepted,
    quality:excellentSingleFallback?'good':qualityFor(accuracy,stable),
    acceptanceMode:excellentSingleFallback?'excellent_single_timeout':stable?'stable_cluster':'not_ready'
  };
}
export function gpsPointReady(point){
  if(!point)return false;
  if(point.source!=='gps')return true;
  return point.gpsAccepted===true&&finite(point.accuracy)&&Number(point.accuracy)<=MAX_GPS_ACCURACY_M;
}
export function smartGpsProgressText(s){
  if(!s||!finite(s.accuracy))return'กำลังค้นหาตำแหน่งที่แม่นที่สุด…';
  const a=Math.round(Number(s.accuracy));
  if(s.accepted&&a<=10)return`GPS ±${a} ม. · แม่นยำมาก พร้อมใช้งาน`;
  if(s.accepted&&a<=20)return`GPS ±${a} ม. · ตำแหน่งนิ่ง พร้อมใช้งาน`;
  if(s.accepted)return`GPS ±${a} ม. · พอใช้ กรุณาตรวจหมุดบนแผนที่`;
  if(a<=30)return`GPS ±${a} ม. · กำลังตรวจความนิ่ง (${s.stableCount||1} จุด)`;
  return`GPS ±${a} ม. · ยังคลาดเคลื่อน กำลังปรับความแม่นยำ…`;
}
export function smartGpsFinalText(s){
  if(!s)return'จับตำแหน่งไม่สำเร็จ';
  if(s.accepted)return smartGpsProgressText(s);
  const a=finite(s.accuracy)?Math.round(Number(s.accuracy)):null;
  return a==null?'ยังหาพิกัดที่เชื่อถือได้ กรุณาลองใหม่':`GPS ดีที่สุด ±${a} ม. แต่ยังไม่นิ่ง/แม่นพอ · กดจับใหม่หรือปรับหมุดด้วยนิ้ว`;
}
let permissionRetryHandler=null;

export async function gpsPermissionState(){
  if(typeof navigator==='undefined'||!navigator.permissions?.query)return'unknown';
  try{
    const status=await navigator.permissions.query({name:'geolocation'});
    return status?.state||'unknown';
  }catch{return'unknown';}
}

function permissionDeviceGuide(){
  const ua=typeof navigator==='undefined'?'':String(navigator.userAgent||'');
  const ios=/iPad|iPhone|iPod/.test(ua)||(navigator.platform==='MacIntel'&&navigator.maxTouchPoints>1);
  if(ios)return [
    '1) เปิด การตั้งค่า > ความเป็นส่วนตัวและความปลอดภัย > บริการหาตำแหน่งที่ตั้ง',
    '2) ใน Safari แตะเมนูเว็บไซต์ (aA) > การตั้งค่าเว็บไซต์ > ตำแหน่งที่ตั้ง > อนุญาต',
    '3) กลับมาพระบาท พลัส แล้วกด “ตรวจสอบ GPS อีกครั้ง”'
  ];
  if(/Android/i.test(ua))return [
    '1) เปิด “ตำแหน่ง (Location)” ของโทรศัพท์',
    '2) ใน Chrome แตะไอคอนด้านซ้ายของที่อยู่เว็บ > สิทธิ์/การตั้งค่าเว็บไซต์ > ตำแหน่ง > อนุญาต',
    '3) กลับมาพระบาท พลัส แล้วกด “ตรวจสอบ GPS อีกครั้ง”'
  ];
  return [
    '1) เปิด Location/ตำแหน่งของอุปกรณ์',
    '2) ที่แถบที่อยู่เว็บ เปิด Site permissions/สิทธิ์เว็บไซต์ > Location > Allow',
    '3) กลับมาพระบาท พลัส แล้วกด “ตรวจสอบ GPS อีกครั้ง”'
  ];
}

function ensureGpsPermissionDialog(){
  if(typeof document==='undefined')return null;
  let overlay=document.getElementById('phc-gps-permission-help-v2178');
  if(overlay)return overlay;
  const style=document.createElement('style');
  style.id='phc-gps-permission-style-v2178';
  style.textContent='#phc-gps-permission-help-v2178{position:fixed;inset:0;z-index:9800;background:#102e2894;display:flex;align-items:center;justify-content:center;padding:16px}'
    +'#phc-gps-permission-help-v2178[hidden]{display:none!important}'
    +'.phc-gps-permission-card{width:min(560px,100%);max-height:92dvh;overflow:auto;background:#fff;border-radius:22px;padding:20px;box-shadow:0 24px 80px #0005;color:#173c34}'
    +'.phc-gps-permission-card h2{margin:0 0 8px;font-size:1.35rem}.phc-gps-permission-card p{line-height:1.6;margin:.45rem 0}'
    +'.phc-gps-permission-state{padding:10px 12px;border-radius:13px;background:#fff5dd;border:1px solid #ead69d;font-weight:850;color:#6a5218}'
    +'.phc-gps-permission-steps{margin:12px 0;padding:12px 14px;border-radius:14px;background:#f3f8f6;display:grid;gap:8px;line-height:1.55}'
    +'.phc-gps-permission-note{font-size:.93rem;color:#5b706a}.phc-gps-permission-actions{display:grid;grid-template-columns:1fr 1.35fr;gap:10px;margin-top:15px}'
    +'.phc-gps-permission-actions button{min-height:62px;border:0;border-radius:14px;font:inherit;font-size:1.02rem;font-weight:900;cursor:pointer}'
    +'.phc-gps-permission-close{background:#e7efec;color:#294b44}.phc-gps-permission-retry{background:#0b6f60;color:#fff}'
    +'@media(max-width:560px){#phc-gps-permission-help-v2178{padding:0;align-items:flex-end}.phc-gps-permission-card{width:100%;max-height:96dvh;border-radius:22px 22px 0 0;padding:18px 14px max(22px,env(safe-area-inset-bottom))}.phc-gps-permission-actions{grid-template-columns:1fr}.phc-gps-permission-actions button{min-height:66px;font-size:1.08rem}}';
  document.head.appendChild(style);
  overlay=document.createElement('div');
  overlay.id='phc-gps-permission-help-v2178';
  overlay.hidden=true;
  overlay.innerHTML='<section class="phc-gps-permission-card" role="dialog" aria-modal="true" aria-labelledby="phc-gps-permission-title">'
    +'<h2 id="phc-gps-permission-title">อนุญาตตำแหน่งเพื่อใช้ GPS</h2>'
    +'<p>พระบาท พลัสยังไม่ได้รับอนุญาตให้ใช้ตำแหน่ง จึงไม่สามารถจับพิกัดบ้านได้</p>'
    +'<div class="phc-gps-permission-state" data-gps-permission-state>กำลังตรวจสอบสิทธิ์ตำแหน่ง…</div>'
    +'<div class="phc-gps-permission-steps" data-gps-permission-steps></div>'
    +'<p class="phc-gps-permission-note">หากเคยกด “ไม่อนุญาต” แบบถาวร เบราว์เซอร์อาจไม่แสดงกล่องขออนุญาตซ้ำ จนกว่าจะเปลี่ยนสิทธิ์ของเว็บไซต์เป็น “อนุญาต” ก่อน</p>'
    +'<div class="phc-gps-permission-actions"><button type="button" class="phc-gps-permission-close" data-gps-permission-close>ปิด</button><button type="button" class="phc-gps-permission-retry" data-gps-permission-retry>ตรวจสอบ GPS อีกครั้ง</button></div>'
    +'</section>';
  document.body.appendChild(overlay);
  overlay.querySelector('[data-gps-permission-close]').onclick=()=>{overlay.hidden=true;permissionRetryHandler=null;};
  overlay.addEventListener('click',e=>{if(e.target===overlay){overlay.hidden=true;permissionRetryHandler=null;}});
  overlay.querySelector('[data-gps-permission-retry]').onclick=()=>{
    const retry=permissionRetryHandler;
    overlay.hidden=true;
    permissionRetryHandler=null;
    if(typeof retry==='function')Promise.resolve().then(retry).catch(()=>{});
  };
  return overlay;
}

export async function showGpsPermissionHelp({onRetry}={}){
  const overlay=ensureGpsPermissionDialog();
  if(!overlay)return;
  permissionRetryHandler=typeof onRetry==='function'?onRetry:null;
  const steps=permissionDeviceGuide();
  const stepBox=overlay.querySelector('[data-gps-permission-steps]');
  stepBox.replaceChildren(...steps.map(t=>{const div=document.createElement('div');div.textContent=t;return div;}));
  const state=await gpsPermissionState();
  const status=overlay.querySelector('[data-gps-permission-state]');
  status.textContent=state==='denied'
    ?'สถานะ: ถูกปฏิเสธสิทธิ์ตำแหน่ง — ต้องเปิดสิทธิ์ของเว็บไซต์ก่อน'
    :state==='prompt'
      ?'สถานะ: พร้อมขอสิทธิ์ — กด “ตรวจสอบ GPS อีกครั้ง” แล้วเลือก “อนุญาต”'
      :state==='granted'
        ?'สถานะ: อนุญาตแล้ว — กด “ตรวจสอบ GPS อีกครั้ง”'
        :'สถานะ: กรุณาตรวจ Location และสิทธิ์ตำแหน่งของเบราว์เซอร์';
  overlay.hidden=false;
  overlay.querySelector('[data-gps-permission-retry]')?.focus();
}

export function captureSmartGps({onUpdate,timeoutMs=DEFAULT_TIMEOUT_MS,targetAccuracyM=TARGET_ACCURACY_M}={}){
  return new Promise((resolve,reject)=>{
    if(!navigator.geolocation){reject(Object.assign(new Error('GEO_UNSUPPORTED'),{code:0}));return;}
    const startedAt=Date.now(),samples=[];
    let watchId=null,done=false;
    const finish=(err=null)=>{
      if(done)return;done=true;
      if(watchId!=null)try{navigator.geolocation.clearWatch(watchId);}catch{}
      clearTimeout(timer);
      if(err){reject(err);return;}
      resolve(analyze(samples,startedAt));
    };
    const timer=setTimeout(()=>finish(),timeoutMs);
    watchId=navigator.geolocation.watchPosition(p=>{
      const lat=Number(p.coords.latitude),lng=Number(p.coords.longitude),accuracy=Number(p.coords.accuracy);
      if(!finite(lat)||!finite(lng)||!finite(accuracy))return;
      samples.push({lat,lng,accuracy,ts:Number(p.timestamp)||Date.now()});
      if(samples.length>40)samples.splice(0,samples.length-40);
      const state=analyze(samples,startedAt);
      try{onUpdate?.(state);}catch{}
      if(state.durationMs>=WARMUP_MS&&state.accepted&&state.accuracy<=targetAccuracyM)finish();
      else if(state.durationMs>=8000&&state.accepted&&state.accuracy<=20)finish();
    },e=>{
      try{onUpdate?.({...analyze(samples,startedAt),errorCode:e?.code||0});}catch{}
      if(e?.code===1)finish(Object.assign(new Error('GEO_PERMISSION_DENIED'),{code:1}));
    },{enableHighAccuracy:true,maximumAge:0,timeout:15000});
  });
}

export const SMART_GPS_LIMITS=Object.freeze({
  targetAccuracyM:TARGET_ACCURACY_M,
  maxGpsAccuracyM:MAX_GPS_ACCURACY_M,
  timeoutMs:DEFAULT_TIMEOUT_MS,
  clusterRadiusM:CLUSTER_RADIUS_M
});
