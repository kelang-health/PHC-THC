'use strict';
window.AppointmentNoticePhase35={
  async mount(){
    const host=document.getElementById('an-osm-bridge-panel');
    if(!host)return;
    let data=null,community='',search='';
    const badge=(text,kind)=>'<span class="badge '+(kind||'')+'">'+esc(text)+'</span>';
    const pct=v=>Number(v||0).toFixed(1)+'%';
    const label=s=>({dual_ready:'พร้อม 2 OA',osm_bridge_ready:'พร้อมเชื่อมผ่าน OSM',primary_link_unusable:'OSM link ใช้ไม่ได้',fallback_registration:'ลงทะเบียนแบบเดิม'}[s]||s||'—');
    const render=async()=>{
      host.innerHTML='<div class="empty">กำลังตรวจ OSM Primary Bridge…</div>';
      try{
        const q=new URLSearchParams();
        if(community)q.set('community',community);
        if(search)q.set('search',search);
        data=await api('/appointment-notices/failover/osm-bridge?'+q.toString());
        const s=data.summary||{},p=data.primary_quota||{},h=data.hub_bridge||{},rows=data.rows||[],comms=data.communities||[],policy=data.policy||{};
        let html='';
        html+='<div class="panel-head"><div><h3>OSM Primary Bridge Onboarding</h3><p class="muted">ใช้ LINE OA ของ OSM ที่เชื่อมอยู่แล้วเป็นเส้นทางหลัก เพื่อเชื่อม OA สำรองโดยไม่กรอก CID/วันเกิดซ้ำ</p></div><div>'+(h.status==='ok'?badge('Hub Bridge พร้อม','good'):badge('Hub Bridge ไม่พร้อม','warn'))+'</div></div>';
        html+='<div class="notice-bridge-grid">';
        html+='<article><strong>'+num(s.primary_ready||0)+'</strong><span>เชื่อม OSM OA แล้ว</span><small>'+pct(s.primary_pct)+' ของ '+num(s.volunteers_total||0)+' คน</small></article>';
        html+='<article><strong>'+num(s.osm_bridge_ready||0)+'</strong><span>พร้อมเชื่อมผ่าน OSM</span><small>ไม่ต้องลงทะเบียนใหม่</small></article>';
        html+='<article><strong>'+num(s.dual_ready||0)+'</strong><span>พร้อม 2 OA</span><small>ใช้งาน Backup ได้แล้ว</small></article>';
        html+='<article><strong>'+num(s.fallback_registration||0)+'</strong><span>Fallback registration</span><small>ยังไม่เชื่อม OSM OA</small></article>';
        html+='<article><strong>'+num(p.remaining||0)+'</strong><span>โควตา OA หลักคงเหลือ</span><small>ใช้ '+num(p.used||0)+' / '+num(p.limit||0)+'</small></article>';
        html+='<article><strong>'+num(s.recently_invited||0)+'</strong><span>เชิญแล้วล่าสุด</span><small>กันส่งซ้ำ '+num(policy.resend_hours||12)+' ชม.</small></article></div>';
        html+='<div class="notice-bridge-policy"><strong>เส้นทางหลัก:</strong> OSM OA เดิม → one-time token 30 นาที → OA สำรอง → verified mapping <span>'+badge('ไม่ส่ง raw Backup LINE ID เข้า OSM','good')+'</span></div>';
        html+='<div class="notice-bridge-toolbar"><label>ชุมชน<select id="p35-community"><option value="">ทุกชุมชน</option>';
        comms.forEach(c=>{html+='<option value="'+esc(c)+'" '+(c===community?'selected':'')+'>'+esc(c)+'</option>';});
        html+='</select></label><label>ค้นหา<input type="search" id="p35-search" value="'+esc(search)+'" placeholder="ชื่อ อสม."></label><button type="button" class="secondary" id="p35-refresh">รีเฟรช</button><button type="button" class="secondary" id="p35-select">เลือกพร้อมเชื่อมสูงสุด '+num(policy.max_batch||50)+' คน</button></div>';
        html+='<div class="notice-bridge-actions"><button type="button" class="secondary" id="p35-dryrun">ตรวจสอบ Dry-run</button><button type="button" class="primary" id="p35-send">ส่งคำเชิญผ่าน OSM OA</button><span class="muted" id="p35-selected">เลือก 0 คน</span></div>';
        html+='<div class="table-wrap notice-bridge-table"><table><thead><tr><th>เลือก</th><th>อสม.</th><th>ชุมชน</th><th>หมู่</th><th>OSM OA</th><th>Backup</th><th>เส้นทาง</th><th>เชิญล่าสุด</th></tr></thead><tbody>';
        if(rows.length){
          rows.forEach(r=>{
            html+='<tr><td>'+(r.bridge_sendable&&!r.recently_invited?'<input type="checkbox" class="p35-pick" value="'+num(r.volunteer_id)+'">':'—')+'</td>';
            html+='<td><strong>'+esc(r.name||'—')+'</strong></td><td>'+esc(r.community||'—')+'</td><td>'+esc(r.moo||'—')+'</td>';
            html+='<td>'+(r.primary_ready?badge('พร้อม','good'):badge('ไม่พร้อม','warn'))+'</td>';
            html+='<td>'+(r.backup_ready?badge('พร้อม','good'):badge('ยัง',''))+'</td>';
            html+='<td>'+badge(label(r.status),r.status==='dual_ready'?'good':r.status==='osm_bridge_ready'?'warn':'')+'</td>';
            html+='<td>'+(r.last_invited_at?esc(r.last_invited_at):'—')+'</td></tr>';
          });
        }else html+='<tr><td colspan="8" class="empty">ไม่มีข้อมูล</td></tr>';
        html+='</tbody></table></div>';
        host.innerHTML=html;

        const updateSelected=()=>{document.getElementById('p35-selected').textContent='เลือก '+num(document.querySelectorAll('.p35-pick:checked').length)+' คน';};
        document.querySelectorAll('.p35-pick').forEach(x=>x.onchange=updateSelected);
        document.getElementById('p35-community').onchange=async e=>{community=e.target.value;await render();};
        document.getElementById('p35-search').onchange=async e=>{search=e.target.value.trim();await render();};
        document.getElementById('p35-refresh').onclick=render;
        document.getElementById('p35-select').onclick=()=>{let n=0;document.querySelectorAll('.p35-pick').forEach(cb=>{if(n<Number(policy.max_batch||50)){cb.checked=true;n++;}else cb.checked=false;});updateSelected();};
        const selected=()=>Array.from(document.querySelectorAll('.p35-pick:checked')).map(x=>Number(x.value));
        const run=async dry=>{
          const ids=selected();
          if(!ids.length){toast('กรุณาเลือก อสม. อย่างน้อย 1 คน');return;}
          if(!dry&&!confirm('ส่งคำเชิญจริงผ่าน OSM OA '+num(ids.length)+' คน\nโควตาคงเหลือ '+num(p.remaining||0)+'\nลิงก์มีอายุ 30 นาที\n\nยืนยันส่งหรือไม่?'))return;
          try{
            const r=await api('/appointment-notices/failover/osm-bridge/invite',{method:'POST',body:JSON.stringify({volunteer_ids:ids,dry_run:dry,allow_resend:false})});
            const lines=[dry?'OSM Bridge Dry-run':'ส่งคำเชิญ OSM Bridge','เลือก '+num(r.selected||0)+' คน','พร้อม '+num(r.ready||0),'บล็อก '+num(r.blocked||0),'ส่งจริง '+num(r.sent||0)];
            (r.results||[]).slice(0,20).forEach(x=>lines.push('• '+(x.name||('ID '+x.volunteer_id))+' · '+(x.community||'')+' · '+(x.status||'—')+(x.reason?' · '+x.reason:'')));
            alert(lines.join('\n'));
            if(!dry)await render();
          }catch(e){toast(e.message);}
        };
        document.getElementById('p35-dryrun').onclick=()=>run(true);
        document.getElementById('p35-send').onclick=()=>run(false);
      }catch(e){host.innerHTML='<div class="empty">'+esc(e.message)+'</div>';}
    };
    await render();
  }
};