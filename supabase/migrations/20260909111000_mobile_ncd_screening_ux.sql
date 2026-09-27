-- v1.8.1 Mobile NCD Screening UX
-- Adds previous JHCIS screening snapshot fields and behavior-frequency details.
-- Existing save_health_ncd_screening RPC remains available for cached v1.8 clients.
begin;

alter table public.health_persons
  add column if not exists previous_screened_on date,
  add column if not exists previous_weight_kg numeric(5,2),
  add column if not exists previous_height_cm numeric(5,2),
  add column if not exists previous_waist_cm numeric(5,2),
  add column if not exists previous_sbp integer,
  add column if not exists previous_dbp integer,
  add column if not exists previous_glucose_mg_dl integer,
  add column if not exists previous_bmi numeric(5,2),
  add column if not exists previous_source text not null default '';

alter table public.health_ncd_screenings
  add column if not exists smoking_frequency text not null default '',
  add column if not exists alcohol_frequency text not null default '',
  add column if not exists exercise_frequency text not null default '';

create or replace view public.health_ncd_latest
with (security_invoker=true)
as
select distinct on (source_pcucode,source_pid) *
from public.health_ncd_screenings
order by source_pcucode,source_pid,screened_on desc,recorded_at desc;

grant select on public.health_ncd_latest to authenticated;

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
  if v_smoke not in ('เนเธกเนเธชเธนเธ','1-5 เธกเธงเธเธ•เนเธญเธงเธฑเธ','6-10 เธกเธงเธเธ•เนเธญเธงเธฑเธ','เธกเธฒเธเธเธงเนเธฒ 10 เธกเธงเธเธ•เนเธญเธงเธฑเธ') then
    raise exception 'invalid smoking frequency';
  end if;
  if v_alcohol_text not in ('เนเธกเนเธ”เธทเนเธก','1-2 เธเธฃเธฑเนเธเธ•เนเธญเธชเธฑเธเธ”เธฒเธซเน','3-5 เธเธฃเธฑเนเธเธ•เนเธญเธชเธฑเธเธ”เธฒเธซเน','เธ—เธธเธเธงเธฑเธ') then
    raise exception 'invalid alcohol frequency';
  end if;
  if v_exercise not in ('เน€เธเธตเธขเธเธเธญ','1-2 เธเธฃเธฑเนเธเธ•เนเธญเธชเธฑเธเธ”เธฒเธซเน','เนเธกเนเนเธ”เนเธญเธญเธเธเธณเธฅเธฑเธเธเธฒเธข') then
    raise exception 'invalid exercise frequency';
  end if;

  v_smoker := v_smoke <> 'เนเธกเนเธชเธนเธ';
  v_alcohol := v_alcohol_text <> 'เนเธกเนเธ”เธทเนเธก';
  v_exercise_ok := v_exercise = 'เน€เธเธตเธขเธเธเธญ';

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
with base as (
  select p.*,h.house_no,h.moo,h.community,h.volunteer_pid,
    case when p.birth_date is null then null else extract(year from age(current_date,p.birth_date))::integer end as age_years
  from public.health_persons p
  join public.houses h on h.source_pcucode=p.house_pcucode and h.hcode=p.hcode
  where p.active=true
), latest as (
  select * from public.health_ncd_latest
), fy as (
  select case when extract(month from current_date)>=10
    then make_date(extract(year from current_date)::integer,10,1)
    else make_date(extract(year from current_date)::integer-1,10,1) end as fy_start
)
select b.source_pcucode,b.source_pid,b.house_pcucode,b.hcode,b.house_no,b.moo,b.community,b.volunteer_pid,
  b.display_name,b.gender,b.birth_date,b.age_years,
  case when b.age_years is null then 'เนเธกเนเธ—เธฃเธฒเธ'
       when b.age_years<=5 then 'เน€เธ”เนเธเธเธเธกเธงเธฑเธข'
       when b.age_years<=14 then 'เน€เธ”เนเธเธงเธฑเธขเน€เธฃเธตเธขเธ'
       when b.age_years<=24 then 'เธงเธฑเธขเธฃเธธเนเธเนเธฅเธฐเน€เธขเธฒเธงเธเธ'
       when b.age_years<=59 then 'เธงเธฑเธขเธ—เธณเธเธฒเธ'
       else 'เธเธนเนเธชเธนเธเธญเธฒเธขเธธ' end as life_stage,
  b.has_ht,b.has_dm,(b.has_ht or b.has_dm) as known_ncd,
  (b.age_years>=35 and not (b.has_ht or b.has_dm)) as ncd_target,
  coalesce(l.screened_on,b.previous_screened_on) as latest_screened_on,
  case when l.screened_on is not null then l.ncd_status
       when b.previous_screened_on is not null then 'เธกเธตเธเธฃเธฐเธงเธฑเธ•เธดเธเธฑเธ”เธเธฃเธญเธเนเธ JHCIS'
       else null end as latest_ncd_status,
  l.severity as latest_severity,
  case when coalesce(l.screened_on,b.previous_screened_on) is not null
         and coalesce(l.screened_on,b.previous_screened_on)>=fy.fy_start then true else false end as screened_current_fy,
  coalesce(l.screened_on,b.previous_screened_on) as previous_screened_on,
  coalesce(l.weight_kg,b.previous_weight_kg) as previous_weight_kg,
  coalesce(l.height_cm,b.previous_height_cm) as previous_height_cm,
  coalesce(l.waist_cm,b.previous_waist_cm) as previous_waist_cm,
  coalesce(l.sbp,b.previous_sbp) as previous_sbp,
  coalesce(l.dbp,b.previous_dbp) as previous_dbp,
  coalesce(l.glucose_mg_dl,b.previous_glucose_mg_dl) as previous_glucose_mg_dl,
  coalesce(l.bmi,b.previous_bmi) as previous_bmi,
  case when l.screened_on is not null then 'เธญเธชเธก. เธเธฅเธฑเธช'
       when b.previous_screened_on is not null then coalesce(nullif(b.previous_source,''),'JHCIS')
       else '' end as previous_source,
  coalesce(nullif(l.smoking_frequency,''),case when l.smoker then 'เธชเธนเธ' else 'เนเธกเนเธชเธนเธ' end) as previous_smoking,
  coalesce(nullif(l.alcohol_frequency,''),case when l.alcohol_risk then 'เธ”เธทเนเธก' else 'เนเธกเนเธ”เธทเนเธก' end) as previous_alcohol,
  coalesce(nullif(l.exercise_frequency,''),case when l.exercise_sufficient then 'เน€เธเธตเธขเธเธเธญ' else 'เนเธกเนเน€เธเธตเธขเธเธเธญ' end) as previous_exercise
from base b
left join latest l on l.source_pcucode=b.source_pcucode and l.source_pid=b.source_pid
cross join fy;

grant select on public.health_person_worklist to authenticated;

drop view if exists public.health_ncd_history;

create view public.health_ncd_history
with (security_invoker=true)
as
select
  s.id,s.screened_on,s.source_pcucode,s.source_pid,
  p.display_name,p.gender,p.birth_date,
  s.hcode,h.house_no,h.moo,h.community,
  s.weight_kg,s.height_cm,s.waist_cm,s.bmi,s.sbp,s.dbp,s.glucose_mg_dl,s.glucose_type,
  s.smoking_frequency,s.alcohol_frequency,s.exercise_frequency,
  s.ncd_status,s.severity,s.bp_status,s.glucose_status,s.advice,s.recorded_at
from public.health_ncd_screenings s
join public.health_persons p
  on p.source_pcucode=s.source_pcucode and p.source_pid=s.source_pid
join public.houses h
  on h.source_pcucode=s.house_pcucode and h.hcode=s.hcode;

grant select on public.health_ncd_history to authenticated;

insert into public.app_settings(key,value)
values ('health_screening_ux',jsonb_build_object(
  'version','1.8.1',
  'previous_value_priority',jsonb_build_array('osm_plus','jhcis'),
  'jhcis_screening_source','ncd_person_ncd_screen read-only',
  'behavior_frequency',true,
  'mobile_first',true,
  'jhcis_write_back',false
))
on conflict(key) do update set value=excluded.value,updated_at=now();

commit;
