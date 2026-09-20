import {getSharedSupabase,getSharedProfile} from './shared-runtime-v2035.mjs?v=2.0.35';
const ROOT='https://tgeezbwbrovfyjbeykrj.supabase.co';
const KEY='sb_publishable_'+'bw0sKPthqc6S'+'l9xU8fdVpA_p2sZ4-N2';
const $=s=>document.querySelector(s);
let client=null,ready=false;
const text=x=>{$('#admin-training-status').textContent=x;};
async function status(){
 const {data,error}=await client.rpc('admin_training_status_v2065');
 if(error)throw Error(error.message);
 text(data.exists?'ชุดฝึกอบรมพร้อมใช้งาน\nบ้าน '+data.houses+' หลัง · บุคคล '+data.people+
  ' คน · บ้านรอตรวจ '+data.pending_houses+' หลัง · สมาชิกค้าง '+data.pending_people+
  ' คน\nบัญชีฝึกอบรมที่เปิดใช้ '+data.accounts+' บัญชี':
  'ชุดฝึกอบรมถูกลบแล้ว · สามารถสร้างใหม่โดยกดรีเซ็ต');
}
async function manage(action){
 if(!ready)return;
 if(window.prompt('พิมพ์ DEMO เพื่อยืนยัน'+(action==='reset'?'รีเซ็ต':'ลบ')+
 'เฉพาะพื้นที่ฝึกอบรม (การรีเซ็ตจะยุติเซสชันผู้ทดลองที่กำลังใช้งาน)')!=='DEMO')return;
 const controls=$('#admin-training-controls');controls.hidden=true;
 text('กำลัง'+(action==='reset'?'รีเซ็ต':'ลบ')+'ข้อมูลฝึกอบรม…');
 try{
   const {data,error}=await client.rpc('admin_training_manage_v2065',{p_action:action});
   if(error||!data?.ok)throw Error(error?.message||'ดำเนินการไม่สำเร็จ');
   await status();
 }catch(e){text('ผิดพลาด: '+e.message);}
 finally{controls.hidden=false;}
}
(async()=>{
 try{
   client=await getSharedSupabase(ROOT,KEY);
   const p=await getSharedProfile(client,{force:true});
   if(p?.role!=='admin'||p?.active!==true){
     text('ต้องเข้าสู่ระบบ Cloud หลักด้วยบัญชี Admin ก่อน แล้วเปิดหน้านี้อีกครั้ง');return;
   }
   ready=true;$('#admin-training-controls').hidden=false;await status();
   $('#admin-training-reload').onclick=()=>status().catch(e=>text(e.message));
   $('#admin-training-reset').onclick=()=>manage('reset');
   $('#admin-training-delete').onclick=()=>manage('delete');
 }catch(e){text('ไม่สามารถตรวจสิทธิ์ Admin: '+e.message+' · เปิด Cloud หลักเพื่อเข้าสู่ระบบก่อน');}
})();
