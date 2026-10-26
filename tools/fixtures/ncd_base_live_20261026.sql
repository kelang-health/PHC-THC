CREATE OR REPLACE FUNCTION public.save_health_ncd_screening(p_source_pcucode text, p_source_pid bigint, p_screened_on date, p_weight_kg numeric, p_height_cm numeric, p_waist_cm numeric, p_sbp integer, p_dbp integer, p_glucose_mg_dl integer, p_glucose_type text, p_danger_symptoms boolean, p_smoker boolean, p_alcohol_risk boolean, p_exercise_sufficient boolean, p_note text, p_request_id uuid)
 RETURNS health_ncd_screenings
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_person public.health_persons;
  v_row public.health_ncd_screenings;
  v_age integer;
  v_known boolean;
  v_bmi numeric(5,2);
  v_waist_risk boolean := false;
  v_bp text;
  v_glucose text;
  v_status text := 'ข้อมูลยังไม่ครบ / ต้องประเมินเพิ่มเติม';
  v_severity text := 'incomplete';
  v_advice text := 'ผลนี้เป็นการคัดกรองเบื้องต้น ไม่ใช่การวินิจฉัยโรค';
  v_day date := coalesce(p_screened_on,current_date);
begin
  if auth.uid() is null or private.current_role() is null then raise exception 'Not authorized'; end if;
  if p_request_id is null or p_source_pid is null or p_source_pid<=0 or coalesce(btrim(p_source_pcucode),'')='' then
    raise exception 'Person and request ID are required';
  end if;

  select * into v_person
  from public.health_persons
  where source_pcucode=btrim(p_source_pcucode) and source_pid=p_source_pid and active=true;
  if not found then raise exception 'Target person not found'; end if;
  if not private.health_can_access_house(v_person.house_pcucode,v_person.hcode) then
    raise exception 'Not authorized for this person';
  end if;
  if v_person.gender not in ('ชาย','หญิง') or v_person.birth_date is null then
    raise exception 'Please verify gender/birth date in JHCIS';
  end if;

  v_age := extract(year from age(v_day,v_person.birth_date))::integer;
  if v_age<18 or v_age>120 then raise exception 'Adult screening only (18-120 years)'; end if;
  if v_day > current_date + 1 then raise exception 'screened_on cannot be in the future'; end if;

  -- Hard plausibility limits. Clinically extreme but possible values inside these ranges
  -- are preserved and handled by the UI confirmation + follow-up severity below.
  if p_weight_kg is null or p_weight_kg not between 10 and 400 then raise exception 'invalid weight'; end if;
  if p_height_cm is null or p_height_cm not between 80 and 250 then raise exception 'invalid height'; end if;
  if p_waist_cm is null or p_waist_cm not between 30 and 250 then raise exception 'invalid waist'; end if;
  if p_sbp is null or p_sbp not between 70 and 260 then raise exception 'invalid systolic BP'; end if;
  if p_dbp is null or p_dbp not between 40 and 180 then raise exception 'invalid diastolic BP'; end if;
  if p_sbp<=p_dbp then raise exception 'systolic BP must exceed diastolic BP'; end if;
  if p_glucose_mg_dl is null or p_glucose_mg_dl not between 20 and 700 then raise exception 'invalid glucose'; end if;
  if coalesce(p_glucose_type,'') not in ('fasting','random','unknown') then raise exception 'invalid glucose type'; end if;

  select * into v_row
  from public.health_ncd_screenings
  where recorded_by=auth.uid() and request_id=p_request_id;
  if found then return v_row; end if;

  v_known := coalesce(v_person.has_ht,false) or coalesce(v_person.has_dm,false);
  v_bmi := round(p_weight_kg/power(p_height_cm/100,2),2);
  v_waist_risk := (v_person.gender='ชาย' and p_waist_cm>=90)
               or (v_person.gender='หญิง' and p_waist_cm>=80);

  -- Thai HT guideline 2567 severity bands for clinic BP.
  v_bp := case
    when p_sbp>=180 or p_dbp>=110 then 'ความดันสูงระดับ 3/อันตราย'
    when p_sbp>=160 or p_dbp>=100 then 'ความดันสูงระดับ 2'
    when p_sbp>=140 or p_dbp>=90 then 'ความดันสูงระดับ 1 ควรตรวจยืนยัน'
    when p_sbp>=130 or p_dbp>=80 then 'BP at risk'
    when p_sbp<90 or p_dbp<60 then 'ความดันต่ำ ควรประเมิน'
    when p_sbp<120 and p_dbp<80 then 'Optimal'
    else 'Normal'
  end;

  -- DDC/MOPH screening flow: fasting 100-125 = IFG, >=126 suspect DM;
  -- random >=110 should repeat fasting, >=200 is high and needs clinical confirmation.
  v_glucose := case
    when p_glucose_mg_dl<70 then 'น้ำตาลต่ำ ต้องตรวจซ้ำ/ประเมินอาการ'
    when p_glucose_type='fasting' and p_glucose_mg_dl>=126 then 'น้ำตาลอดอาหารสูง สงสัยเบาหวาน ต้องตรวจยืนยัน'
    when p_glucose_type='fasting' and p_glucose_mg_dl>=100 then 'น้ำตาลอดอาหาร 100-125 กลุ่มเสี่ยง/IFG'
    when p_glucose_type='fasting' then 'อยู่ในช่วงคัดกรองปกติ'
    when p_glucose_type='random' and p_glucose_mg_dl>=200 then 'น้ำตาลสุ่มสูงมาก ต้องตรวจยืนยัน'
    when p_glucose_type='random' and p_glucose_mg_dl>=110 then 'น้ำตาลสุ่มตั้งแต่ 110 ควรตรวจ FPG/FCBG ซ้ำ'
    when p_glucose_type='random' then 'น้ำตาลสุ่มอยู่ในช่วงคัดกรองปกติ'
    else 'ไม่ทราบสถานะอดอาหาร'
  end;

  if coalesce(p_danger_symptoms,false) then
    v_severity:='urgent';
    v_status:='มีอาการอันตราย (สีแดง)';
    v_advice:='ประสานเจ้าหน้าที่สาธารณสุขเพื่อประเมินเร่งด่วน หากมีเจ็บหน้าอก หอบ อ่อนแรง พูดไม่ชัด ซึมหรือหมดสติ ให้ติดต่อหน่วยฉุกเฉินทันที';
  elsif p_sbp>=180 or p_dbp>=110 then
    v_severity:='urgent';
    v_status:='ความดันสูงระดับ 3/อันตราย (สีแดง)';
    v_advice:='ให้พักและวัดซ้ำอย่างถูกวิธี หากยังตั้งแต่ 180/110 มม.ปรอทขึ้นไป หรือมีอาการผิดปกติ ให้ประสานเจ้าหน้าที่เพื่อประเมินเร่งด่วน';
  elsif p_glucose_mg_dl<70 then
    v_severity:='urgent';
    v_status:='น้ำตาลต่ำ ต้องประเมินเร่งด่วน (สีแดง)';
    v_advice:='ตรวจน้ำตาลซ้ำและประเมินอาการทันที โดยเฉพาะผู้ใช้ยาลดน้ำตาลหรืออินซูลิน หากมีอาการผิดปกติให้ประสานเจ้าหน้าที่เร่งด่วน';
  elsif p_sbp>=140 or p_dbp>=90
     or (p_glucose_type='fasting' and p_glucose_mg_dl>=126)
     or (p_glucose_type='random' and p_glucose_mg_dl>=200) then
    v_severity:='alert';
    v_status:=case
      when v_known then 'ผู้มีโรคเดิม ค่าตรวจผิดปกติ ต้องติดตาม (สีแดง)'
      else 'ผลคัดกรองผิดปกติ ต้องตรวจยืนยัน (สีแดง)'
    end;
    v_advice:=case
      when p_sbp>=140 or p_dbp>=90 then
        'วัดความดันซ้ำอย่างถูกวิธีและประสานเจ้าหน้าที่เพื่อตรวจยืนยัน/นัดติดตาม ค่าครั้งเดียวไม่ใช้ยืนยันการวินิจฉัย'
      else
        'ประสานเจ้าหน้าที่เพื่อตรวจยืนยันระดับน้ำตาลตามแนวทาง ค่าน้ำตาลครั้งเดียวไม่ใช้ยืนยันการวินิจฉัยโรค'
    end;
  elsif v_known then
    v_severity:='risk';
    v_status:='ผู้มีโรคเดิม ต้องติดตาม (สีเหลือง)';
    v_advice:='ติดตามกับหน่วยบริการตามแผนเดิม ไม่สรุปว่าหายจากโรคจากค่าตรวจครั้งเดียว';
  elsif p_sbp>=130 or p_dbp>=80 or p_sbp<90 or p_dbp<60
     or (p_glucose_type='fasting' and p_glucose_mg_dl>=100)
     or (p_glucose_type='random' and p_glucose_mg_dl>=110)
     or v_bmi<18.5 or v_bmi>=23 or v_waist_risk
     or coalesce(p_smoker,false) or coalesce(p_alcohol_risk,false)
     or not coalesce(p_exercise_sufficient,false) then
    v_severity:='risk';
    v_status:='ควรประเมินความเสี่ยงเพิ่มเติม (สีเหลือง)';
    v_advice:=case
      when p_glucose_type='random' and p_glucose_mg_dl>=110 then
        'ควรนัดตรวจ FPG/FCBG ซ้ำตามแนวทาง และประเมินปัจจัยเสี่ยงร่วม'
      when p_glucose_type='fasting' and p_glucose_mg_dl>=100 then
        'อยู่ในกลุ่มเสี่ยง/IFG ควรให้คำแนะนำปรับพฤติกรรมและติดตามตามแนวทาง'
      when p_sbp>=130 or p_dbp>=80 then
        'BP at risk ควรวัดซ้ำอย่างถูกวิธี ให้คำแนะนำปรับพฤติกรรม และติดตามตามความเสี่ยง'
      else
        'ส่งเสริมการปรับพฤติกรรมและให้เจ้าหน้าที่พิจารณาปัจจัยเสี่ยงร่วม กำหนดแผนติดตามเฉพาะบุคคล'
    end;
  else
    v_severity:='normal';
    v_status:='ค่าที่ตรวจอยู่ในช่วงคัดกรองปกติ (สีเขียว)';
    v_advice:='ผลคัดกรองครั้งนี้ไม่ยืนยันว่าไม่มีโรค ให้ติดตามตามรอบและประเมินปัจจัยเสี่ยงร่วม';
  end if;

  insert into public.health_ncd_screenings(
    source_pcucode,source_pid,house_pcucode,hcode,screened_on,
    weight_kg,height_cm,waist_cm,sbp,dbp,glucose_mg_dl,glucose_type,
    danger_symptoms,smoker,alcohol_risk,exercise_sufficient,known_ncd,
    bmi,waist_risk,bp_status,glucose_status,ncd_status,severity,advice,note,
    calculation_version,request_id,recorded_by
  ) values (
    v_person.source_pcucode,v_person.source_pid,v_person.house_pcucode,v_person.hcode,v_day,
    p_weight_kg,p_height_cm,p_waist_cm,p_sbp,p_dbp,p_glucose_mg_dl,p_glucose_type,
    coalesce(p_danger_symptoms,false),coalesce(p_smoker,false),coalesce(p_alcohol_risk,false),
    coalesce(p_exercise_sufficient,false),v_known,
    v_bmi,v_waist_risk,v_bp,v_glucose,v_status,v_severity,v_advice,left(coalesce(p_note,''),1000),
    'osm-health-ncd-2.0.122-guard',p_request_id,auth.uid()
  ) returning * into v_row;

  insert into public.health_audit_log(
    operator_id,action,entity,entity_id,source_pcucode,source_pid,hcode,severity,details
  )
  values(
    auth.uid(),'CREATE','health_ncd_screening',v_row.id::text,v_row.source_pcucode,
    v_row.source_pid,v_row.hcode,v_row.severity,
    jsonb_build_object(
      'screened_on',v_row.screened_on,
      'calculation_version',v_row.calculation_version,
      'bp_status',v_row.bp_status,
      'glucose_status',v_row.glucose_status,
      'guard_policy','ncd-entry-guard-v2122'
    )
  );
  return v_row;
end;
$function$
