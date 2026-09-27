-- v1.8.9: optional mental-health 2Q capture alongside NCD screening.
-- JHCIS remains read-only. Existing NCD calculations and v1/v2 RPCs are unchanged.
begin;

alter table public.health_ncd_screenings
  add column if not exists mental_2q_q1 boolean,
  add column if not exists mental_2q_q2 boolean,
  add column if not exists mental_2q_status text not null default 'not_assessed',
  add column if not exists mental_2q_result boolean;

alter table public.health_ncd_screenings
  drop constraint if exists health_ncd_screenings_mental_2q_check;

alter table public.health_ncd_screenings
  add constraint health_ncd_screenings_mental_2q_check check (
    (
      mental_2q_status = 'not_assessed'
      and mental_2q_q1 is null
      and mental_2q_q2 is null
      and mental_2q_result is null
    )
    or (
      mental_2q_status = 'incomplete'
      and ((mental_2q_q1 is null) <> (mental_2q_q2 is null))
      and mental_2q_result is null
    )
    or (
      mental_2q_status = 'assessed'
      and mental_2q_q1 is not null
      and mental_2q_q2 is not null
      and mental_2q_result is not distinct from (mental_2q_q1 or mental_2q_q2)
    )
  );

create or replace function private.evaluate_health_2q(
  p_q1 boolean,
  p_q2 boolean
)
returns table(assessment_status text, assessment_result boolean)
language sql immutable
set search_path = ''
as $$
  select
    case
      when p_q1 is null and p_q2 is null then 'not_assessed'
      when p_q1 is null or p_q2 is null then 'incomplete'
      else 'assessed'
    end,
    case
      when p_q1 is not null and p_q2 is not null then p_q1 or p_q2
      else null::boolean
    end
$$;

revoke all on function private.evaluate_health_2q(boolean,boolean) from public,anon,authenticated;

create or replace function public.save_health_ncd_screening_v3(
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
set search_path = ''
as $$
declare
  v_row public.health_ncd_screenings;
  v_2q_status text;
  v_2q_result boolean;
begin
  -- Preserve idempotency: a repeated request_id returns the original answers.
  select * into v_row
  from public.health_ncd_screenings
  where recorded_by = auth.uid() and request_id = p_request_id;
  if found then return v_row; end if;

  v_row := public.save_health_ncd_screening_v2(
    p_source_pcucode,p_source_pid,p_screened_on,
    p_weight_kg,p_height_cm,p_waist_cm,p_sbp,p_dbp,p_glucose_mg_dl,
    p_glucose_type,p_danger_symptoms,p_smoking_frequency,p_alcohol_frequency,
    p_exercise_frequency,p_note,p_request_id
  );

  select assessment_status,assessment_result
  into v_2q_status,v_2q_result
  from private.evaluate_health_2q(p_mental_2q_q1,p_mental_2q_q2);

  update public.health_ncd_screenings
  set mental_2q_q1 = p_mental_2q_q1,
      mental_2q_q2 = p_mental_2q_q2,
      mental_2q_status = v_2q_status,
      mental_2q_result = v_2q_result
  where id = v_row.id
  returning * into v_row;

  update public.health_audit_log
  set details = details || jsonb_build_object(
    'mental_2q_status',v_2q_status,
    'mental_2q_result',v_2q_result
  )
  where operator_id = auth.uid()
    and entity = 'health_ncd_screening'
    and entity_id = v_row.id::text;

  return v_row;
end;
$$;

revoke all on function public.save_health_ncd_screening_v3(text,bigint,date,numeric,numeric,numeric,integer,integer,integer,text,boolean,text,text,text,text,uuid,boolean,boolean) from public,anon;

grant execute on function public.save_health_ncd_screening_v3(text,bigint,date,numeric,numeric,numeric,integer,integer,integer,text,boolean,text,text,text,text,uuid,boolean,boolean) to authenticated;

create or replace view public.health_2q_summary
with (security_invoker=true)
as
select
  count(*)::bigint as latest_ncd_screenings,
  count(*) filter (where mental_2q_status = 'assessed')::bigint as mental_2q_assessed,
  count(*) filter (where mental_2q_status = 'not_assessed')::bigint as mental_2q_not_assessed,
  count(*) filter (where mental_2q_status = 'incomplete')::bigint as mental_2q_incomplete,
  count(*) filter (where mental_2q_status = 'assessed' and mental_2q_result is true)::bigint as mental_2q_positive,
  count(*) filter (where mental_2q_status = 'assessed' and mental_2q_result is false)::bigint as mental_2q_negative
from (
  select distinct on (source_pcucode,source_pid)
    source_pcucode,source_pid,mental_2q_status,mental_2q_result
  from public.health_ncd_screenings
  order by source_pcucode,source_pid,screened_on desc,recorded_at desc
) latest;

grant select on public.health_2q_summary to authenticated;

create or replace view public.health_ncd_history
with (security_invoker=true)
as
select
  s.id::text as id,s.screened_on,s.source_pcucode,s.source_pid,
  p.display_name,p.gender,p.birth_date,
  s.hcode,h.house_no,h.moo,h.community,
  s.weight_kg,s.height_cm,s.waist_cm,s.bmi,s.sbp,s.dbp,s.glucose_mg_dl,s.glucose_type,
  s.smoking_frequency,s.alcohol_frequency,s.exercise_frequency,
  s.ncd_status,s.severity,s.bp_status,s.glucose_status,s.advice,
  case when s.record_mode='test' then 'เธญเธชเธก. เธเธฅเธฑเธช ยท เธ—เธ”เธชเธญเธ' else 'เธญเธชเธก. เธเธฅเธฑเธช' end::text as source_label,
  true as quality_valid,'{}'::text[] as quality_issues,''::text as legacy_cvd_risk,s.recorded_at,
  s.mental_2q_q1,s.mental_2q_q2,s.mental_2q_status,s.mental_2q_result
from public.health_ncd_screenings s
join public.health_persons p on p.source_pcucode=s.source_pcucode and p.source_pid=s.source_pid
join public.houses h on h.source_pcucode=s.house_pcucode and h.hcode=s.hcode;

grant select on public.health_ncd_history to authenticated;

insert into public.app_settings(key,value)
values ('health_mental_2q',jsonb_build_object(
  'version','1.8.9',
  'required',false,
  'blank_storage','NULL',
  'result_requires_both_answers',true,
  'statuses',jsonb_build_array('assessed','not_assessed','incomplete'),
  'jhcis_write_back',false
))
on conflict(key) do update set value=excluded.value,updated_at=now();

commit;
