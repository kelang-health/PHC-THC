'use strict';
window.AppointmentNoticePhase34={
  async mount(){
    const host=document.getElementById('an-acceleration-panel');
    if(!host)return;
    const badge=(text,kind)=>'<span class="badge '+(kind||'')+'">'+esc(text)+'</span>';
    const pct=v=>Number(v||0).toFixed(1)+'%';
    const stateLabel=s=>({closed:'Gate ปิด',pilot_ready:'Pilot Ready',operational_ready:'Operational Ready'}[s]||s||'—');
    const actLabel=s=>({target_reached:'ถึงเป้า',stalled:'ค้าง',not_started:'ยังไม่เริ่ม',active:'กำลังดำเนินการ',pending:'รอดำเนินการ'}[s]||s||'—');
    const priLabel=s=>({critical:'เร่งด่วนมาก',high:'สูง',medium:'กลาง',low:'ต่ำ'}[s]||s||'—');
    const dailyLabel=s=>({baseline:'รอ baseline',on_track:'ตามเป้า',behind:'ต่ำกว่าเป้า'}[s]||s||'—');
    const render=async()=>{
      host.innerHTML='<div class="empty">กำลังคำนวณ Coverage Acceleration…</div>';
      try{
        const d=await api('/appointment-notices/failover/acceleration');
        const s=d.summary||{},g=d.gate||{},c=d.config||{},rows=d.communities||[],alerts=d.alerts||[];
        let html='';
        html+='<div class="panel-head"><div><h3>Coverage Acceleration & Readiness Gate</h3><p class="muted">จัดลำดับชุมชน · เป้ารายวัน · ตรวจค้าง · ปิด Live Failover จนกว่าจะผ่านเกณฑ์</p></div><div>'+badge(stateLabel(g.state),g.state==='closed'?'warn':'good')+'</div></div>';
        html+='<div class="notice-accel-grid">';
        html+='<article class="'+(g.state==='closed'?'notice-risk-card':'')+'"><strong>'+pct(s.dual_pct)+'</strong><span>Coverage ปัจจุบัน</span><small>'+num(s.dual_ready||0)+' / '+num(s.volunteers_total||0)+' คน</small></article>';
        html+='<article><strong>'+num(s.gap_to_target||0)+'</strong><span>ขาดถึง Gate '+num(c.target_pct||90)+'%</span><small>เป้า '+num(s.target_count||0)+' คน</small></article>';
        html+='<article><strong>'+num(s.daily_target||0)+'</strong><span>เป้าต่อวัน</span><small>เพื่อถึง Gate ใน '+num(s.target_days||0)+' วัน</small></article>';
        html+='<article><strong>'+(s.today_gain===null||s.today_gain===undefined?'—':num(s.today_gain))+'</strong><span>เพิ่มวันนี้</span><small>'+dailyLabel(s.daily_status)+'</small></article>';
        html+='<article><strong>'+(s.eta_days===null||s.eta_days===undefined?'—':num(s.eta_days))+'</strong><span>ETA จากความเร็วจริง</span><small>วัน · เมื่อมี baseline เพียงพอ</small></article>';
        html+='<article><strong>'+num(s.not_started_communities||0)+'</strong><span>ชุมชนยังไม่เริ่ม</span><small>ค้าง '+num(s.stalled_communities||0)+' ชุมชน</small></article></div>';
        html+='<div class="notice-gate-box '+(g.state==='closed'?'closed':'ready')+'"><div><strong>Readiness Gate: '+esc(stateLabel(g.state))+'</strong><p>'+esc(g.reason||'')+'</p></div><div>';
        html+=(g.live_failover_allowed?badge('Live Failover อนุญาต','good'):badge('Live Failover ล็อกอยู่','warn'));
        html+='<small>Phase 3.4 ยังไม่มี Live Send endpoint</small></div></div>';
        if(alerts.length){
          html+='<div class="notice-alert-list">';
          alerts.forEach(a=>{html+='<div class="notice-alert '+esc(a.level||'')+'"><strong>'+esc(a.code||'')+'</strong><span>'+esc(a.message||'')+'</span></div>';});
          html+='</div>';
        }
        html+='<div class="notice-accel-settings">';
        html+='<label>Readiness Gate<input type="number" id="p34-target" min="70" max="99" value="'+num(c.target_pct||90)+'"><span>%</span></label>';
        html+='<label>Operational Goal<input type="number" id="p34-goal" min="80" max="100" value="'+num(c.operational_goal_pct||95)+'"><span>%</span></label>';
        html+='<label>Target days<input type="number" id="p34-days" min="3" max="60" value="'+num(c.target_days||14)+'"><span>วัน</span></label>';
        html+='<label>Stalled check<input type="number" id="p34-stalled" min="2" max="14" value="'+num(c.stalled_days||3)+'"><span>วัน</span></label>';
        html+='<button type="button" class="primary" id="p34-save">บันทึกแผน</button><button type="button" class="secondary" id="p34-refresh">คำนวณใหม่</button></div>';
        html+='<div class="table-wrap notice-accel-table"><table><thead><tr><th>ลำดับ</th><th>ชุมชน</th><th>ความสำคัญ</th><th>พร้อม</th><th>Coverage</th><th>Gap ถึง Gate</th><th>เป้าวันนี้</th><th>สถานะ</th><th></th></tr></thead><tbody>';
        if(rows.length){
          rows.forEach(r=>{
            html+='<tr class="'+(r.priority==='critical'?'notice-priority-critical':'')+'">';
            html+='<td>'+num(r.rank||0)+'</td><td><strong>'+esc(r.community||'—')+'</strong></td>';
            html+='<td>'+badge(priLabel(r.priority),(r.priority==='critical'||r.priority==='high')?'warn':'')+'</td>';
            html+='<td>'+num(r.dual_ready||0)+' / '+num(r.total||0)+'</td><td>'+pct(r.dual_pct)+'</td><td>'+num(r.gap_to_target||0)+'</td>';
            html+='<td><strong>'+num(r.daily_target||0)+'</strong></td>';
            html+='<td>'+badge(actLabel(r.activity),r.activity==='target_reached'?'good':(r.activity==='stalled'||r.activity==='not_started'?'warn':''))+'</td>';
            html+='<td><button type="button" class="secondary p34-focus" data-community="'+esc(r.community||'')+'">โฟกัส</button></td></tr>';
          });
        }else html+='<tr><td colspan="9" class="empty">ไม่มีข้อมูล</td></tr>';
        html+='</tbody></table></div>';
        host.innerHTML=html;
        document.getElementById('p34-refresh').onclick=render;
        document.getElementById('p34-save').onclick=async()=>{
          const body={
            target_pct:Number(document.getElementById('p34-target').value||90),
            operational_goal_pct:Number(document.getElementById('p34-goal').value||95),
            target_days:Number(document.getElementById('p34-days').value||14),
            stalled_days:Number(document.getElementById('p34-stalled').value||3)
          };
          try{
            await api('/appointment-notices/failover/acceleration/settings',{method:'POST',body:JSON.stringify(body)});
            toast('บันทึก Readiness Gate แล้ว');
            await render();
          }catch(e){toast(e.message);}
        };
        document.querySelectorAll('.p34-focus').forEach(btn=>{
          btn.onclick=()=>{
            const sel=document.getElementById('p33-community');
            if(!sel){toast('ไม่พบตัวกรอง Operational Rollout');return;}
            sel.value=btn.dataset.community||'';
            sel.dispatchEvent(new Event('change'));
            sel.scrollIntoView({behavior:'smooth',block:'center'});
          };
        });
      }catch(e){host.innerHTML='<div class="empty">'+esc(e.message)+'</div>';}
    };
    await render();
  }
};