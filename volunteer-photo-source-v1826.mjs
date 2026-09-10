const VERSION='1.8.27';
let supabase=null,profile=null,photoRows=[],observer=null,mutationObserver=null;
const $=(s,r=document)=>r.querySelector(s);

function validPhotoUrl(url){
  try{
    const u=new URL(String(url||''));
    return u.protocol==='https:' && u.hostname==='lh3.googleusercontent.com';
  }catch{return false;}
}

async function loadData(){
  const {data:{session}}=await supabase.auth.getSession();
  if(!session)return;
  const {data:p,error:pErr}=await supabase.from('profiles').select('user_id,role,community,volunteer_pid,active').eq('user_id',session.user.id).maybeSingle();
  if(pErr||!p?.active)return;
  profile=p;
  const {data,error}=await supabase.rpc('volunteer_registry_profiles_v2');
  if(error)return;
  photoRows=(data||[]).filter(r=>!String(r.photo_object_path||'').trim()&&validPhotoUrl(r.photo_source_url));
}

function ensureImg(avatar,row){
  if(!avatar||!row||avatar.dataset.v26Ready==='1')return;
  avatar.dataset.v26Ready='1';
  const fallback=avatar.querySelector(':scope > span');
  let img=avatar.querySelector('img');
  if(!img){
    img=document.createElement('img');
    img.hidden=true;
    img.loading='lazy';
    img.decoding='async';
    img.referrerPolicy='no-referrer';
    img.alt=`รูป ${row.display_name||'อสม.'}`;
    img.style.width='100%';img.style.height='100%';img.style.objectFit='cover';img.style.position='absolute';img.style.inset='0';
    avatar.appendChild(img);
  }
  const load=()=>{
    if(img.dataset.srcSet==='1')return;
    img.dataset.srcSet='1';
    img.onload=()=>{img.hidden=false;if(fallback)fallback.hidden=true;};
    img.onerror=()=>{img.hidden=true;if(fallback)fallback.hidden=false;};
    img.src=row.photo_source_url;
  };
  if('IntersectionObserver'in window){
    if(!observer)observer=new IntersectionObserver(entries=>entries.forEach(e=>{if(e.isIntersecting){observer.unobserve(e.target);const fn=e.target.__v26Load;delete e.target.__v26Load;if(fn)fn();}}),{rootMargin:'180px'});
    avatar.__v26Load=load;observer.observe(avatar);
  }else load();
}

function applyPhotos(){
  if(!profile||!photoRows.length)return;
  const byPid=new Map(photoRows.map(r=>[String(r.source_pid),r]));
  document.querySelectorAll('.vreg25-card[data-v25-card]').forEach(card=>{
    const row=byPid.get(String(card.dataset.v25Card));
    if(row)ensureImg(card.querySelector('.vreg25-avatar'),row);
  });
  if(profile.role==='user'&&profile.volunteer_pid){
    const row=byPid.get(String(profile.volunteer_pid));
    const self=document.querySelector('[data-vself25] .vreg25-avatar');
    if(row&&self)ensureImg(self,row);
  }
}

function setVersion(){const e=$('.login-version');if(e)e.textContent=`Cloud v${VERSION}`;}

async function start(){
  await loadData();applyPhotos();setVersion();
  const portal=$('#portal');
  if(portal&&'MutationObserver'in window){
    let t=null;
    mutationObserver=new MutationObserver(()=>{clearTimeout(t);t=setTimeout(applyPhotos,100);});
    mutationObserver.observe(portal,{subtree:true,childList:true,attributes:true,attributeFilter:['hidden']});
  }
}

export async function initVolunteerPhotoSource1826(url,key){
  if(window.__PHC_VOLUNTEER_PHOTO_SOURCE_1826__)return;
  window.__PHC_VOLUNTEER_PHOTO_SOURCE_1826__=true;
  const {createClient}=await import('https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2/+esm');
  supabase=createClient(url,key,{auth:{persistSession:true,autoRefreshToken:false,detectSessionInUrl:false}});
  if(document.readyState==='loading')document.addEventListener('DOMContentLoaded',start,{once:true});else start();
}
