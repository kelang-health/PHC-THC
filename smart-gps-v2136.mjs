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
  const stable=(bestCluster.length>=3&&radius<=CLUSTER_RADIUS_M)||(accuracy<=10&&bestCluster.length>=2&&radius<=15);
  const accepted=stable&&accuracy<=MAX_GPS_ACCURACY_M;
  return{
    lat:Number(selected.lat),lng:Number(selected.lng),accuracy,
    sampleCount:usable.length,stableCount:bestCluster.length,
    stabilityRadiusM:Math.round(radius*10)/10,
    durationMs:Date.now()-startedAt,stable,accepted,
    quality:qualityFor(accuracy,stable)
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
