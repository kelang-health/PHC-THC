const KEY='__PHC_SHARED_RUNTIME_V2035__';
const state=window[KEY]||(window[KEY]={client:null,clientPromise:null,session:null,profile:null,profileUserId:null,profileAt:0,inflight:new Map(),cache:new Map(),authHooked:false,refreshPromise:null});
if(!Object.prototype.hasOwnProperty.call(state,'clientPromise'))state.clientPromise=null;
if(!Object.prototype.hasOwnProperty.call(state,'refreshPromise'))state.refreshPromise=null;

function hookAuth(client){
  if(state.authHooked||!client?.auth?.onAuthStateChange)return;
  state.authHooked=true;
  client.auth.onAuthStateChange((event,session)=>{
    state.session=session||null;
    if(event==='SIGNED_OUT'){
      state.profile=null;
      state.profileUserId=null;
      state.profileAt=0;
      state.cache.clear();
      state.inflight.clear();
      state.refreshPromise=null;
    }
    if(event==='USER_UPDATED'||event==='TOKEN_REFRESHED'||event==='SIGNED_IN')state.session=session||state.session;
  });
}

export function registerSharedSupabase(client){
  if(client&&!state.client)state.client=client;
  if(state.client)hookAuth(state.client);
  return state.client;
}

export async function getSharedSupabase(url,key){
  if(state.client)return state.client;
  if(state.clientPromise)return state.clientPromise;
  state.clientPromise=(async()=>{
    const {createClient}=await import('https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2/+esm');
    if(!state.client)state.client=createClient(url,key,{auth:{persistSession:true,autoRefreshToken:true,detectSessionInUrl:true}});
    hookAuth(state.client);
    return state.client;
  })().catch(error=>{
    state.clientPromise=null;
    throw error;
  });
  return state.clientPromise;
}

export function setSharedSession(session){state.session=session||null;}
export function setSharedProfile(profile){
  state.profile=profile||null;
  state.profileUserId=profile?.user_id||null;
  state.profileAt=Date.now();
}
export function clearSharedAuth(){
  state.session=null;
  state.profile=null;
  state.profileUserId=null;
  state.profileAt=0;
  state.refreshPromise=null;
  state.cache.clear();
  state.inflight.clear();
}

export function isSharedAuthError(error){
  const status=Number(error?.status||error?.statusCode||error?.response?.status||0);
  const code=String(error?.code||'').toLowerCase();
  const message=String(error?.message||error?.error_description||'').toLowerCase();
  return status===401
    || code.includes('jwt')
    || code==='pgrst301'
    || message.includes('jwt expired')
    || message.includes('invalid jwt')
    || message.includes('token is expired')
    || message.includes('invalid token');
}

export async function refreshSharedSession(client=state.client){
  if(!client?.auth?.refreshSession)return null;
  if(state.refreshPromise)return state.refreshPromise;
  state.refreshPromise=(async()=>{
    const {data,error}=await client.auth.refreshSession();
    if(error)throw error;
    state.session=data?.session||null;
    return state.session;
  })().finally(()=>{state.refreshPromise=null;});
  return state.refreshPromise;
}

export async function getSharedSession(client=state.client){
  if(state.session)return state.session;
  if(!client)return null;
  return sharedCall('auth:session',async()=>{
    const {data:{session},error}=await client.auth.getSession();
    if(error)throw error;
    state.session=session||null;
    return state.session;
  },750);
}

export async function ensureSharedSession(client=state.client,session=state.session,{minValiditySeconds=60}={}){
  let candidate=session||state.session||await getSharedSession(client);
  if(!candidate)return null;
  state.session=candidate;
  const expiresAt=Number(candidate.expires_at||0);
  const nowSeconds=Math.floor(Date.now()/1000);
  if(expiresAt&&expiresAt-nowSeconds<=Math.max(0,Number(minValiditySeconds)||0)){
    candidate=await refreshSharedSession(client);
  }
  return candidate||null;
}

export async function getSharedProfile(client=state.client,{force=false,ttlMs=300000}={}){
  const session=await getSharedSession(client);
  if(!session)return null;
  if(!force&&state.profile&&state.profileUserId===session.user.id&&(Date.now()-state.profileAt)<ttlMs)return state.profile;
  return sharedCall(`profile:${session.user.id}`,async()=>{
    const {data,error}=await client.from('profiles').select('user_id,display_name,role,community,volunteer_pid,active').eq('user_id',session.user.id).maybeSingle();
    if(error)throw error;
    setSharedProfile(data);
    return data;
  },1500);
}

export async function sharedCall(key,loader,ttlMs=0){
  const now=Date.now(),cached=state.cache.get(key);
  if(ttlMs>0&&cached&&cached.expires>now)return cached.value;
  if(state.inflight.has(key))return state.inflight.get(key);
  const p=Promise.resolve().then(loader).then(value=>{
    if(ttlMs>0)state.cache.set(key,{value,expires:Date.now()+ttlMs});
    return value;
  }).finally(()=>state.inflight.delete(key));
  state.inflight.set(key,p);
  return p;
}

export function invalidateShared(prefix=''){
  for(const key of [...state.cache.keys()])if(!prefix||key.startsWith(prefix))state.cache.delete(key);
}

export function isPortalViewActive(view){
  const panel=document.querySelector(`[data-portal-panel="${CSS.escape(view)}"]`);
  return Boolean(panel&&!panel.hidden&&document.documentElement.dataset.authView==='portal');
}

export function bindPortalActivation(view,handler,{runIfActive=true}={}){
  let busy=false,pending=false;
  const run=async()=>{
    if(!isPortalViewActive(view))return;
    if(busy){pending=true;return;}
    busy=true;
    try{await handler();}finally{
      busy=false;
      if(pending){pending=false;queueMicrotask(run);}
    }
  };
  const onView=e=>{if(e.detail?.view===view)run().catch(()=>{});};
  const onAuth=()=>run().catch(()=>{});
  document.addEventListener('phc:portal-view-changed',onView);
  document.addEventListener('phc:auth-ready',onAuth);
  if(runIfActive)queueMicrotask(()=>run().catch(()=>{}));
  return ()=>{
    document.removeEventListener('phc:portal-view-changed',onView);
    document.removeEventListener('phc:auth-ready',onAuth);
  };
}

export function sharedDiagnostics(){
  return {hasClient:Boolean(state.client),hasSession:Boolean(state.session),profileUserId:state.profileUserId,refreshInFlight:Boolean(state.refreshPromise),inflight:[...state.inflight.keys()],cacheKeys:[...state.cache.keys()]};
}
