
create or replace function public.save_health_ncd_screening(
  p_source_pcucode text,
  p_source_pid bigint,
  p_screened_on date,
  p_weight_kg numeric,
  p_height_cm numeric,
  p_waist_cm numeric,
  p_sbp integer,
  p_dbp integer,
  p_glucose_mg_dl integer,
  p_glucose_type text,
  p_danger_symptoms boolean,
  p_smoker boolean,
  p_alcohol_risk boolean,
  p_exercise_sufficient boolean,
  p_note text,
  p_request_id uuid
)
returns public.health_ncd_screenings
language plpgsql
security definer
set search_path=''
as $function$
declare
  v_person public.health_persons;
  v_row public.health_ncd_screenings;
  v_age integer;
  v_known boolean;
  v_bmi numeric(5,2);
  v_waist_risk boolean := false;
  v_bp text;
  v_glucose text;
  v_status text := 'เธเนเธญเธกเธนเธฅเธขเธฑเธเนเธกเนเธเธฃเธ / เธ•เนเธญเธเธเธฃเธฐเน€เธกเธดเธเน€เธเธดเนเธกเน€เธ•เธดเธก';
  v_severity text := 'incomplete';
  v_advice text := 'เธเธฅเธเธตเนเน€เธเนเธเธเธฒเธฃเธเธฑเธ”เธเธฃเธญเธเน€เธเธทเนเธญเธเธ•เนเธ เนเธกเนเนเธเนเธเธฒเธฃเธงเธดเธเธดเธเธเธฑเธขเนเธฃเธ';
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
  if v_person.gender not in ('เธเธฒเธข','เธซเธเธดเธ') or v_person.birth_date is null then
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
  v_waist_risk := (v_person.gender='เธเธฒเธข' and p_waist_cm>=90)
               or (v_person.gender='เธซเธเธดเธ' and p_waist_cm>=80);

  -- Thai HT guideline 2567 severity bands for clinic BP.
  v_bp := case
    when p_sbp>=180 or p_dbp>=110 then 'เธเธงเธฒเธกเธ”เธฑเธเธชเธนเธเธฃเธฐเธ”เธฑเธ 3/เธญเธฑเธเธ•เธฃเธฒเธข'
    when p_sbp>=160 or p_dbp>=100 then 'เธเธงเธฒเธกเธ”เธฑเธเธชเธนเธเธฃเธฐเธ”เธฑเธ 2'
    when p_sbp>=140 or p_dbp>=90 then 'เธเธงเธฒเธกเธ”เธฑเธเธชเธนเธเธฃเธฐเธ”เธฑเธ 1 เธเธงเธฃเธ•เธฃเธงเธเธขเธทเธเธขเธฑเธ'
    when p_sbp>=130 or p_dbp>=80 then 'BP at risk'
    when p_sbp<90 or p_dbp<60 then 'เธเธงเธฒเธกเธ”เธฑเธเธ•เนเธณ เธเธงเธฃเธเธฃเธฐเน€เธกเธดเธ'
    when p_sbp<120 and p_dbp<80 then 'Optimal'
    else 'Normal'
  end;

  -- DDC/MOPH screening flow: fasting 100-125 = IFG, >=126 suspect DM;
  -- random >=110 should repeat fasting, >=200 is high and needs clinical confirmation.
  v_glucose := case
    when p_glucose_mg_dl<70 then 'เธเนเธณเธ•เธฒเธฅเธ•เนเธณ เธ•เนเธญเธเธ•เธฃเธงเธเธเนเธณ/เธเธฃเธฐเน€เธกเธดเธเธญเธฒเธเธฒเธฃ'
    when p_glucose_type='fasting' and p_glucose_mg_dl>=126 then 'เธเนเธณเธ•เธฒเธฅเธญเธ”เธญเธฒเธซเธฒเธฃเธชเธนเธ เธชเธเธชเธฑเธขเน€เธเธฒเธซเธงเธฒเธ เธ•เนเธญเธเธ•เธฃเธงเธเธขเธทเธเธขเธฑเธ'
    when p_glucose_type='fasting' and p_glucose_mg_dl>=100 then 'เธเนเธณเธ•เธฒเธฅเธญเธ”เธญเธฒเธซเธฒเธฃ 100-125 เธเธฅเธธเนเธกเน€เธชเธตเนเธขเธ/IFG'
    when p_glucose_type='fasting' then 'เธญเธขเธนเนเนเธเธเนเธงเธเธเธฑเธ”เธเธฃเธญเธเธเธเธ•เธด'
    when p_glucose_type='random' and p_glucose_mg_dl>=200 then 'เธเนเธณเธ•เธฒเธฅเธชเธธเนเธกเธชเธนเธเธกเธฒเธ เธ•เนเธญเธเธ•เธฃเธงเธเธขเธทเธเธขเธฑเธ'
    when p_glucose_type='random' and p_glucose_mg_dl>=110 then 'เธเนเธณเธ•เธฒเธฅเธชเธธเนเธกเธ•เธฑเนเธเนเธ•เน 110 เธเธงเธฃเธ•เธฃเธงเธ FPG/FCBG เธเนเธณ'
    when p_glucose_type='random' then 'เธเนเธณเธ•เธฒเธฅเธชเธธเนเธกเธญเธขเธนเนเนเธเธเนเธงเธเธเธฑเธ”เธเธฃเธญเธเธเธเธ•เธด'
    else 'เนเธกเนเธ—เธฃเธฒเธเธชเธ–เธฒเธเธฐเธญเธ”เธญเธฒเธซเธฒเธฃ'
  end;

  if coalesce(p_danger_symptoms,false) then
    v_severity:='urgent';
    v_status:='เธกเธตเธญเธฒเธเธฒเธฃเธญเธฑเธเธ•เธฃเธฒเธข (เธชเธตเนเธ”เธ)';
    v_advice:='เธเธฃเธฐเธชเธฒเธเน€เธเนเธฒเธซเธเนเธฒเธ—เธตเนเธชเธฒเธเธฒเธฃเธ“เธชเธธเธเน€เธเธทเนเธญเธเธฃเธฐเน€เธกเธดเธเน€เธฃเนเธเธ”เนเธงเธ เธซเธฒเธเธกเธตเน€เธเนเธเธซเธเนเธฒเธญเธ เธซเธญเธ เธญเนเธญเธเนเธฃเธ เธเธนเธ”เนเธกเนเธเธฑเธ” เธเธถเธกเธซเธฃเธทเธญเธซเธกเธ”เธชเธ•เธด เนเธซเนเธ•เธดเธ”เธ•เนเธญเธซเธเนเธงเธขเธเธธเธเน€เธเธดเธเธ—เธฑเธเธ—เธต';
  elsif p_sbp>=180 or p_dbp>=110 then
    v_severity:='urgent';
    v_status:='เธเธงเธฒเธกเธ”เธฑเธเธชเธนเธเธฃเธฐเธ”เธฑเธ 3/เธญเธฑเธเธ•เธฃเธฒเธข (เธชเธตเนเธ”เธ)';
    v_advice:='เนเธซเนเธเธฑเธเนเธฅเธฐเธงเธฑเธ”เธเนเธณเธญเธขเนเธฒเธเธ–เธนเธเธงเธดเธเธต เธซเธฒเธเธขเธฑเธเธ•เธฑเนเธเนเธ•เน 180/110 เธกเธก.เธเธฃเธญเธ—เธเธถเนเธเนเธ เธซเธฃเธทเธญเธกเธตเธญเธฒเธเธฒเธฃเธเธดเธ”เธเธเธ•เธด เนเธซเนเธเธฃเธฐเธชเธฒเธเน€เธเนเธฒเธซเธเนเธฒเธ—เธตเนเน€เธเธทเนเธญเธเธฃเธฐเน€เธกเธดเธเน€เธฃเนเธเธ”เนเธงเธ';
  elsif p_glucose_mg_dl<70 then
    v_severity:='urgent';
    v_status:='เธเนเธณเธ•เธฒเธฅเธ•เนเธณ เธ•เนเธญเธเธเธฃเธฐเน€เธกเธดเธเน€เธฃเนเธเธ”เนเธงเธ (เธชเธตเนเธ”เธ)';
    v_advice:='เธ•เธฃเธงเธเธเนเธณเธ•เธฒเธฅเธเนเธณเนเธฅเธฐเธเธฃเธฐเน€เธกเธดเธเธญเธฒเธเธฒเธฃเธ—เธฑเธเธ—เธต เนเธ”เธขเน€เธเธเธฒเธฐเธเธนเนเนเธเนเธขเธฒเธฅเธ”เธเนเธณเธ•เธฒเธฅเธซเธฃเธทเธญเธญเธดเธเธเธนเธฅเธดเธ เธซเธฒเธเธกเธตเธญเธฒเธเธฒเธฃเธเธดเธ”เธเธเธ•เธดเนเธซเนเธเธฃเธฐเธชเธฒเธเน€เธเนเธฒเธซเธเนเธฒเธ—เธตเนเน€เธฃเนเธเธ”เนเธงเธ';
  elsif p_sbp>=140 or p_dbp>=90
     or (p_glucose_type='fasting' and p_glucose_mg_dl>=126)
     or (p_glucose_type='random' and p_glucose_mg_dl>=200) then
    v_severity:='alert';
    v_status:=case
      when v_known then 'เธเธนเนเธกเธตเนเธฃเธเน€เธ”เธดเธก เธเนเธฒเธ•เธฃเธงเธเธเธดเธ”เธเธเธ•เธด เธ•เนเธญเธเธ•เธดเธ”เธ•เธฒเธก (เธชเธตเนเธ”เธ)'
      else 'เธเธฅเธเธฑเธ”เธเธฃเธญเธเธเธดเธ”เธเธเธ•เธด เธ•เนเธญเธเธ•เธฃเธงเธเธขเธทเธเธขเธฑเธ (เธชเธตเนเธ”เธ)'
    end;
    v_advice:=case
      when p_sbp>=140 or p_dbp>=90 then
        'เธงเธฑเธ”เธเธงเธฒเธกเธ”เธฑเธเธเนเธณเธญเธขเนเธฒเธเธ–เธนเธเธงเธดเธเธตเนเธฅเธฐเธเธฃเธฐเธชเธฒเธเน€เธเนเธฒเธซเธเนเธฒเธ—เธตเนเน€เธเธทเนเธญเธ•เธฃเธงเธเธขเธทเธเธขเธฑเธ/เธเธฑเธ”เธ•เธดเธ”เธ•เธฒเธก เธเนเธฒเธเธฃเธฑเนเธเน€เธ”เธตเธขเธงเนเธกเนเนเธเนเธขเธทเธเธขเธฑเธเธเธฒเธฃเธงเธดเธเธดเธเธเธฑเธข'
      else
        'เธเธฃเธฐเธชเธฒเธเน€เธเนเธฒเธซเธเนเธฒเธ—เธตเนเน€เธเธทเนเธญเธ•เธฃเธงเธเธขเธทเธเธขเธฑเธเธฃเธฐเธ”เธฑเธเธเนเธณเธ•เธฒเธฅเธ•เธฒเธกเนเธเธงเธ—เธฒเธ เธเนเธฒเธเนเธณเธ•เธฒเธฅเธเธฃเธฑเนเธเน€เธ”เธตเธขเธงเนเธกเนเนเธเนเธขเธทเธเธขเธฑเธเธเธฒเธฃเธงเธดเธเธดเธเธเธฑเธขเนเธฃเธ'
    end;
  elsif v_known then
    v_severity:='risk';
    v_status:='เธเธนเนเธกเธตเนเธฃเธเน€เธ”เธดเธก เธ•เนเธญเธเธ•เธดเธ”เธ•เธฒเธก (เธชเธตเน€เธซเธฅเธทเธญเธ)';
    v_advice:='เธ•เธดเธ”เธ•เธฒเธกเธเธฑเธเธซเธเนเธงเธขเธเธฃเธดเธเธฒเธฃเธ•เธฒเธกเนเธเธเน€เธ”เธดเธก เนเธกเนเธชเธฃเธธเธเธงเนเธฒเธซเธฒเธขเธเธฒเธเนเธฃเธเธเธฒเธเธเนเธฒเธ•เธฃเธงเธเธเธฃเธฑเนเธเน€เธ”เธตเธขเธง';
  elsif p_sbp>=130 or p_dbp>=80 or p_sbp<90 or p_dbp<60
     or (p_glucose_type='fasting' and p_glucose_mg_dl>=100)
     or (p_glucose_type='random' and p_glucose_mg_dl>=110)
     or v_bmi<18.5 or v_bmi>=23 or v_waist_risk
     or coalesce(p_smoker,false) or coalesce(p_alcohol_risk,false)
     or not coalesce(p_exercise_sufficient,false) then
    v_severity:='risk';
    v_status:='เธเธงเธฃเธเธฃเธฐเน€เธกเธดเธเธเธงเธฒเธกเน€เธชเธตเนเธขเธเน€เธเธดเนเธกเน€เธ•เธดเธก (เธชเธตเน€เธซเธฅเธทเธญเธ)';
    v_advice:=case
      when p_glucose_type='random' and p_glucose_mg_dl>=110 then
        'เธเธงเธฃเธเธฑเธ”เธ•เธฃเธงเธ FPG/FCBG เธเนเธณเธ•เธฒเธกเนเธเธงเธ—เธฒเธ เนเธฅเธฐเธเธฃเธฐเน€เธกเธดเธเธเธฑเธเธเธฑเธขเน€เธชเธตเนเธขเธเธฃเนเธงเธก'
      when p_glucose_type='fasting' and p_glucose_mg_dl>=100 then
        'เธญเธขเธนเนเนเธเธเธฅเธธเนเธกเน€เธชเธตเนเธขเธ/IFG เธเธงเธฃเนเธซเนเธเธณเนเธเธฐเธเธณเธเธฃเธฑเธเธเธคเธ•เธดเธเธฃเธฃเธกเนเธฅเธฐเธ•เธดเธ”เธ•เธฒเธกเธ•เธฒเธกเนเธเธงเธ—เธฒเธ'
      when p_sbp>=130 or p_dbp>=80 then
        'BP at risk เธเธงเธฃเธงเธฑเธ”เธเนเธณเธญเธขเนเธฒเธเธ–เธนเธเธงเธดเธเธต เนเธซเนเธเธณเนเธเธฐเธเธณเธเธฃเธฑเธเธเธคเธ•เธดเธเธฃเธฃเธก เนเธฅเธฐเธ•เธดเธ”เธ•เธฒเธกเธ•เธฒเธกเธเธงเธฒเธกเน€เธชเธตเนเธขเธ'
      else
        'เธชเนเธเน€เธชเธฃเธดเธกเธเธฒเธฃเธเธฃเธฑเธเธเธคเธ•เธดเธเธฃเธฃเธกเนเธฅเธฐเนเธซเนเน€เธเนเธฒเธซเธเนเธฒเธ—เธตเนเธเธดเธเธฒเธฃเธ“เธฒเธเธฑเธเธเธฑเธขเน€เธชเธตเนเธขเธเธฃเนเธงเธก เธเธณเธซเธเธ”เนเธเธเธ•เธดเธ”เธ•เธฒเธกเน€เธเธเธฒเธฐเธเธธเธเธเธฅ'
    end;
  else
    v_severity:='normal';
    v_status:='เธเนเธฒเธ—เธตเนเธ•เธฃเธงเธเธญเธขเธนเนเนเธเธเนเธงเธเธเธฑเธ”เธเธฃเธญเธเธเธเธ•เธด (เธชเธตเน€เธเธตเธขเธง)';
    v_advice:='เธเธฅเธเธฑเธ”เธเธฃเธญเธเธเธฃเธฑเนเธเธเธตเนเนเธกเนเธขเธทเธเธขเธฑเธเธงเนเธฒเนเธกเนเธกเธตเนเธฃเธ เนเธซเนเธ•เธดเธ”เธ•เธฒเธกเธ•เธฒเธกเธฃเธญเธเนเธฅเธฐเธเธฃเธฐเน€เธกเธดเธเธเธฑเธเธเธฑเธขเน€เธชเธตเนเธขเธเธฃเนเธงเธก';
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
$function$;

do $patch$
declare ddl text;
begin
  select pg_get_functiondef(p.oid) into ddl
  from pg_proc p join pg_namespace n on n.oid=p.pronamespace
  where n.nspname='public' and p.proname='save_health_ncd_screening_v4'
  order by p.oid desc limit 1;
  if ddl is null then raise exception 'SAVE_V4_NOT_FOUND'; end if;
  ddl:=replace(ddl,'calculation_version=''osm-health-ncd-1.8.47''',
                    'calculation_version=''osm-health-ncd-2.0.122-guard''');
  execute ddl;
end
$patch$;

insert into public.app_settings(key,value)
values(
  'ncd_entry_guard_v2122',
  jsonb_build_object(
    'version','2.0.122',
    'hard_limits',jsonb_build_object(
      'weight_kg','10-400','height_cm','80-250','waist_cm','30-250',
      'sbp','70-260','dbp','40-180','glucose_mg_dl','20-700'
    ),
    'verify_extreme_entry',jsonb_build_object(
      'weight_kg','<20 or >250','height_cm','<100 or >220',
      'weight_change','>20% from previous','height_change','>5 cm from previous'
    ),
    'bp_guidance','Thai HT guideline 2567: at risk 130-139/80-89; grade1 140-159/90-99; grade2 160-179/100-109; grade3 >=180 or >=110',
    'glucose_guidance','DDC/MOPH screening: fasting 100-125 risk, >=126 confirm; random >=110 repeat fasting, >=200 confirm; <70 low',
    'source_of_truth','MOPH/DDC screening guidance + Thai HT guideline 2567'
  )
)
on conflict(key) do update set value=excluded.value,updated_at=now();

notify pgrst,'reload schema';
