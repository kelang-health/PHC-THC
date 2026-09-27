-- OSM-PHC v1.8.5 โ€” FY2570 go-live control, test reset and production-only NCD counting
-- Real operation starts 2026-10-01 (B.E. 2570 fiscal year).
-- Screenings before go-live are test records and never count as production output.
begin;

alter table public.health_ncd_screenings
  add column if not exists record_mode text not null default 'test';

update public.health_ncd_screenings
set record_mode = case when screened_on < date '2026-10-01' then 'test' else 'production' end
where record_mode is null or record_mode not in ('test','production')
   or (screened_on < date '2026-10-01' and record_mode <> 'test')
   or (screened_on >= date '2026-10-01' and record_mode <> 'production');

alter table public.health_ncd_screenings drop constraint if exists health_ncd_screenings_record_mode_check;

alter table public.health_ncd_screenings
  add constraint health_ncd_screenings_record_mode_check check (record_mode in ('test','production'));

create or replace function private.health_set_record_mode()
returns trigger
language plpgsql
set search_path=''
as $$
begin
  new.record_mode := case when new.screened_on < date '2026-10-01' then 'test' else 'production' end;
  return new;
end;
$$;

drop trigger if exists health_ncd_record_mode_trigger on public.health_ncd_screenings;

create trigger health_ncd_record_mode_trigger
before insert or update of screened_on on public.health_ncd_screenings
for each row execute function private.health_set_record_mode();

-- Preserve reset records as an admin-only immutable JSON archive.
create table if not exists public.health_ncd_screening_reset_archive (
  archive_id bigint generated always as identity primary key,
  original_id uuid not null unique,
  original_row jsonb not null,
  reset_at timestamptz not null default now(),
  reset_by uuid,
  reason text not null default '',
  reset_batch uuid not null
);

alter table public.health_ncd_screening_reset_archive enable row level security;

revoke all on public.health_ncd_screening_reset_archive from public,anon,authenticated;

grant select on public.health_ncd_screening_reset_archive to authenticated;

drop policy if exists health_ncd_reset_archive_admin on public.health_ncd_screening_reset_archive;

create policy health_ncd_reset_archive_admin on public.health_ncd_screening_reset_archive
for select to authenticated using (private.current_role()='admin');

-- Smart NCD Care D screening_rows.sql was field-test data. Keep it only as archive/reference.
alter table public.health_ncd_legacy_screenings
  add column if not exists record_purpose text not null default 'field_test';

update public.health_ncd_legacy_screenings set record_purpose='field_test';

drop policy if exists health_ncd_legacy_select on public.health_ncd_legacy_screenings;

create policy health_ncd_legacy_select on public.health_ncd_legacy_screenings
for select to authenticated using (private.current_role()='admin');

create or replace view public.health_ncd_latest_production
with (security_invoker=true)
as
select distinct on (source_pcucode,source_pid) *
from public.health_ncd_screenings
where record_mode='production'
order by source_pcucode,source_pid,screened_on desc,recorded_at desc;

grant select on public.health_ncd_latest_production to authenticated;

-- Worklist uses current JHCIS/j-report target registry and production OSM Plus results only.
-- The operational fiscal-year start is never earlier than 2026-10-01.
create or replace view public.health_person_worklist
with (security_invoker=true)
as
with fy as (
  select greatest(
    date '2026-10-01',
    case when extract(month from current_date)>=10
      then make_date(extract(year from current_date)::integer,10,1)
      else make_date(extract(year from current_date)::integer-1,10,1) end
  ) as fy_start
), base as (
  select p.*,h.house_no,h.moo,h.community,h.volunteer_pid,
    case when p.birth_date is null then null else extract(year from age(current_date,p.birth_date))::integer end as age_years
  from public.health_persons p
  join public.houses h on h.source_pcucode=p.house_pcucode and h.hcode=p.hcode
  where p.active=true
), app_latest as (
  select * from public.health_ncd_latest_production
), ranked as (
  select b.*,
    a.screened_on as app_screened_on,a.ncd_status as app_ncd_status,a.severity as app_severity,
    a.weight_kg as app_weight_kg,a.height_cm as app_height_cm,a.waist_cm as app_waist_cm,
    a.sbp as app_sbp,a.dbp as app_dbp,a.glucose_mg_dl as app_glucose_mg_dl,a.bmi as app_bmi,
    a.smoker as app_smoker,a.alcohol_risk as app_alcohol_risk,a.exercise_sufficient as app_exercise_sufficient,
    a.smoking_frequency as app_smoking_frequency,a.alcohol_frequency as app_alcohol_frequency,a.exercise_frequency as app_exercise_frequency,
    (a.screened_on is not null and (b.previous_screened_on is null or a.screened_on>=b.previous_screened_on)) as app_is_latest
  from base b
  left join app_latest a on a.source_pcucode=b.source_pcucode and a.source_pid=b.source_pid
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
  case when (case when r.app_is_latest then r.app_screened_on else r.previous_screened_on end)
       between fy.fy_start and current_date then true else false end as screened_current_fy,
  case when r.app_is_latest then r.app_screened_on else r.previous_screened_on end as previous_screened_on,
  (case when r.app_is_latest then r.app_weight_kg else r.previous_weight_kg end)::numeric(5,2) as previous_weight_kg,
  (case when r.app_is_latest then r.app_height_cm else r.previous_height_cm end)::numeric(5,2) as previous_height_cm,
  (case when r.app_is_latest then r.app_waist_cm else r.previous_waist_cm end)::numeric(5,2) as previous_waist_cm,
  case when r.app_is_latest then r.app_sbp else r.previous_sbp end as previous_sbp,
  case when r.app_is_latest then r.app_dbp else r.previous_dbp end as previous_dbp,
  case when r.app_is_latest then r.app_glucose_mg_dl else r.previous_glucose_mg_dl end as previous_glucose_mg_dl,
  (case when r.app_is_latest then r.app_bmi else r.previous_bmi end)::numeric(5,2) as previous_bmi,
  case when r.app_is_latest then 'เธญเธชเธก. เธเธฅเธฑเธช'
       when r.previous_screened_on is not null then coalesce(nullif(r.previous_source,''),'JHCIS / j-report NCD Export')
       else '' end as previous_source,
  case when r.app_is_latest then coalesce(nullif(r.app_smoking_frequency,''),case when r.app_smoker then 'เธชเธนเธ' else 'เนเธกเนเธชเธนเธ' end) else '' end as previous_smoking,
  case when r.app_is_latest then coalesce(nullif(r.app_alcohol_frequency,''),case when r.app_alcohol_risk then 'เธ”เธทเนเธก' else 'เนเธกเนเธ”เธทเนเธก' end) else '' end as previous_alcohol,
  case when r.app_is_latest then coalesce(nullif(r.app_exercise_frequency,''),case when r.app_exercise_sufficient then 'เน€เธเธตเธขเธเธเธญ' else 'เนเธกเนเน€เธเธตเธขเธเธเธญ' end) else '' end as previous_exercise
from ranked r
cross join fy;

grant select on public.health_person_worklist to authenticated;

-- User-facing history excludes the Smart NCD legacy field-test archive.
drop view if exists public.health_ncd_history;

create view public.health_ncd_history
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
  true as quality_valid,'{}'::text[] as quality_issues,''::text as legacy_cvd_risk,s.recorded_at
from public.health_ncd_screenings s
join public.health_persons p on p.source_pcucode=s.source_pcucode and p.source_pid=s.source_pid
join public.houses h on h.source_pcucode=s.house_pcucode and h.hcode=s.hcode;

grant select on public.health_ncd_history to authenticated;

create or replace function public.admin_health_reset_preview()
returns jsonb
language sql stable security definer
set search_path=''
as $$
  select case when auth.role()='service_role' or private.current_role()='admin' then
    jsonb_build_object(
      'go_live_date','2026-10-01',
      'test_screenings',(select count(*) from public.health_ncd_screenings where record_mode='test'),
      'production_screenings',(select count(*) from public.health_ncd_screenings where record_mode='production'),
      'legacy_field_test_archive',(select count(*) from public.health_ncd_legacy_screenings where record_purpose='field_test'),
      'reset_archive',(select count(*) from public.health_ncd_screening_reset_archive)
    )
  else null end;
$$;

revoke all on function public.admin_health_reset_preview() from public,anon,authenticated;

grant execute on function public.admin_health_reset_preview() to service_role;

create or replace function public.admin_reset_health_test_screenings(p_reason text)
returns jsonb
language plpgsql security definer
set search_path=''
as $$
declare
  v_batch uuid := extensions.gen_random_uuid();
  v_count integer := 0;
  v_reason text := btrim(coalesce(p_reason,''));
begin
  if auth.role()<>'service_role' and private.current_role()<>'admin' then
    raise exception 'Not authorized';
  end if;
  if length(v_reason)<5 then raise exception 'Reset reason is required'; end if;

  insert into public.health_ncd_screening_reset_archive(original_id,original_row,reset_by,reason,reset_batch)
  select s.id,to_jsonb(s),auth.uid(),v_reason,v_batch
  from public.health_ncd_screenings s
  where s.record_mode='test'
  on conflict(original_id) do nothing;
  get diagnostics v_count = row_count;

  delete from public.health_ncd_screenings where record_mode='test';

  insert into public.health_audit_log(operator_id,action,entity,entity_id,severity,details)
  values(auth.uid(),'RESET_TEST','health_ncd_screening',v_batch::text,'',
    jsonb_build_object('archived',v_count,'reason',v_reason,'go_live_date','2026-10-01'));

  return jsonb_build_object('ok',true,'archived',v_count,'reset_batch',v_batch,'go_live_date','2026-10-01');
end;
$$;

revoke all on function public.admin_reset_health_test_screenings(text) from public,anon,authenticated;

grant execute on function public.admin_reset_health_test_screenings(text) to service_role;

insert into public.app_settings(key,value)
values ('health_go_live',jsonb_build_object(
  'version','1.8.5',
  'go_live_date','2026-10-01',
  'fiscal_year_be',2570,
  'pre_go_live_mode','test',
  'target_source','j-report ncd_screen_export_report / JHCIS read-only equivalent',
  'target_resync_required',true,
  'target_refresh_after','2026-09-28',
  'legacy_screening','field_test_archive_only',
  'production_counting','record_mode=production and screened_on >= operational FY start',
  'jhcis_write_back',false
))
on conflict(key) do update set value=excluded.value,updated_at=now();

commit;
