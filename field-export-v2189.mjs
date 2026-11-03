const IDENTITY='source_pcucode,source_pid,display_name,hcode,house_no,moo,community,volunteer_pid';
export const EXPORT_DATASETS={
 work:{label:'รายการงานปัจจุบัน (ไม่กรองวันที่)',sheet:'04_Work_Items',table:'field_work_items_v200',columns:IDENTITY+',age_years,task_type,task_label,status,progress_percent,priority,last_activity_at,completed_at,period_start,period_mode',order:['source_pcucode','source_pid','task_type']},
 ncd:{label:'ผลคัดกรอง NCD',sheet:'05_NCD',table:'field_export_ncd_v200',date:'screened_on',order:['screened_on','id'],columns:IDENTITY+',screened_on,recorded_at,weight_kg,height_cm,waist_cm,bmi,sbp,dbp,glucose_mg_dl,glucose_type,ncd_status,severity,bp_status,glucose_status,mental_2q_status,mental_2q_result,cvd_risk_percent,cvd_risk_level,pulse',details:'id,record_mode,calculation_version'},
 growth:{label:'น้ำหนักและส่วนสูง',sheet:'06_Growth',table:'field_export_growth_v200',date:'screened_at',timestamp:true,order:['screened_at','id'],columns:IDENTITY+',screened_at,age_months,weight_kg,height_cm,interpretation_code,interpretation_label,reference_version',details:'id,nutrition_result'},
 child:{label:'พัฒนาการเด็ก',sheet:'07_Child_Dev',table:'field_export_child_dev_v200',date:'screened_at',timestamp:true,order:['screened_at','id'],columns:IDENTITY+',screened_at,actual_age_months,reference_target_months,overall_status',details:'id,domains,note'},
 elderly:{label:'ผู้สูงอายุ 9 ด้าน',sheet:'08_Elderly9',table:'field_export_elderly9_v200',date:'screening_date',order:['screening_date','session_id'],columns:IDENTITY+',screening_date,ncd_status,elderly9_status,completed_domains,observations,last_assessed_at',details:'session_id,domains'},
 followup:{label:'งานติดตาม',sheet:'09_Followup',table:'field_export_followup_v200',date:'created_at',timestamp:true,order:['created_at','id'],columns:IDENTITY+',created_at,updated_at,completed_at,followup_type,domain_code,priority,status,summary,resolution_note',details:'id'}
};
export function validExportRange(start,end){
 const valid=s=>/^\d{4}-\d{2}-\d{2}$/.test(s)&&Number.isFinite(Date.parse(s+'T00:00:00Z'))&&new Date(s+'T00:00:00Z').toISOString().slice(0,10)===s;
 return valid(start)&&valid(end)&&start<=end;
}
export function nextExportDay(day){return new Date(Date.parse(day+'T00:00:00Z')+86400000).toISOString().slice(0,10);}
export function buildExportQuery(client,key,options,scope,offset=0){
 const d=EXPORT_DATASETS[key];if(!d)throw new Error('EXPORT_TYPE_INVALID');
 if(!validExportRange(options.start,options.end))throw new Error('ช่วงวันที่ไม่ถูกต้อง');
 let q=client.from(d.table).select(d.columns+(options.details&&d.details?','+d.details:''));
 if(scope.mode==='self'&&scope.role!=='admin'){
  if(scope.volunteerPid==null)throw new Error('ยังไม่ระบุ อสม. ในขอบเขตนี้');
  q=q.eq('volunteer_pid',scope.volunteerPid);
 }else if(scope.mode==='volunteer'){
  if(scope.ownerPid==null)throw new Error('กรุณาเลือก อสม.');
  q=q.eq('volunteer_pid',scope.ownerPid);
 }else if(scope.mode==='community'){
  if(!scope.community)throw new Error('ยังไม่ระบุชุมชน');
  q=q.eq('community',scope.community);
 }else if(!(scope.mode==='all'&&scope.role==='admin'))throw new Error('ขอบเขตส่งออกไม่ถูกต้อง');
 if(d.date){
  const suffix=d.timestamp?'T00:00:00+07:00':'';
  q=q.gte(d.date,options.start+suffix).lt(d.date,nextExportDay(options.end)+suffix);
 }
 for(const col of d.order)q=q.order(col);
 return q.range(offset,offset+499);
}
export async function fetchExportDatasets(client,options,scope,isCurrent=()=>true){
 const keys=[...new Set(options.keys)];if(!keys.length||keys.some(k=>!EXPORT_DATASETS[k]))throw new Error('กรุณาเลือกประเภทข้อมูล');
 const sheets=[];
 for(const key of keys){
  const rows=[];
  for(let offset=0;;offset+=500){
   if(!isCurrent())throw new Error('บัญชีหรือขอบเขตเปลี่ยนแล้ว กรุณาส่งออกใหม่');
   const {data,error}=await buildExportQuery(client,key,options,scope,offset);
   if(error)throw error;
   if(!isCurrent())throw new Error('บัญชีหรือขอบเขตเปลี่ยนแล้ว กรุณาส่งออกใหม่');
   rows.push(...(data||[]));if((data||[]).length<500)break;
  }
  sheets.push([EXPORT_DATASETS[key].sheet,rows]);
 }
 return sheets;
}
