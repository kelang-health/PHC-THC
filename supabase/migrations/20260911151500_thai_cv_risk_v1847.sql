-- Cloud v1.8.47: Thai CV Risk (Thai ASCVD score 5, no-lab mode)
-- Published operational formula: Thai NCD / Ministry of Public Health.
-- The result is a 10-year screening risk estimate, not a diagnosis or treatment order.
-- JHCIS remains read-only; only derived eligibility flags are synced to Cloud.
begin;

alter table public.health_persons
  add column if not exists has_cvd boolean not null default false,
  add column if not exists cvd_population_eligible boolean not null default false;

comment on column public.health_persons.has_cvd is
  'Derived from JHCIS chronic diagnoses indicating established cardiovascular/valvular/arrhythmia/cerebrovascular disease; used to exclude Thai CV Risk calculation.';

comment on column public.health_persons.cvd_population_eligible is
  'Derived eligibility flag from JHCIS source for the Thai-population Thai CV Risk model; raw nationality is not uploaded.';

alter table public.health_ncd_screenings
  add column if not exists cvd_risk_percent numeric(6,2),
  add column if not exists cvd_risk_level text not null default '',
  add column if not exists cvd_risk_eligible boolean not null default false,
  add column if not exists cvd_risk_reason text not null default '',
  add column if not exists cvd_full_score numeric(12,6),
  add column if not exists cvd_model_version text not null default '';

alter table public.health_ncd_screenings
  drop constraint if exists health_ncd_screenings_cvd_risk_percent_check;

alter table public.health_ncd_screenings
  add constraint health_ncd_screenings_cvd_risk_percent_check
  check (cvd_risk_percent is null or (cvd_risk_percent >= 0 and cvd_risk_percent <= 100));

alter table public.health_ncd_screenings
  drop constraint if exists health_ncd_screenings_cvd_level_check;

alter table public.health_ncd_screenings
  add constraint health_ncd_screenings_cvd_level_check
  check (cvd_risk_level in ('','low','moderate','high','very_high','dangerous'));

create or replace function private.calculate_thai_cv_risk_v1847(
  p_age integer,
  p_gender text,
  p_sbp integer,
  p_has_dm boolean,
  p_smoker boolean,
  p_waist_cm numeric,
  p_height_cm numeric,
  p_has_cvd boolean,
  p_population_eligible boolean
)
returns table(
  eligible boolean,
  risk_percent numeric,
  risk_level text,
  reason text,
  full_score numeric,
  model_version text
)
language plpgsql immutable
set search_path=''
as $$
declare
  v_sex integer;
  v_score numeric;
  v_risk numeric;
  v_model constant text := 'thai-ascvd-score5-nolab-moph-2026-09';
begin
  if not coalesce(p_population_eligible,false) then
    return query select false,null::numeric,''::text,'population_not_eligible'::text,null::numeric,v_model;
    return;
  end if;
  if p_age is null or p_age < 35 or p_age > 70 then
    return query select false,null::numeric,''::text,'age_outside_35_70'::text,null::numeric,v_model;
    return;
  end if;
  if coalesce(p_has_cvd,false) then
    return query select false,null::numeric,''::text,'known_cvd_excluded'::text,null::numeric,v_model;
    return;
  end if;
  if p_gender not in ('เธเธฒเธข','เธซเธเธดเธ') then
    return query select false,null::numeric,''::text,'gender_unavailable'::text,null::numeric,v_model;
    return;
  end if;
  if p_sbp is null or p_waist_cm is null or p_height_cm is null or p_height_cm <= 0 then
    return query select false,null::numeric,''::text,'required_data_incomplete'::text,null::numeric,v_model;
    return;
  end if;

  -- Thai ASCVD score 5: male=1, female=0; smoker/DM true=1.
  v_sex := case when p_gender='เธเธฒเธข' then 1 else 0 end;
  v_score :=
      (0.079 * p_age)
    + (0.128 * v_sex)
    + (0.019350987 * p_sbp)
    + (0.58454 * case when coalesce(p_has_dm,false) then 1 else 0 end)
    + (3.512566 * (p_waist_cm / p_height_cm))
    + (0.459 * case when coalesce(p_smoker,false) then 1 else 0 end);

  v_risk := (1 - power(0.978296::numeric, exp((v_score - 7.720484)::double precision)::numeric)) * 100;
  v_risk := greatest(0::numeric,least(100::numeric,v_risk));

  return query select
    true,
    round(v_risk,2),
    case
      when v_risk < 10 then 'low'
      when v_risk < 20 then 'moderate'
      when v_risk < 30 then 'high'
      when v_risk < 40 then 'very_high'
      else 'dangerous'
    end::text,
    'assessed'::text,
    round(v_score,6),
    v_model;
end;
$$;

revoke all on function private.calculate_thai_cv_risk_v1847(integer,text,integer,boolean,boolean,numeric,numeric,boolean,boolean) from public,anon,authenticated;

create or replace function public.save_health_ncd_screening_v4(
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
  p_mental_2q_q2 boolean default null
)
returns public.health_ncd_screenings
language plpgsql security definer
set search_path=''
as $$
declare
  v_row public.health_ncd_screenings;
  v_person public.health_persons;
  v_age integer;
  v_eligible boolean;
  v_risk numeric;
  v_level text;
  v_reason text;
  v_score numeric;
  v_model text;
begin
  v_row := public.save_health_ncd_screening_v3(
    p_source_pcucode,p_source_pid,p_screened_on,
    p_weight_kg,p_height_cm,p_waist_cm,p_sbp,p_dbp,p_glucose_mg_dl,
    p_glucose_type,p_danger_symptoms,p_smoking_frequency,p_alcohol_frequency,
    p_exercise_frequency,p_note,p_request_id,p_mental_2q_q1,p_mental_2q_q2
  );

  select * into v_person
  from public.health_persons
  where source_pcucode=v_row.source_pcucode and source_pid=v_row.source_pid;

  v_age := case when v_person.birth_date is null then null
    else extract(year from age(v_row.screened_on,v_person.birth_date))::integer end;

  select c.eligible,c.risk_percent,c.risk_level,c.reason,c.full_score,c.model_version
  into v_eligible,v_risk,v_level,v_reason,v_score,v_model
  from private.calculate_thai_cv_risk_v1847(
    v_age,v_person.gender,v_row.sbp,v_person.has_dm,v_row.smoker,
    v_row.waist_cm,v_row.height_cm,v_person.has_cvd,v_person.cvd_population_eligible
  ) c;

  update public.health_ncd_screenings
  set cvd_risk_percent=v_risk,
      cvd_risk_level=coalesce(v_level,''),
      cvd_risk_eligible=coalesce(v_eligible,false),
      cvd_risk_reason=coalesce(v_reason,''),
      cvd_full_score=v_score,
      cvd_model_version=coalesce(v_model,''),
      calculation_version='osm-health-ncd-1.8.47'
  where id=v_row.id
  returning * into v_row;

  update public.health_audit_log
  set details=details || jsonb_build_object(
    'cvd_model_version',v_row.cvd_model_version,
    'cvd_risk_eligible',v_row.cvd_risk_eligible,
    'cvd_risk_percent',v_row.cvd_risk_percent,
    'cvd_risk_level',v_row.cvd_risk_level,
    'cvd_risk_reason',v_row.cvd_risk_reason
  )
  where operator_id=auth.uid()
    and entity='health_ncd_screening'
    and entity_id=v_row.id::text;

  return v_row;
end;
$$;

revoke all on function public.save_health_ncd_screening_v4(text,bigint,date,numeric,numeric,numeric,integer,integer,integer,text,boolean,text,text,text,text,uuid,boolean,boolean) from public,anon;

grant execute on function public.save_health_ncd_screening_v4(text,bigint,date,numeric,numeric,numeric,integer,integer,integer,text,boolean,text,text,text,text,uuid,boolean,boolean) to authenticated;

-- New view name avoids changing the column contract of the v1.8.41 view in-place.
create or replace view public.health_person_worklist_active_v1847
with (security_invoker=true) as
select w.*,p.has_cvd,p.cvd_population_eligible
from public.health_person_worklist_active_v1841 w
join public.health_persons p
  on p.source_pcucode=w.source_pcucode and p.source_pid=w.source_pid;

revoke all on table public.health_person_worklist_active_v1847 from anon;

revoke insert,update,delete,truncate,references,trigger on table public.health_person_worklist_active_v1847 from authenticated;

grant select on table public.health_person_worklist_active_v1847 to authenticated;

-- User-facing history: current OSM Plus screenings only; legacy field-test CVD remains archive-only.
drop view if exists public.health_ncd_history;

create view public.health_ncd_history
with (security_invoker=true) as
select
  s.id::text as id,s.screened_on,s.source_pcucode,s.source_pid,
  p.display_name,p.gender,p.birth_date,
  s.hcode,h.house_no,h.moo,h.community,
  s.weight_kg,s.height_cm,s.waist_cm,s.bmi,s.sbp,s.dbp,s.glucose_mg_dl,s.glucose_type,
  s.smoking_frequency,s.alcohol_frequency,s.exercise_frequency,
  s.ncd_status,s.severity,s.bp_status,s.glucose_status,s.advice,
  case when s.record_mode='test' then 'เธญเธชเธก. เธเธฅเธฑเธช ยท เธ—เธ”เธชเธญเธ' else 'เธญเธชเธก. เธเธฅเธฑเธช' end::text as source_label,
  true as quality_valid,'{}'::text[] as quality_issues,''::text as legacy_cvd_risk,
  s.recorded_at,s.mental_2q_q1,s.mental_2q_q2,s.mental_2q_status,s.mental_2q_result,
  s.cvd_risk_percent,s.cvd_risk_level,s.cvd_risk_eligible,s.cvd_risk_reason,s.cvd_model_version
from public.health_ncd_screenings s
join public.health_persons p on p.source_pcucode=s.source_pcucode and p.source_pid=s.source_pid
join public.houses h on h.source_pcucode=s.house_pcucode and h.hcode=s.hcode;

grant select on public.health_ncd_history to authenticated;

insert into public.app_settings(key,value)
values ('thai_cv_risk',jsonb_build_object(
  'version','1.8.47',
  'model','Thai ASCVD score 5',
  'mode','no_total_cholesterol',
  'model_version','thai-ascvd-score5-nolab-moph-2026-09',
  'age_min',35,'age_max',70,
  'inputs',jsonb_build_array('age','sex','sbp','diabetes','smoking','waist_cm','height_cm'),
  'risk_bands',jsonb_build_array('<10','10-<20','20-<30','30-<40','>=40'),
  'server_calculated',true,
  'legacy_cvd_used',false,
  'jhcis_write_back',false,
  'source_formula','Thai NCD Online Survey analysis guide / MOPH Thai CV Risk operational formula',
  'source_scope','Thai people age 35-70 without established CVD; do not use for valvular disease or arrhythmia',
  'future_model_note','DDC is developing a newer Thailand CVD risk score in 2569; preserve model_version for future replacement without rewriting historical results'
))
on conflict(key) do update set value=excluded.value,updated_at=now();

commit;
