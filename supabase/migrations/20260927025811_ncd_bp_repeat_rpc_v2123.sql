create or replace function public.save_health_ncd_screening_v5(
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
  p_smoking_frequency text,
  p_alcohol_frequency text,
  p_exercise_frequency text,
  p_note text,
  p_request_id uuid,
  p_mental_2q_q1 boolean default null,
  p_mental_2q_q2 boolean default null,
  p_sbp_repeat integer default null,
  p_dbp_repeat integer default null
)
returns public.health_ncd_screenings
language plpgsql
security definer
set search_path=''
as $function$
declare
  v_row public.health_ncd_screenings;
  v_repeat_required boolean;
  v_repeat_present boolean;
  v_sbp_effective integer;
  v_dbp_effective integer;
  v_any_grade3 boolean;
  v_measure_note text;
begin
  if auth.uid() is null or private.current_role() is null then
    raise exception 'Not authorized';
  end if;

  select * into v_row
  from public.health_ncd_screenings
  where recorded_by=auth.uid() and request_id=p_request_id;
  if found then return v_row; end if;

  if p_sbp is null or p_sbp not between 70 and 260 then raise exception 'invalid systolic BP'; end if;
  if p_dbp is null or p_dbp not between 40 and 180 then raise exception 'invalid diastolic BP'; end if;
  if p_sbp<=p_dbp then raise exception 'systolic BP must exceed diastolic BP'; end if;

  v_repeat_required := p_sbp>=140 or p_dbp>=90;
  v_repeat_present := p_sbp_repeat is not null or p_dbp_repeat is not null;

  if v_repeat_present and (p_sbp_repeat is null or p_dbp_repeat is null) then
    raise exception 'BP_REPEAT_PAIR_REQUIRED';
  end if;
  if v_repeat_required and not v_repeat_present then
    raise exception 'BP_REPEAT_REQUIRED';
  end if;

  if v_repeat_present then
    if p_sbp_repeat not between 70 and 260 then raise exception 'invalid repeat systolic BP'; end if;
    if p_dbp_repeat not between 40 and 180 then raise exception 'invalid repeat diastolic BP'; end if;
    if p_sbp_repeat<=p_dbp_repeat then raise exception 'repeat systolic BP must exceed repeat diastolic BP'; end if;
    v_sbp_effective := round((p_sbp+p_sbp_repeat)::numeric/2.0)::integer;
    v_dbp_effective := round((p_dbp+p_dbp_repeat)::numeric/2.0)::integer;
  else
    v_sbp_effective := p_sbp;
    v_dbp_effective := p_dbp;
  end if;

  v_any_grade3 := p_sbp>=180 or p_dbp>=110
    or coalesce(p_sbp_repeat,0)>=180 or coalesce(p_dbp_repeat,0)>=110;

  v_row := public.save_health_ncd_screening_v4(
    p_source_pcucode,p_source_pid,p_screened_on,
    p_weight_kg,p_height_cm,p_waist_cm,
    v_sbp_effective,v_dbp_effective,p_glucose_mg_dl,
    p_glucose_type,p_danger_symptoms,
    p_smoking_frequency,p_alcohol_frequency,p_exercise_frequency,
    p_note,p_request_id,p_mental_2q_q1,p_mental_2q_q2
  );

  v_measure_note := case
    when v_repeat_present then format(
      'เธเธฃเธฑเนเธเนเธฃเธ %s/%s ยท เธเธฃเธฑเนเธเธ—เธตเน 2 %s/%s ยท เธเนเธฒเน€เธเธฅเธตเนเธข %s/%s',
      p_sbp,p_dbp,p_sbp_repeat,p_dbp_repeat,v_sbp_effective,v_dbp_effective
    )
    else 'เธงเธฑเธ” 1 เธเธฃเธฑเนเธ'
  end;

  update public.health_ncd_screenings
  set sbp_first=p_sbp,
      dbp_first=p_dbp,
      sbp_repeat=case when v_repeat_present then p_sbp_repeat else null end,
      dbp_repeat=case when v_repeat_present then p_dbp_repeat else null end,
      bp_measurement_count=case when v_repeat_present then 2 else 1 end,
      bp_status=case
        when v_any_grade3 then 'เธเธเธเนเธฒเธเธงเธฒเธกเธ”เธฑเธเธฃเธฐเธ”เธฑเธ 3/เธญเธฑเธเธ•เธฃเธฒเธขเธญเธขเนเธฒเธเธเนเธญเธข 1 เธเธฃเธฑเนเธ ยท '||v_measure_note
        when v_repeat_present then coalesce(bp_status,'')||' ยท '||v_measure_note
        else bp_status
      end,
      severity=case when v_any_grade3 then 'urgent' else severity end,
      ncd_status=case when v_any_grade3 then 'เธเธงเธฒเธกเธ”เธฑเธเธชเธนเธเธฃเธฐเธ”เธฑเธ 3/เธญเธฑเธเธ•เธฃเธฒเธข (เธชเธตเนเธ”เธ)' else ncd_status end,
      advice=case
        when v_any_grade3 then 'เธเธฑเธเนเธฅเธฐเธงเธฑเธ”เธเนเธณเธญเธขเนเธฒเธเธ–เธนเธเธงเธดเธเธต เธซเธฒเธเธกเธตเธเนเธฒเธ•เธฑเนเธเนเธ•เน 180/110 เธกเธก.เธเธฃเธญเธ—เธเธถเนเธเนเธเธญเธขเนเธฒเธเธเนเธญเธขเธซเธเธถเนเธเธเธฃเธฑเนเธ เธซเธฃเธทเธญเธกเธตเธญเธฒเธเธฒเธฃเธเธดเธ”เธเธเธ•เธด เนเธซเนเธเธฃเธฐเธชเธฒเธเน€เธเนเธฒเธซเธเนเธฒเธ—เธตเนเน€เธเธทเนเธญเธเธฃเธฐเน€เธกเธดเธเน€เธฃเนเธเธ”เนเธงเธ'
        else advice
      end,
      calculation_version='osm-health-ncd-2.0.123-bp-repeat'
  where id=v_row.id
  returning * into v_row;

  update public.health_audit_log
  set details=details || jsonb_build_object(
    'bp_repeat_policy','first_high_140_90',
    'sbp_first',p_sbp,'dbp_first',p_dbp,
    'sbp_repeat',p_sbp_repeat,'dbp_repeat',p_dbp_repeat,
    'bp_measurement_count',case when v_repeat_present then 2 else 1 end,
    'sbp_effective',v_sbp_effective,'dbp_effective',v_dbp_effective,
    'any_grade3',v_any_grade3
  )
  where operator_id=auth.uid()
    and entity='health_ncd_screening'
    and entity_id=v_row.id::text;

  return v_row;
end;
$function$;

revoke all on function public.save_health_ncd_screening_v5(
  text,bigint,date,numeric,numeric,numeric,integer,integer,integer,text,boolean,
  text,text,text,text,uuid,boolean,boolean,integer,integer
) from public,anon;
grant execute on function public.save_health_ncd_screening_v5(
  text,bigint,date,numeric,numeric,numeric,integer,integer,integer,text,boolean,
  text,text,text,text,uuid,boolean,boolean,integer,integer
) to authenticated,service_role;

notify pgrst,'reload schema';
