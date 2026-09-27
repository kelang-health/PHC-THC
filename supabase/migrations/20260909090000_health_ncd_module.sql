-- OSM-PHC v1.8 Health Work Center / Smart NCD Care integration
-- Single Supabase project, single Auth/Profile model, JHCIS read-only source.
-- No Thai citizen ID, HN, phone, or full address is stored in health_persons.
begin;

create table if not exists public.health_persons (
  source_pcucode text not null,
  source_pid bigint not null check (source_pid > 0),
  house_pcucode text not null,
  hcode text not null,
  display_name text not null,
  gender text not null default 'เนเธกเนเธฃเธฐเธเธธ' check (gender in ('เธเธฒเธข','เธซเธเธดเธ','เนเธกเนเธฃเธฐเธเธธ')),
  birth_date date,
  active boolean not null default true,
  has_ht boolean not null default false,
  has_dm boolean not null default false,
  source_updated_at text not null default '',
  sync_token uuid,
  synced_at timestamptz not null default now(),
  primary key (source_pcucode, source_pid),
  foreign key (house_pcucode, hcode)
    references public.houses(source_pcucode, hcode)
);

create index if not exists health_persons_house_idx on public.health_persons(house_pcucode,hcode);

create index if not exists health_persons_birth_idx on public.health_persons(birth_date);

create index if not exists health_persons_ncd_idx on public.health_persons(has_ht,has_dm,active);

create or replace function private.health_can_access_house(p_pcucode text, p_hcode text)
returns boolean
language sql stable security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.houses h
    where h.source_pcucode = p_pcucode
      and h.hcode = p_hcode
      and (
        private.current_role() in ('admin','staff')
        or (private.current_role() = 'user' and h.volunteer_pid = private.current_volunteer_pid())
      )
  );
$$;

revoke all on function private.health_can_access_house(text,text) from public,anon,authenticated;

grant execute on function private.health_can_access_house(text,text) to authenticated;

create or replace function private.health_can_access_person(p_pcucode text, p_pid bigint)
returns boolean
language sql stable security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.health_persons p
    where p.source_pcucode = p_pcucode
      and p.source_pid = p_pid
      and p.active = true
      and private.health_can_access_house(p.house_pcucode,p.hcode)
  );
$$;

revoke all on function private.health_can_access_person(text,bigint) from public,anon,authenticated;

grant execute on function private.health_can_access_person(text,bigint) to authenticated;

alter table public.health_persons enable row level security;

revoke all on public.health_persons from public,anon,authenticated;

grant select on public.health_persons to authenticated;

drop policy if exists health_persons_select on public.health_persons;

create policy health_persons_select on public.health_persons
for select to authenticated
using (active = true and private.health_can_access_house(house_pcucode,hcode));

create table if not exists public.health_ncd_screenings (
  id uuid primary key default extensions.gen_random_uuid(),
  source_pcucode text not null,
  source_pid bigint not null,
  house_pcucode text not null,
  hcode text not null,
  screened_on date not null,
  weight_kg numeric(5,2) not null,
  height_cm numeric(5,2) not null,
  waist_cm numeric(5,2) not null,
  sbp integer not null,
  dbp integer not null,
  glucose_mg_dl integer not null,
  glucose_type text not null check (glucose_type in ('fasting','random','unknown')),
  danger_symptoms boolean not null default false,
  smoker boolean not null default false,
  alcohol_risk boolean not null default false,
  exercise_sufficient boolean not null default false,
  known_ncd boolean not null default false,
  bmi numeric(5,2),
  waist_risk boolean not null default false,
  bp_status text not null,
  glucose_status text not null,
  ncd_status text not null,
  severity text not null check (severity in ('incomplete','normal','risk','alert','urgent')),
  advice text not null default '',
  note text not null default '' check (length(note) <= 1000),
  calculation_version text not null default 'osm-health-ncd-1.8.0',
  request_id uuid not null,
  recorded_by uuid not null references auth.users(id),
  recorded_at timestamptz not null default now(),
  unique(recorded_by,request_id),
  foreign key (source_pcucode,source_pid)
    references public.health_persons(source_pcucode,source_pid),
  foreign key (house_pcucode,hcode)
    references public.houses(source_pcucode,hcode)
);

create index if not exists health_ncd_person_date_idx on public.health_ncd_screenings(source_pcucode,source_pid,screened_on desc,recorded_at desc);

create index if not exists health_ncd_house_date_idx on public.health_ncd_screenings(house_pcucode,hcode,screened_on desc,recorded_at desc);

alter table public.health_ncd_screenings enable row level security;

revoke all on public.health_ncd_screenings from public,anon,authenticated;

grant select on public.health_ncd_screenings to authenticated;

drop policy if exists health_ncd_select on public.health_ncd_screenings;

create policy health_ncd_select on public.health_ncd_screenings
for select to authenticated
using (private.health_can_access_person(source_pcucode,source_pid));

create table if not exists public.health_audit_log (
  id bigint generated always as identity primary key,
  created_at timestamptz not null default now(),
  operator_id uuid,
  action text not null,
  entity text not null,
  entity_id text not null,
  source_pcucode text not null default '',
  source_pid bigint,
  hcode text not null default '',
  severity text not null default '',
  details jsonb not null default '{}'::jsonb
);

alter table public.health_audit_log enable row level security;

revoke all on public.health_audit_log from public,anon,authenticated;

grant select on public.health_audit_log to authenticated;

drop policy if exists health_audit_admin on public.health_audit_log;

create policy health_audit_admin on public.health_audit_log
for select to authenticated using (private.current_role()='admin');

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
language plpgsql security definer
set search_path = ''
as $$
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
  select * into v_person from public.health_persons
  where source_pcucode=btrim(p_source_pcucode) and source_pid=p_source_pid and active=true;
  if not found then raise exception 'Target person not found'; end if;
  if not private.health_can_access_house(v_person.house_pcucode,v_person.hcode) then raise exception 'Not authorized for this person'; end if;
  if v_person.gender not in ('เธเธฒเธข','เธซเธเธดเธ') or v_person.birth_date is null then raise exception 'Please verify gender/birth date in JHCIS'; end if;
  v_age := extract(year from age(v_day,v_person.birth_date))::integer;
  if v_age<18 or v_age>120 then raise exception 'Adult screening only (18-120 years)'; end if;
  if v_day > current_date + 1 then raise exception 'screened_on cannot be in the future'; end if;
  if p_weight_kg is null or p_weight_kg not between 10 and 400 then raise exception 'invalid weight'; end if;
  if p_height_cm is null or p_height_cm not between 80 and 250 then raise exception 'invalid height'; end if;
  if p_waist_cm is null or p_waist_cm not between 30 and 250 then raise exception 'invalid waist'; end if;
  if p_sbp is null or p_sbp not between 70 and 260 then raise exception 'invalid systolic BP'; end if;
  if p_dbp is null or p_dbp not between 40 and 180 then raise exception 'invalid diastolic BP'; end if;
  if p_sbp<=p_dbp then raise exception 'systolic BP must exceed diastolic BP'; end if;
  if p_glucose_mg_dl is null or p_glucose_mg_dl not between 20 and 700 then raise exception 'invalid glucose'; end if;
  if coalesce(p_glucose_type,'') not in ('fasting','random','unknown') then raise exception 'invalid glucose type'; end if;

  select * into v_row from public.health_ncd_screenings
  where recorded_by=auth.uid() and request_id=p_request_id;
  if found then return v_row; end if;

  v_known := coalesce(v_person.has_ht,false) or coalesce(v_person.has_dm,false);
  v_bmi := round(p_weight_kg/power(p_height_cm/100,2),2);
  v_waist_risk := (v_person.gender='เธเธฒเธข' and p_waist_cm>=90) or (v_person.gender='เธซเธเธดเธ' and p_waist_cm>=80);
  v_bp := case
    when p_sbp>=180 or p_dbp>=120 then 'เธเธงเธฒเธกเธ”เธฑเธเธชเธนเธเธกเธฒเธ'
    when p_sbp>=140 or p_dbp>=90 then 'เธเธงเธฒเธกเธ”เธฑเธเธชเธนเธ เธเธงเธฃเธ•เธฃเธงเธเธขเธทเธเธขเธฑเธ'
    when p_sbp>=120 or p_dbp>=80 then 'เธเธงเธฒเธกเธ”เธฑเธเน€เธฃเธดเนเธกเธชเธนเธ'
    when p_sbp<90 or p_dbp<60 then 'เธเธงเธฒเธกเธ”เธฑเธเธ•เนเธณ เธเธงเธฃเธเธฃเธฐเน€เธกเธดเธ'
    else 'เธญเธขเธนเนเนเธเธเนเธงเธเธเธฑเธ”เธเธฃเธญเธเธเธเธ•เธด' end;
  v_glucose := case
    when p_glucose_mg_dl<70 then 'เธเนเธณเธ•เธฒเธฅเธ•เนเธณ'
    when p_glucose_type='fasting' and p_glucose_mg_dl>=126 then 'เธเนเธณเธ•เธฒเธฅเธญเธ”เธญเธฒเธซเธฒเธฃเธชเธนเธ เธเธงเธฃเธ•เธฃเธงเธเธขเธทเธเธขเธฑเธ'
    when p_glucose_type='fasting' and p_glucose_mg_dl>=100 then 'เธเนเธณเธ•เธฒเธฅเธญเธ”เธญเธฒเธซเธฒเธฃเน€เธฃเธดเนเธกเธชเธนเธ'
    when p_glucose_type='fasting' then 'เธญเธขเธนเนเนเธเธเนเธงเธเธเธฑเธ”เธเธฃเธญเธเธเธเธ•เธด'
    when p_glucose_type='random' and p_glucose_mg_dl>=200 then 'เธเนเธณเธ•เธฒเธฅเธชเธนเธ เธเธงเธฃเธ•เธฃเธงเธเธขเธทเธเธขเธฑเธ'
    when p_glucose_type='random' then 'เธขเธฑเธเธชเธฃเธธเธเธเธงเธฒเธกเน€เธชเธตเนเธขเธเน€เธเธฒเธซเธงเธฒเธเนเธกเนเนเธ”เน (เนเธกเนเนเธ”เนเธญเธ”เธญเธฒเธซเธฒเธฃ)'
    else 'เนเธกเนเธ—เธฃเธฒเธเธชเธ–เธฒเธเธฐเธญเธ”เธญเธฒเธซเธฒเธฃ' end;

  if coalesce(p_danger_symptoms,false) then
    v_severity:='urgent'; v_status:='เธกเธตเธญเธฒเธเธฒเธฃเธญเธฑเธเธ•เธฃเธฒเธข (เธชเธตเนเธ”เธ)';
    v_advice:='เธเธฃเธฐเธชเธฒเธเน€เธเนเธฒเธซเธเนเธฒเธ—เธตเนเธชเธฒเธเธฒเธฃเธ“เธชเธธเธเน€เธเธทเนเธญเธเธฃเธฐเน€เธกเธดเธเน€เธฃเนเธเธ”เนเธงเธ เธซเธฒเธเธกเธตเน€เธเนเธเธซเธเนเธฒเธญเธ เธซเธญเธ เธญเนเธญเธเนเธฃเธ เธเธนเธ”เนเธกเนเธเธฑเธ” เธเธถเธกเธซเธฃเธทเธญเธซเธกเธ”เธชเธ•เธด เนเธซเนเธ•เธดเธ”เธ•เนเธญเธซเธเนเธงเธขเธเธธเธเน€เธเธดเธเธ—เธฑเธเธ—เธต';
  elsif p_sbp>=180 or p_dbp>=120 or p_glucose_mg_dl<70 then
    v_severity:='urgent'; v_status:='เธ•เนเธญเธเธเธฃเธฐเน€เธกเธดเธเน€เธฃเนเธเธ”เนเธงเธ (เธชเธตเนเธ”เธ)';
    v_advice:='เนเธเนเธเน€เธเนเธฒเธซเธเนเธฒเธ—เธตเนเธชเธฒเธเธฒเธฃเธ“เธชเธธเธเธ—เธฑเธเธ—เธตเน€เธเธทเนเธญเธเธฃเธฐเน€เธกเธดเธเนเธฅเธฐเธ•เธฃเธงเธเธเนเธณเธญเธขเนเธฒเธเน€เธซเธกเธฒเธฐเธชเธก';
  elsif p_sbp>=140 or p_dbp>=90
     or (p_glucose_type='fasting' and p_glucose_mg_dl>=126)
     or (p_glucose_type='random' and p_glucose_mg_dl>=200) then
    v_severity:='alert';
    v_status:=case when v_known then 'เธเธนเนเธกเธตเนเธฃเธเน€เธ”เธดเธก เธเนเธฒเธ•เธฃเธงเธเธชเธนเธ (เธชเธตเนเธ”เธ)' else 'เธเธฅเธเธฑเธ”เธเธฃเธญเธเธชเธนเธ เธ•เนเธญเธเธ•เธฃเธงเธเธขเธทเธเธขเธฑเธ (เธชเธตเนเธ”เธ)' end;
    v_advice:='เธเธฃเธฐเธชเธฒเธเน€เธเนเธฒเธซเธเนเธฒเธ—เธตเนเน€เธเธทเนเธญเธเธณเธซเธเธ”เธเธฒเธฃเธ•เธฃเธงเธเธขเธทเธเธขเธฑเธเนเธฅเธฐเธเธฑเธ”เธ•เธดเธ”เธ•เธฒเธกเธ•เธฒเธกเนเธเธงเธ—เธฒเธเธซเธเนเธงเธขเธเธฃเธดเธเธฒเธฃ เธเนเธฒเธเนเธณเธ•เธฒเธฅเธเธฃเธฑเนเธเน€เธ”เธตเธขเธงเนเธกเนเธขเธทเธเธขเธฑเธเธเธฒเธฃเธงเธดเธเธดเธเธเธฑเธขเนเธฃเธ';
  elsif v_known then
    v_severity:='risk'; v_status:='เธเธนเนเธกเธตเนเธฃเธเน€เธ”เธดเธก เธ•เนเธญเธเธ•เธดเธ”เธ•เธฒเธก (เธชเธตเน€เธซเธฅเธทเธญเธ)';
    v_advice:='เธ•เธดเธ”เธ•เธฒเธกเธเธฑเธเธซเธเนเธงเธขเธเธฃเธดเธเธฒเธฃเธ•เธฒเธกเนเธเธเน€เธ”เธดเธก เนเธกเนเธชเธฃเธธเธเธงเนเธฒเธซเธฒเธขเธเธฒเธเนเธฃเธเธเธฒเธเธเนเธฒเธ•เธฃเธงเธเธเธฃเธฑเนเธเน€เธ”เธตเธขเธง';
  elsif p_glucose_type='fasting' and (
       p_sbp>=120 or p_dbp>=80 or p_sbp<90 or p_dbp<60 or p_glucose_mg_dl>=100
       or v_bmi<18.5 or v_bmi>=23 or v_waist_risk
       or coalesce(p_smoker,false) or coalesce(p_alcohol_risk,false) or not coalesce(p_exercise_sufficient,false)
  ) then
    v_severity:='risk'; v_status:='เธเธงเธฃเธเธฃเธฐเน€เธกเธดเธเธเธงเธฒเธกเน€เธชเธตเนเธขเธเน€เธเธดเนเธกเน€เธ•เธดเธก (เธชเธตเน€เธซเธฅเธทเธญเธ)';
    v_advice:='เธชเนเธเน€เธชเธฃเธดเธกเธเธฒเธฃเธเธฃเธฑเธเธเธคเธ•เธดเธเธฃเธฃเธกเนเธฅเธฐเนเธซเนเน€เธเนเธฒเธซเธเนเธฒเธ—เธตเนเธเธดเธเธฒเธฃเธ“เธฒเธเธฑเธเธเธฑเธขเน€เธชเธตเนเธขเธเธฃเนเธงเธก เธเธณเธซเธเธ”เนเธเธเธ•เธดเธ”เธ•เธฒเธกเน€เธเธเธฒเธฐเธเธธเธเธเธฅ';
  elsif p_glucose_type='fasting' then
    v_severity:='normal'; v_status:='เธเนเธฒเธ—เธตเนเธ•เธฃเธงเธเธญเธขเธนเนเนเธเธเนเธงเธเธเธฑเธ”เธเธฃเธญเธเธเธเธ•เธด (เธชเธตเน€เธเธตเธขเธง)';
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
    coalesce(p_danger_symptoms,false),coalesce(p_smoker,false),coalesce(p_alcohol_risk,false),coalesce(p_exercise_sufficient,false),v_known,
    v_bmi,v_waist_risk,v_bp,v_glucose,v_status,v_severity,v_advice,left(coalesce(p_note,''),1000),
    'osm-health-ncd-1.8.0',p_request_id,auth.uid()
  ) returning * into v_row;

  insert into public.health_audit_log(operator_id,action,entity,entity_id,source_pcucode,source_pid,hcode,severity,details)
  values(auth.uid(),'CREATE','health_ncd_screening',v_row.id::text,v_row.source_pcucode,v_row.source_pid,v_row.hcode,v_row.severity,
    jsonb_build_object('screened_on',v_row.screened_on,'calculation_version',v_row.calculation_version));
  return v_row;
end;
$$;

revoke all on function public.save_health_ncd_screening(text,bigint,date,numeric,numeric,numeric,integer,integer,integer,text,boolean,boolean,boolean,boolean,text,uuid) from public,anon;

grant execute on function public.save_health_ncd_screening(text,bigint,date,numeric,numeric,numeric,integer,integer,integer,text,boolean,boolean,boolean,boolean,text,uuid) to authenticated;

create or replace view public.health_ncd_latest
with (security_invoker=true)
as
select distinct on (source_pcucode,source_pid) *
from public.health_ncd_screenings
order by source_pcucode,source_pid,screened_on desc,recorded_at desc;

grant select on public.health_ncd_latest to authenticated;

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
  l.screened_on as latest_screened_on,l.ncd_status as latest_ncd_status,l.severity as latest_severity,
  case when l.screened_on is not null and l.screened_on >= fy.fy_start then true else false end as screened_current_fy
from base b
left join latest l on l.source_pcucode=b.source_pcucode and l.source_pid=b.source_pid
cross join fy;

grant select on public.health_person_worklist to authenticated;

create or replace view public.health_work_summary
with (security_invoker=true)
as
select
  count(*)::bigint as people,
  count(*) filter (where age_years>=35)::bigint as age35plus,
  count(*) filter (where ncd_target)::bigint as ncd_targets,
  count(*) filter (where ncd_target and screened_current_fy)::bigint as ncd_screened_current_fy,
  count(*) filter (where ncd_target and not screened_current_fy)::bigint as ncd_due,
  count(*) filter (where known_ncd)::bigint as known_ncd,
  count(*) filter (where life_stage='เน€เธ”เนเธเธเธเธกเธงเธฑเธข')::bigint as early_child,
  count(*) filter (where life_stage='เน€เธ”เนเธเธงเธฑเธขเน€เธฃเธตเธขเธ')::bigint as school_age,
  count(*) filter (where life_stage='เธงเธฑเธขเธฃเธธเนเธเนเธฅเธฐเน€เธขเธฒเธงเธเธ')::bigint as youth,
  count(*) filter (where life_stage='เธงเธฑเธขเธ—เธณเธเธฒเธ')::bigint as working_age,
  count(*) filter (where life_stage='เธเธนเนเธชเธนเธเธญเธฒเธขเธธ')::bigint as older_people
from public.health_person_worklist;

grant select on public.health_work_summary to authenticated;

insert into public.app_settings(key,value)
values ('health_module',jsonb_build_object(
  'name','เธเธฒเธเธชเธธเธเธ เธฒเธ',
  'first_module','Smart NCD Care',
  'auth_source','public.profiles + Supabase Auth',
  'person_source','JHCIS read-only sync -> public.health_persons',
  'person_key','source_pcucode + source_pid',
  'house_scope','public.houses -> volunteer_pid',
  'ncd_target','age >= 35 and no known DM/HT',
  'fiscal_year_start_month',10,
  'jhcis_write_back',false,
  'citizen_id_uploaded',false,
  'screening_notice','screening_not_diagnosis'
))
on conflict(key) do update set value=excluded.value,updated_at=now();

commit;
