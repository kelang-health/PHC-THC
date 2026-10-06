-- Elderly 9-domain basic-health gate v2140
-- People with both known DM and HT must have a same-session basic exam
-- before any elderly 9-domain result can be saved.

create table if not exists public.elderly9_basic_health_checks_v2140 (
  session_id uuid primary key references public.screening_sessions(id) on delete cascade,
  source_pcucode text not null,
  source_pid bigint not null,
  measured_on date not null,
  height_cm numeric(5,1) not null check (height_cm between 80 and 250),
  weight_kg numeric(5,1) not null check (weight_kg between 10 and 400),
  waist_cm numeric(5,1) not null check (waist_cm between 30 and 250),
  sbp smallint not null check (sbp between 70 and 260),
  dbp smallint not null check (dbp between 40 and 180),
  pulse smallint not null check (pulse between 20 and 250),
  respiratory_rate smallint not null check (respiratory_rate between 1 and 100),
  temperature_c numeric(4,1) not null check (temperature_c between 25 and 45),
  measured_by uuid not null references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint elderly9_basic_health_bp_v2140 check (sbp > dbp),
  constraint elderly9_basic_health_person_v2140
    foreign key (source_pcucode, source_pid)
    references public.health_persons(source_pcucode, source_pid)
);

create index if not exists elderly9_basic_health_person_v2140_idx
  on public.elderly9_basic_health_checks_v2140(source_pcucode, source_pid, measured_on desc);

alter table public.elderly9_basic_health_checks_v2140 enable row level security;
revoke all on table public.elderly9_basic_health_checks_v2140 from anon;
revoke insert, update, delete on table public.elderly9_basic_health_checks_v2140 from authenticated;
grant select on table public.elderly9_basic_health_checks_v2140 to authenticated;
grant all on table public.elderly9_basic_health_checks_v2140 to service_role;

drop policy if exists elderly9_basic_health_select_v2140 on public.elderly9_basic_health_checks_v2140;
create policy elderly9_basic_health_select_v2140
on public.elderly9_basic_health_checks_v2140
for select to authenticated
using ((select private.health_can_access_person(source_pcucode, source_pid)));

create or replace function public.save_elderly9_basic_health_v2140(
  p_session_id uuid,
  p_height_cm numeric,
  p_weight_kg numeric,
  p_waist_cm numeric,
  p_sbp integer,
  p_dbp integer,
  p_pulse integer,
  p_respiratory_rate integer,
  p_temperature_c numeric
) returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  s public.screening_sessions%rowtype;
  person public.health_persons%rowtype;
begin
  if auth.uid() is null or private.current_role() not in ('user','staff','admin') then
    raise exception 'AUTH_REQUIRED';
  end if;

  select * into s from public.screening_sessions where id=p_session_id for update;
  if not found or not private.health_can_access_person(s.source_pcucode,s.source_pid) then
    raise exception 'SESSION_OUT_OF_SCOPE';
  end if;
  if s.route<>'elderly_60_plus' or s.age_years<60 then
    raise exception 'ELDERLY9_NOT_APPLICABLE';
  end if;

  select * into person
  from public.health_persons
  where source_pcucode=s.source_pcucode and source_pid=s.source_pid;
  if not found or not (coalesce(person.has_dm,false) and coalesce(person.has_ht,false)) then
    raise exception 'ELDERLY_BASIC_HEALTH_NOT_REQUIRED';
  end if;

  if p_height_cm is null or p_height_cm not between 80 and 250 then raise exception 'INVALID_HEIGHT'; end if;
  if p_weight_kg is null or p_weight_kg not between 10 and 400 then raise exception 'INVALID_WEIGHT'; end if;
  if p_waist_cm is null or p_waist_cm not between 30 and 250 then raise exception 'INVALID_WAIST'; end if;
  if p_sbp is null or p_sbp not between 70 and 260 then raise exception 'INVALID_SBP'; end if;
  if p_dbp is null or p_dbp not between 40 and 180 or p_sbp<=p_dbp then raise exception 'INVALID_DBP'; end if;
  if p_pulse is null or p_pulse not between 20 and 250 then raise exception 'INVALID_PULSE'; end if;
  if p_respiratory_rate is null or p_respiratory_rate not between 1 and 100 then raise exception 'INVALID_RESPIRATORY_RATE'; end if;
  if p_temperature_c is null or p_temperature_c not between 25 and 45 then raise exception 'INVALID_TEMPERATURE'; end if;

  insert into public.elderly9_basic_health_checks_v2140(
    session_id,source_pcucode,source_pid,measured_on,height_cm,weight_kg,waist_cm,
    sbp,dbp,pulse,respiratory_rate,temperature_c,measured_by
  ) values (
    s.id,s.source_pcucode,s.source_pid,s.screening_date,p_height_cm,p_weight_kg,p_waist_cm,
    p_sbp,p_dbp,p_pulse,p_respiratory_rate,p_temperature_c,auth.uid()
  )
  on conflict(session_id) do update set
    measured_on=excluded.measured_on,height_cm=excluded.height_cm,weight_kg=excluded.weight_kg,
    waist_cm=excluded.waist_cm,sbp=excluded.sbp,dbp=excluded.dbp,pulse=excluded.pulse,
    respiratory_rate=excluded.respiratory_rate,temperature_c=excluded.temperature_c,
    measured_by=auth.uid(),updated_at=now();

  insert into public.health_audit_log(
    operator_id,action,entity,entity_id,source_pcucode,source_pid,severity,details
  ) values (
    auth.uid(),'UPSERT','elderly9_basic_health',s.id::text,s.source_pcucode,s.source_pid,'normal',
    jsonb_build_object('measured_on',s.screening_date,'reference_version','elderly9-basic-health-v2140')
  );

  return jsonb_build_object(
    'ok',true,'session_id',s.id,'measured_on',s.screening_date,
    'height_cm',p_height_cm,'weight_kg',p_weight_kg,'waist_cm',p_waist_cm,
    'sbp',p_sbp,'dbp',p_dbp,'pulse',p_pulse,
    'respiratory_rate',p_respiratory_rate,'temperature_c',p_temperature_c
  );
end;
$$;

revoke all on function public.save_elderly9_basic_health_v2140(uuid,numeric,numeric,numeric,integer,integer,integer,integer,numeric) from public, anon;
grant execute on function public.save_elderly9_basic_health_v2140(uuid,numeric,numeric,numeric,integer,integer,integer,integer,numeric) to authenticated, service_role;

create or replace function private.require_elderly9_basic_health_v2140()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  s public.screening_sessions%rowtype;
  both_diseases boolean;
begin
  select * into s from public.screening_sessions where id=new.session_id;
  if not found then raise exception 'SESSION_NOT_FOUND'; end if;

  select coalesce(p.has_dm,false) and coalesce(p.has_ht,false)
    into both_diseases
  from public.health_persons p
  where p.source_pcucode=s.source_pcucode and p.source_pid=s.source_pid;

  if s.screening_date>=date '2026-10-06'
     and coalesce(both_diseases,false) and not exists (
    select 1 from public.elderly9_basic_health_checks_v2140 b
    where b.session_id=s.id
      and b.source_pcucode=s.source_pcucode
      and b.source_pid=s.source_pid
      and b.measured_on=s.screening_date
  ) then
    raise exception 'ELDERLY_BASIC_HEALTH_REQUIRED_FIRST';
  end if;
  return new;
end;
$$;

revoke all on function private.require_elderly9_basic_health_v2140() from public, anon, authenticated;

drop trigger if exists elderly9_basic_health_gate_v2140 on public.elderly9_domain_results;
create trigger elderly9_basic_health_gate_v2140
before insert or update on public.elderly9_domain_results
for each row execute function private.require_elderly9_basic_health_v2140();

insert into public.app_settings(key,value,updated_at)
values(
  'elderly9_basic_health_gate_v2140',
  jsonb_build_object(
    'required_when','has_dm_and_has_ht',
    'required_fields',jsonb_build_array('height_cm','weight_kg','waist_cm','sbp','dbp','pulse','respiratory_rate','temperature_c'),
    'excluded_fields',jsonb_build_array('glucose','smoking','alcohol','diagnosis'),
    'same_session_date_required',true
  ),
  now()
)
on conflict(key) do update set value=excluded.value,updated_at=now();

comment on table public.elderly9_basic_health_checks_v2140 is
  'Same-day basic health exam required before elderly 9-domain screening for people with both known DM and HT.';
