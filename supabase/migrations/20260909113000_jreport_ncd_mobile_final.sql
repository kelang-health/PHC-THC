-- v1.8.1 final: align NCD target eligibility with j-report ncd_screen_export_report
-- and finalize mobile behavior-frequency capture. JHCIS remains read-only.
begin;

alter table public.health_persons
  add column if not exists ncd_base_eligible boolean not null default false;

create or replace function public.save_health_ncd_screening_v2(
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
  p_request_id uuid
)
returns public.health_ncd_screenings
language plpgsql security definer
set search_path = ''
as $$
declare
  v_row public.health_ncd_screenings;
  v_smoker boolean;
  v_alcohol boolean;
  v_exercise_ok boolean;
  v_smoke text := coalesce(p_smoking_frequency,'');
  v_alcohol_text text := coalesce(p_alcohol_frequency,'');
  v_exercise text := coalesce(p_exercise_frequency,'');
begin
  if v_smoke not in (
    'เนเธกเนเธชเธนเธ','1-5 เธกเธงเธ/เธงเธฑเธ','6-10 เธกเธงเธ/เธงเธฑเธ','เธกเธฒเธเธเธงเนเธฒ 10 เธกเธงเธ/เธงเธฑเธ',
    '1-5 เธกเธงเธเธ•เนเธญเธงเธฑเธ','6-10 เธกเธงเธเธ•เนเธญเธงเธฑเธ','เธกเธฒเธเธเธงเนเธฒ 10 เธกเธงเธเธ•เนเธญเธงเธฑเธ'
  ) then raise exception 'invalid smoking frequency'; end if;

  if v_alcohol_text not in (
    'เนเธกเนเธ”เธทเนเธก','1-2 เธเธฃเธฑเนเธ/เธชเธฑเธเธ”เธฒเธซเน','3-5 เธเธฃเธฑเนเธ/เธชเธฑเธเธ”เธฒเธซเน','เธ—เธธเธเธงเธฑเธ',
    '1-2 เธเธฃเธฑเนเธเธ•เนเธญเธชเธฑเธเธ”เธฒเธซเน','3-5 เธเธฃเธฑเนเธเธ•เนเธญเธชเธฑเธเธ”เธฒเธซเน'
  ) then raise exception 'invalid alcohol frequency'; end if;

  if v_exercise not in (
    'เธญเธขเนเธฒเธเธเนเธญเธข 3 เธเธฃเธฑเนเธ/เธชเธฑเธเธ”เธฒเธซเน','1-2 เธเธฃเธฑเนเธ/เธชเธฑเธเธ”เธฒเธซเน','เนเธกเนเนเธ”เนเธญเธญเธเธเธณเธฅเธฑเธเธเธฒเธข',
    'เน€เธเธตเธขเธเธเธญ','1-2 เธเธฃเธฑเนเธเธ•เนเธญเธชเธฑเธเธ”เธฒเธซเน'
  ) then raise exception 'invalid exercise frequency'; end if;

  v_smoker := v_smoke <> 'เนเธกเนเธชเธนเธ';
  v_alcohol := v_alcohol_text <> 'เนเธกเนเธ”เธทเนเธก';
  v_exercise_ok := v_exercise in ('เธญเธขเนเธฒเธเธเนเธญเธข 3 เธเธฃเธฑเนเธ/เธชเธฑเธเธ”เธฒเธซเน','เน€เธเธตเธขเธเธเธญ');

  v_row := public.save_health_ncd_screening(
    p_source_pcucode,p_source_pid,p_screened_on,
    p_weight_kg,p_height_cm,p_waist_cm,p_sbp,p_dbp,p_glucose_mg_dl,
    p_glucose_type,p_danger_symptoms,v_smoker,v_alcohol,v_exercise_ok,
    p_note,p_request_id
  );

  update public.health_ncd_screenings
  set smoking_frequency=v_smoke,
      alcohol_frequency=v_alcohol_text,
      exercise_frequency=v_exercise,
      calculation_version='osm-health-ncd-1.8.1'
  where id=v_row.id
  returning * into v_row;

  return v_row;
end;
$$;

revoke all on function public.save_health_ncd_screening_v2(text,bigint,date,numeric,numeric,numeric,integer,integer,integer,text,boolean,text,text,text,text,uuid) from public,anon;

grant execute on function public.save_health_ncd_screening_v2(text,bigint,date,numeric,numeric,numeric,integer,integer,integer,text,boolean,text,text,text,text,uuid) to authenticated;

create or replace view public.health_person_worklist
with (security_invoker=true)
as
with fy as (
  select case when extract(month from current_date)>=10
    then make_date(extract(year from current_date)::integer,10,1)
    else make_date(extract(year from current_date)::integer-1,10,1) end as fy_start
), base as (
  select p.*,h.house_no,h.moo,h.community,h.volunteer_pid,
    case when p.birth_date is null then null else extract(year from age(current_date,p.birth_date))::integer end as age_years
  from public.health_persons p
  join public.houses h on h.source_pcucode=p.house_pcucode and h.hcode=p.hcode
  where p.active=true
), latest as (
  select * from public.health_ncd_latest
), ranked as (
  select b.*,
    l.screened_on as app_screened_on,l.ncd_status as app_ncd_status,l.severity as app_severity,
    l.weight_kg as app_weight_kg,l.height_cm as app_height_cm,l.waist_cm as app_waist_cm,
    l.sbp as app_sbp,l.dbp as app_dbp,l.glucose_mg_dl as app_glucose_mg_dl,l.bmi as app_bmi,
    l.smoker as app_smoker,l.alcohol_risk as app_alcohol_risk,l.exercise_sufficient as app_exercise_sufficient,
    l.smoking_frequency as app_smoking_frequency,l.alcohol_frequency as app_alcohol_frequency,l.exercise_frequency as app_exercise_frequency,
    (l.screened_on is not null and (b.previous_screened_on is null or l.screened_on>=b.previous_screened_on)) as app_is_latest
  from base b
  left join latest l on l.source_pcucode=b.source_pcucode and l.source_pid=b.source_pid
)
select r.source_pcucode,r.source_pid,r.house_pcucode,r.hcode,r.house_no,r.moo,r.community,r.volunteer_pid,
  r.display_name,r.gender,r.birth_date,r.age_years,
  case when r.age_years is null then 'เนเธกเนเธ—เธฃเธฒเธ'
       when r.age_years<=5 then 'เน€เธ”เนเธเธเธเธกเธงเธฑเธข'
       when r.age_years<=14 then 'เน€เธ”เนเธเธงเธฑเธขเน€เธฃเธตเธขเธ'
       when r.age_years<=24 then 'เธงเธฑเธขเธฃเธธเนเธเนเธฅเธฐเน€เธขเธฒเธงเธเธ'
       when r.age_years<=59 then 'เธงเธฑเธขเธ—เธณเธเธฒเธ'
       else 'เธเธนเนเธชเธนเธเธญเธฒเธขเธธ' end as life_stage,
  r.has_ht,r.has_dm,(r.has_ht or r.has_dm) as known_ncd,
  (r.ncd_base_eligible and r.birth_date is not null
    and extract(year from age(fy.fy_start,r.birth_date))::integer>=35
    and not (r.has_ht or r.has_dm)) as ncd_target,
  case when r.app_is_latest then r.app_screened_on else r.previous_screened_on end as latest_screened_on,
  case when r.app_is_latest then r.app_ncd_status
       when r.previous_screened_on is not null then 'เธกเธตเธเธฃเธฐเธงเธฑเธ•เธดเธเธฑเธ”เธเธฃเธญเธเนเธ JHCIS'
       else null end as latest_ncd_status,
  case when r.app_is_latest then r.app_severity else null end as latest_severity,
  case when (case when r.app_is_latest then r.app_screened_on else r.previous_screened_on end) between fy.fy_start and current_date then true else false end as screened_current_fy,
  case when r.app_is_latest then r.app_screened_on else r.previous_screened_on end as previous_screened_on,
  case when r.app_is_latest then r.app_weight_kg else r.previous_weight_kg end as previous_weight_kg,
  case when r.app_is_latest then r.app_height_cm else r.previous_height_cm end as previous_height_cm,
  case when r.app_is_latest then r.app_waist_cm else r.previous_waist_cm end as previous_waist_cm,
  case when r.app_is_latest then r.app_sbp else r.previous_sbp end as previous_sbp,
  case when r.app_is_latest then r.app_dbp else r.previous_dbp end as previous_dbp,
  case when r.app_is_latest then r.app_glucose_mg_dl else r.previous_glucose_mg_dl end as previous_glucose_mg_dl,
  case when r.app_is_latest then r.app_bmi else r.previous_bmi end as previous_bmi,
  case when r.app_is_latest then 'เธญเธชเธก. เธเธฅเธฑเธช'
       when r.previous_screened_on is not null then coalesce(nullif(r.previous_source,''),'JHCIS / j-report NCD Export')
       else '' end as previous_source,
  case when r.app_is_latest then coalesce(nullif(r.app_smoking_frequency,''),case when r.app_smoker then 'เธชเธนเธ' else 'เนเธกเนเธชเธนเธ' end) else '' end as previous_smoking,
  case when r.app_is_latest then coalesce(nullif(r.app_alcohol_frequency,''),case when r.app_alcohol_risk then 'เธ”เธทเนเธก' else 'เนเธกเนเธ”เธทเนเธก' end) else '' end as previous_alcohol,
  case when r.app_is_latest then coalesce(nullif(r.app_exercise_frequency,''),case when r.app_exercise_sufficient then 'เน€เธเธตเธขเธเธเธญ' else 'เนเธกเนเน€เธเธตเธขเธเธเธญ' end) else '' end as previous_exercise
from ranked r
cross join fy;

grant select on public.health_person_worklist to authenticated;

insert into public.app_settings(key,value)
values ('health_screening_ux',jsonb_build_object(
  'version','1.8.1',
  'source_definition','j-report/reports/ncd_screen_export_report',
  'source_transport','direct read-only JHCIS projection; no CSV re-upload required',
  'previous_value_priority','latest date across OSM Plus and JHCIS; OSM Plus wins ties',
  'behavior_frequency',true,
  'mobile_first',true,
  'jhcis_write_back',false
))
on conflict(key) do update set value=excluded.value,updated_at=now();

commit;
