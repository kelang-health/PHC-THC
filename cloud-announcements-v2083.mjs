import { getSharedSupabase, getSharedProfile, bindPortalActivation, isPortalViewActive } from './shared-runtime-v2035.mjs?v=2.0.35';
/* Cloud phase 4: authenticated read-only notices. A separate Local phase 3 will publish. */
const TABLE='cloud_announcements_v2083',SUMMARY='id,kind,title,summary,home_featured,image_path,priority,published_at,ends_at';
const TTL=5*60*1000, PAGE_SIZE=20;
let supabase=null,profile=null,cache=[],cacheAt=0,cacheFor='',loading=null,viewer=null,allRows=[],allExhausted=false,requestSerial=0;
const $=(s,r=document)=>r.querySelector(s);
const esc=v=>String(v??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
const label=k=>({news:'ข่าวประชาสัมพันธ์',status:'สถานะระบบ',event:'กิจกรรมสุขภาพ'})[k]||'ข่าวสาร';
const shortDate=v=>{if(!v)return '';try{return new Date(v).toLocaleDateString('th-TH',{timeZone:'Asia/Bangkok',dateStyle:'medium'});}catch{return '';}};
function home(){return $('#cloud-announcements-v2083');}
function shut(){if(viewer){viewer.close();viewer.remove();viewer=null;}}
function reset(){requestSerial++;cache=[];cacheAt=0;cacheFor='';loading=null;allRows=[];allExhausted=false;home()?.setAttribute('hidden','');shut();}
function currentKey(){return profile?.user_id?String(profile.user_id):'';}
function safeImagePath(path){return typeof path==='string'&&/^announcements\/[a-zA-Z0-9_.\/-]{1,280}$/.test(path)&&!path.includes('/../')?path:null;}
function imgMarkup(path){const safe=safeImagePath(path);if(!safe)return '';const url=supabase.storage.from('osm-public-assets').getPublicUrl(safe)?.data?.publicUrl;if(!url)return '';return `<img src="${esc(url)}" loading="lazy" decoding="async" alt="ภาพประกอบประกาศ">`;}
function queryPage(start){
 return supabase.from(TABLE).select(SUMMARY)
 .order('home_featured',{ascending:false}).order('priority',{ascending:false})
 .order('published_at',{ascending:false}).order('id',{ascending:true})
 .range(start,start+PAGE_SIZE-1);
}
function homeCard(row){
 return `<article class="cn83-entry" data-kind="${esc(row.kind)}"><small>${label(row.kind)}${row.ends_at?' · ถึง '+esc(shortDate(row.ends_at)):''}</small><strong>${esc(row.title)}</strong><p>${esc(row.summary||'อ่านรายละเอียดประกาศ')}</p><button type="button" data-cn83-detail="${esc(row.id)}">อ่านรายละเอียด</button></article>`;
}
function renderHome(){
 const host=home();
 if(!host||!isPortalViewActive('overview')||!cache.length){if(host)host.hidden=true;return;}
 const top=cache.slice(0,2);
 host.innerHTML=`<div class="cn83-heading"><h2>📣 ข่าวสารและกิจกรรมสุขภาพ</h2><button type="button" data-cn83-all>ดูทั้งหมด</button></div>${top.map(homeCard).join('')}`;
 host.hidden=false;
 host.querySelector('[data-cn83-all]').onclick=()=>openAll();
 host.querySelectorAll('[data-cn83-detail]').forEach(b=>b.onclick=()=>openDetail(b.dataset.cn83Detail));
}
async function loadHome(){
 const host=home();if(!host||!isPortalViewActive('overview'))return;
 try{
   profile=await getSharedProfile(supabase);
   if(!profile?.user_id||profile.active===false){host.hidden=true;return;}
   const key=currentKey();
   if(cacheAt&&cacheFor===key&&Date.now()-cacheAt<TTL){renderHome();return;}
   if(loading)return;
   const serial=++requestSerial;
   loading=(async()=>{
     const {data,error}=await queryPage(0);if(error)throw error;
     if(serial!==requestSerial||!isPortalViewActive('overview')||currentKey()!==key)return;
     cache=Array.isArray(data)?data:[];cacheAt=Date.now();cacheFor=key;
     renderHome();
   })();
   await loading;
 }catch{host.hidden=true;}finally{loading=null;}
}
function dialog(title){
 shut();const d=document.createElement('dialog');d.className='cn83-dialog';
 d.innerHTML=`<div class="cn83-modal"><div class="cn83-modal-head"><h2>${esc(title)}</h2><button type="button" data-cn83-close aria-label="ปิดหน้าข่าวสาร">ปิด ✕</button></div><div data-cn83-body></div></div>`;
 document.body.appendChild(d);viewer=d;d.querySelector('[data-cn83-close]').onclick=()=>d.close();
 d.addEventListener('close',()=>{if(viewer===d)viewer=null;d.remove();},{once:true});
 d.showModal();return d;
}
function itemRows(items){
 return items.map(r=>`<article class="cn83-row"><small>${esc(label(r.kind))} · ${esc(shortDate(r.published_at))}</small><strong>${esc(r.title)}</strong><p>${esc(r.summary||'อ่านรายละเอียดประกาศ')}</p><button type="button" data-cn83-detail="${esc(r.id)}">อ่านรายละเอียด</button></article>`).join('');
}
async function openAll(){
 const d=dialog('ข่าวสารและกิจกรรมทั้งหมด'),body=$('[data-cn83-body]',d);
 allRows=cache.slice();allExhausted=cache.length<PAGE_SIZE;
 const show=()=>{
   if(!d.open)return;
   body.innerHTML=`<div class="cn83-muted">แสดงเฉพาะประกาศที่เผยแพร่และอยู่ในช่วงเวลาที่กำหนด</div>${itemRows(allRows)}${allExhausted?'':'<button type="button" data-cn83-more>ดูรายการเพิ่มเติม</button>'}`;
   body.querySelectorAll('[data-cn83-detail]').forEach(b=>b.onclick=()=>openDetail(b.dataset.cn83Detail));
   const more=$('[data-cn83-more]',body);if(more)more.onclick=async()=>{
     more.disabled=true;more.textContent='กำลังโหลด…';
     try{const {data,error}=await queryPage(allRows.length);if(error)throw error;
       if(!d.open)return;const next=Array.isArray(data)?data:[];allRows.push(...next);allExhausted=next.length<PAGE_SIZE;show();
     }catch{if(d.open){more.disabled=false;more.textContent='โหลดไม่สำเร็จ · ลองอีกครั้ง';}}
   };
 };
 show();
}
async function openDetail(id){
 if(!/^[0-9a-f-]{36}$/i.test(String(id||'')))return;
 const d=dialog('รายละเอียดประกาศ'),body=$('[data-cn83-body]',d);
 body.textContent='กำลังโหลดรายละเอียด…';
 try{
   const {data,error}=await supabase.from(TABLE).select('id,kind,title,summary,body,image_path,published_at,ends_at,booking_enabled,booking_opens_at,booking_closes_at,event_subtype,hcv_enabled,hbsag_enabled,event_contact_phone,eligibility_notice,preparation_notice').eq('id',id).maybeSingle();
   if(error)throw error;if(!d.open)return;
   if(!data){body.textContent='ไม่พบประกาศนี้ หรือสิ้นสุดช่วงเวลาแสดงแล้ว';return;}
   body.innerHTML=`<article class="cn83-detail"><small>${esc(label(data.kind))} · ${esc(shortDate(data.published_at))}</small><h3>${esc(data.title)}</h3><p class="cn83-muted">${esc(data.summary||'')}</p>${imgMarkup(data.image_path)}${String(data.body||'').trim()?`<p>${esc(data.body)}</p>`:''}${data.event_subtype==='hcv_hbsag'?`<div class="cn83-hcv-info"><p>รายการตรวจที่เปิดรับ: ${[data.hcv_enabled?'Anti-HCV':'',data.hbsag_enabled?'HBsAg':''].filter(Boolean).join(' + ')}</p>${data.eligibility_notice?`<p><strong>กลุ่มเป้าหมาย:</strong> ${esc(data.eligibility_notice)}</p>`:''}${data.preparation_notice?`<p><strong>ข้อควรทราบ:</strong> ${esc(data.preparation_notice)}</p>`:''}${data.event_contact_phone?`<p>สอบถามหน่วยบริการ: ${esc(data.event_contact_phone)}</p>`:''}</div>`:''}${data.kind==='event'?(data.booking_enabled?'<button type="button" data-cn83-book class="cn83-book">ตรวจสอบสิทธิ์ / จองกิจกรรม</button><small class="cn83-muted">การจองไม่ใช่การได้รับบริการจริง</small>':'<small class="cn83-muted">กิจกรรมนี้ยังไม่เปิดรับจองหรือปิดรับจองแล้ว</small>'):''}</article>`;
   if(data.kind==='event'&&data.booking_enabled){const button=body.querySelector('[data-cn83-book]');if(button)button.onclick=async()=>{button.disabled=true;try{if(data.event_subtype==='hcv_hbsag'){
     const {openHcvBookingV2088}=await import('./cloud-hcv-booking-v2088.mjs?v=2.0.88.1&p=2088');
     if(d.open)await openHcvBookingV2088({client:supabase,event:data,body,back:()=>openDetail(id)});
    }else{
     const {openEventBookingV2085}=await import('./cloud-event-booking-v2085.mjs?v=2.0.85.1&p=2085');
     if(d.open)await openEventBookingV2085({client:supabase,event:data,body,back:()=>openDetail(id)});
    }}catch{if(d.open){button.disabled=false;body.insertAdjacentHTML('beforeend','<p class="cn83-muted">โหลดระบบจองไม่สำเร็จ กรุณาลองใหม่</p>');}}};}
 }catch{if(d.open)body.textContent='โหลดรายละเอียดไม่สำเร็จ กรุณาลองใหม่';}
}
function start(){
 bindPortalActivation('overview',()=>{loadHome().catch(()=>{});},{runIfActive:true});
 document.addEventListener('phc:portal-view-changed',e=>{if(e.detail?.view!=='overview')home()?.setAttribute('hidden','');});
 document.addEventListener('phc:content-refresh',()=>{cacheAt=0;if(isPortalViewActive('overview'))loadHome().catch(()=>{});});
 document.addEventListener('phc:auth-ready',e=>{const id=String(e.detail?.userId||'');if(cacheFor&&cacheFor!==id)reset();});
 supabase.auth.onAuthStateChange((event)=>{if(event==='SIGNED_OUT')reset();});
 // Refresh only when the signed-in overview is visible. A hidden/expired notice
 // disappears automatically within the five-minute cache interval, without
 // additional background requests on other pages or the sign-in screen.
 const refreshVisible=()=>{if(document.visibilityState==='visible'&&isPortalViewActive('overview')&&(!cacheAt||Date.now()-cacheAt>=TTL))loadHome().catch(()=>{});};
 document.addEventListener('visibilitychange',refreshVisible);
 window.setInterval(refreshVisible,60000);
}
export function initCloudAnnouncements2083(url,key){
 if(window.__PHC_CLOUD_ANNOUNCEMENTS_2083__)return;
 window.__PHC_CLOUD_ANNOUNCEMENTS_2083__=true;
 getSharedSupabase(url,key).then(client=>{supabase=client;start();}).catch(()=>{home()?.setAttribute('hidden','');});
}
