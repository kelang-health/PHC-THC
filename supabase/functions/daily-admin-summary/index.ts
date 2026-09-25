import { createClient } from 'npm:@supabase/supabase-js@2';

const json=(body:unknown,status=200)=>new Response(JSON.stringify(body),{status,headers:{'content-type':'application/json; charset=utf-8'}});
const n=(v:unknown)=>Number(v||0);
const fmtTs=(v:unknown)=>{if(!v)return 'ไม่พบ';try{return new Intl.DateTimeFormat('th-TH',{timeZone:'Asia/Bangkok',day:'2-digit',month:'2-digit',year:'numeric',hour:'2-digit',minute:'2-digit',hour12:false}).format(new Date(String(v)));}catch{return 'ไม่พบ';}};

Deno.serve(async(req)=>{
  if(req.method!=='POST') return json({error:'METHOD_NOT_ALLOWED'},405);
  const now=new Date();
  const parts=new Intl.DateTimeFormat('en-CA',{timeZone:'Asia/Bangkok',year:'numeric',month:'2-digit',day:'2-digit',hour:'2-digit',minute:'2-digit',hour12:false}).formatToParts(now);
  const get=(type:string)=>parts.find(x=>x.type===type)?.value||'';
  const hour=Number(get('hour')||0), minute=Number(get('minute')||0);
  const dateKey=get('year')+'-'+get('month')+'-'+get('day');
  if(hour!==18 || minute>20) return json({ok:true,skipped:'outside_delivery_window'},200);

  const url=Deno.env.get('SUPABASE_URL')||'';
  const serviceKey=Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')||'';
  const botToken=Deno.env.get('TELEGRAM_BOT_TOKEN')||'';
  const chatIds=(Deno.env.get('TELEGRAM_ADMIN_CHAT_IDS')||'').split(',').map(x=>x.trim()).filter(Boolean);
  const appBase=(Deno.env.get('APP_BASE_URL')||'').replace(/\/$/,'');
  if(!url||!serviceKey||!botToken||!chatIds.length) return json({error:'SERVER_CONFIG_MISSING'},503);

  const supabase=createClient(url,serviceKey,{auth:{persistSession:false,autoRefreshToken:false}});
  const [{data:summary,error:summaryError},{data:communityUsage,error:communityError}]=await Promise.all([
    supabase.rpc('admin_daily_system_summary_v2066'),
    supabase.rpc('daily_community_usage_v2134')
  ]);
  if(summaryError) return json({error:'SUMMARY_FAILED',detail:String(summaryError.message||summaryError)},500);
  const s:any=summary||{};
  const communityRows:any[]=communityError?[]:((communityUsage as any)?.rows||[]);
  const {data:state,error:stateError}=await supabase.from('daily_system_summary').select('telegram_sent_at').eq('summary_date',dateKey).maybeSingle();
  if(stateError) return json({error:'DELIVERY_STATE_FAILED'},500);
  if(state?.telegram_sent_at) return json({ok:true,skipped:'already_sent'},200);

  const d:any=s.details||{};
  const sec:any=d.security||{};
  const ops:any=d.operations||{};
  const dq:any=d.data_quality||{};
  const sy:any=d.sync||{};
  const total=n(s.active_accounts), connected=n(s.line_connected);
  const connectedPct=total?Math.round(connected*1000/total)/10:0;
  const workPct=n(ops.target)?Math.round(n(ops.complete)*1000/n(ops.target))/10:0;
  const dateText=new Intl.DateTimeFormat('th-TH',{timeZone:'Asia/Bangkok',day:'numeric',month:'short',year:'numeric'}).format(now);
  const timeText=new Intl.DateTimeFormat('th-TH',{timeZone:'Asia/Bangkok',hour:'2-digit',minute:'2-digit',hour12:false}).format(now);
  const overall=(n(sec.critical_today)>0||n(dq.out_of_scope_active)>0||n(dq.duplicate_active_volunteer_pid)>0)?'🔴 ต้องตรวจสอบ':(n(sec.alerts_today)>0||n(dq.orphan_house_assignment)>0||Boolean(sy.stale_36h))?'🟠 มีจุดติดตาม':'🟢 ปกติ';

  const lines=[
    '📊 OSM-PHC Security & Operations — '+dateText,
    'สถานะรวม: '+overall,
    '',
    '👥 บัญชี Active: '+total+' · user '+n(s.active_users)+' · staff '+n(s.active_staff),
    '🔐 เข้าใช้งานวันนี้: '+n(s.signed_in_today)+' คน',
    '💚 LINE: '+connected+'/'+total+' ('+connectedPct+'%) · ใหม่วันนี้ '+n(s.line_connected_today),
    '🟢 Login ผ่าน LINE: '+n(s.line_login_users_today)+' คน / '+n(s.line_login_events_today)+' ครั้ง',
    '',
    '🏘 การใช้งานรายชุมชนวันนี้ (USER+STAFF)',
    ...communityRows.map((r:any)=>'• ม.'+(r.moo||'-')+' '+(r.community||'ไม่ระบุ')+': เข้า '+n(r.signed_in_today)+'/'+n(r.active_accounts)+' · LINE '+n(r.line_connected)),
    communityError?'• ⚠️ สรุปรายชุมชนโหลดไม่สำเร็จ แต่รายงานหลักยังส่งได้':'',
    '',
    '🛡 Security',
    '• บัญชีถูกล็อกขณะนี้: '+n(sec.locked_now),
    '• Login failed state คงค้าง: '+n(sec.failed_login_states),
    '• Security alerts วันนี้: '+n(sec.alerts_today)+' · Critical '+n(sec.critical_today),
    '',
    '🧰 งานภาคสนาม',
    '• เสร็จ '+n(ops.complete)+'/'+n(ops.target)+' ('+workPct+'%) · คงเหลือ '+n(ops.due)+' · บางส่วน '+n(ops.partial),
    '• งานติดตามเปิด '+n(ops.followup_open)+' · แดง '+n(ops.followup_red)+' · ส้ม '+n(ops.followup_orange),
    '',
    '🧭 Data Quality',
    '• ประชากร Active '+n(dq.health_active)+' · นอกนิยาม '+n(dq.out_of_scope_active),
    '• อสม. Active '+n(dq.active_volunteers)+' · PID ซ้ำ '+n(dq.duplicate_active_volunteer_pid),
    '• บ้านปัจจุบัน '+n(dq.houses_current)+' · verified '+n(dq.houses_verified)+' · review '+n(dq.houses_review_required)+' · pending '+n(dq.houses_pending_jhcis_create),
    '• บ้านผูก อสม.ไม่ Active: '+n(dq.orphan_house_assignment),
    '',
    '☁️ Sync',
    '• Health: '+fmtTs(sy.health_synced_at),
    '• Volunteer/House: '+fmtTs(sy.volunteer_synced_at)+(sy.stale_36h?' · ⚠️ เกิน 36 ชม.':''),
    'สรุปเวลา '+timeText+' น.',
    appBase?appBase:''
  ].filter(Boolean);
  const text=lines.join('\n').slice(0,3900);

  let sent=0;
  try{
    for(const chatId of chatIds){
      const r=await fetch('https://api.telegram.org/bot'+botToken+'/sendMessage',{method:'POST',headers:{'content-type':'application/json'},body:JSON.stringify({chat_id:chatId,text,disable_web_page_preview:true})});
      if(!r.ok) throw new Error('TELEGRAM_'+r.status);
      sent++;
    }
  }catch(e){
    await supabase.from('daily_system_summary').update({telegram_send_status:'failed'}).eq('summary_date',dateKey);
    return json({error:'TELEGRAM_SEND_FAILED'},502);
  }

  await supabase.from('daily_system_summary').update({telegram_sent_at:new Date().toISOString(),telegram_send_status:'sent'}).eq('summary_date',dateKey);
  return json({ok:true,chats:sent,summary_date:dateKey,overall,community_rows:communityRows.length,community_error:communityError?String(communityError.message||communityError):null});
});