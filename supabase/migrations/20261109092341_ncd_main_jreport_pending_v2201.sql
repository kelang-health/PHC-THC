-- Main roster keyed by the JHCIS examination. Field measurements cannot create rows here.
create table private.ncd_main_targets_v2201 (
  id uuid primary key,
  source_pcucode text not null check (source_pcucode = '06116'),
  source_pid bigint not null check (source_pid > 0),
  hcode text not null check (hcode ~ '^[0-9]+$' and hcode not in ('2360','2587')),
  owner_pid bigint,
  community text not null,
  kind text not null check (kind in ('bp','dtx')),
  screened_on date not null,
  due_on date not null check (due_on > screened_on),
  sbp numeric,
  dbp numeric,
  glucose_mg_dl numeric,
  glucose_type text check (glucose_type in ('fasting','random')),
  active boolean not null default true
);
create unique index ncd_main_active_person_v2201
  on private.ncd_main_targets_v2201 (source_pcucode,source_pid,kind) where active;
alter table private.ncd_main_targets_v2201 enable row level security;
revoke all on private.ncd_main_targets_v2201 from public,anon,authenticated;

create table private.ncd_main_sync_state_v2201 (
  source_pcucode text primary key check (source_pcucode = '06116'),
  snapshot_at timestamptz not null,
  target_count integer not null
);
alter table private.ncd_main_sync_state_v2201 enable row level security;
revoke all on private.ncd_main_sync_state_v2201 from public,anon,authenticated;

alter table private.ncd_field_results_v2203
  add column main_target_id uuid references private.ncd_main_targets_v2201(id),
  alter column source_screen_id drop not null,
  add constraint ncd_field_one_source_v2201
    check (num_nonnulls(source_screen_id, main_target_id) = 1);
create unique index ncd_main_bp_slot_v2201
  on private.ncd_field_results_v2203 (main_target_id,measured_on,period,sequence)
  where main_target_id is not null and kind='bp';
create unique index ncd_main_dtx_day_v2201
  on private.ncd_field_results_v2203 (main_target_id,measured_on)
  where main_target_id is not null and kind='dtx';

create function public.sync_ncd_main_targets_v2201(p_targets jsonb, p_snapshot_at timestamptz, p_expected_count integer)
returns jsonb language plpgsql security definer set search_path='' as $$
declare
  v_count integer;
  v_old timestamptz;
  v_today date := timezone('Asia/Bangkok', now())::date;
  v_fy date := make_date(extract(year from v_today)::integer - (extract(month from v_today)<10)::integer,10,1);
begin
  if auth.role() is distinct from 'service_role' then raise exception 'SERVICE_ROLE_REQUIRED'; end if;
  if jsonb_typeof(p_targets) is distinct from 'array' or p_snapshot_at is null
     or p_snapshot_at > now() + interval '5 minutes' or p_snapshot_at < now() - interval '30 minutes'
     or p_expected_count is null or p_expected_count not between 0 and 10000
     or jsonb_array_length(p_targets) is distinct from p_expected_count then
    raise exception 'INVALID_MAIN_SNAPSHOT';
  end if;
  perform pg_catalog.pg_advisory_xact_lock(2201,6116);
  select snapshot_at into v_old from private.ncd_main_sync_state_v2201 where source_pcucode='06116';
  if v_old is not null and p_snapshot_at <= v_old then raise exception 'STALE_MAIN_SNAPSHOT'; end if;
  if exists (
    select 1 from jsonb_to_recordset(p_targets) as t(id uuid, source_pid bigint, kind text, hcode text,
      owner_pid bigint,community text,screened_on date,due_on date)
    where t.id is null or t.source_pid is null or t.source_pid<=0
      or coalesce(t.kind,'') not in ('bp','dtx') or t.hcode is null or t.community is null
      or t.screened_on is null or t.screened_on<v_fy or t.screened_on>v_today
      or t.due_on is null or t.due_on<v_today
  ) then raise exception 'INVALID_MAIN_TARGET'; end if;
  if exists (
    select 1 from jsonb_to_recordset(p_targets) as t(id uuid,source_pid bigint,kind text,screened_on date)
    join private.ncd_main_targets_v2201 old on old.id=t.id
    where (old.source_pid,old.kind,old.screened_on) is distinct from (t.source_pid,t.kind,t.screened_on)
  ) then raise exception 'MAIN_TARGET_IDENTITY_CHANGED'; end if;

  if exists (
    select 1 from jsonb_to_recordset(p_targets) as t(source_pid bigint,hcode text,owner_pid bigint,community text)
    where not exists (
      select 1 from public.health_persons p
      join public.houses h on h.source_pcucode=p.house_pcucode and h.hcode=p.hcode
      where p.source_pcucode='06116' and p.source_pid=t.source_pid
        and p.active and p.service_population_eligible and p.jhcis_typelive in (1,3)
        and h.hcode=t.hcode and h.superseded_by is null and h.verification_status='verified_jhcis'
        and coalesce(h.house_id_11,'')<>'52010046170'
        and h.volunteer_pid is not distinct from t.owner_pid
        and private.community_key(h.community)=private.community_key(t.community)
    )
  ) then raise exception 'MAIN_CLOUD_REGISTRY_MISMATCH'; end if;

  update private.ncd_main_targets_v2201 set active=false where active;
  insert into private.ncd_main_targets_v2201
    (id,source_pcucode,source_pid,hcode,owner_pid,community,kind,screened_on,due_on,sbp,dbp,glucose_mg_dl,glucose_type)
  select id,'06116',source_pid,hcode,owner_pid,community,kind,screened_on,due_on,sbp,dbp,glucose_mg_dl,glucose_type
  from jsonb_to_recordset(p_targets) as t(id uuid,source_pid bigint,hcode text,owner_pid bigint,community text,kind text,
    screened_on date,due_on date,sbp numeric,dbp numeric,glucose_mg_dl numeric,glucose_type text)
  on conflict(id) do update set hcode=excluded.hcode,owner_pid=excluded.owner_pid,community=excluded.community,
    due_on=excluded.due_on,sbp=excluded.sbp,dbp=excluded.dbp,glucose_mg_dl=excluded.glucose_mg_dl,
    glucose_type=excluded.glucose_type,active=true;
  get diagnostics v_count=row_count;
  insert into private.ncd_main_sync_state_v2201 values('06116',p_snapshot_at,v_count)
  on conflict(source_pcucode) do update set snapshot_at=excluded.snapshot_at,target_count=excluded.target_count;
  return jsonb_build_object('synced',v_count,'snapshot_at',p_snapshot_at);
end;
$$;
revoke all on function public.sync_ncd_main_targets_v2201(jsonb,timestamptz,integer) from public,anon,authenticated,service_role;
grant execute on function public.sync_ncd_main_targets_v2201(jsonb,timestamptz,integer) to service_role;

create function private.ncd_main_cases_v2201()
returns table(source_screen_id uuid,kind text,source_pcucode text,source_pid bigint,display_name text,
              house_no text,community text,screened_on date,due_on date,sbp numeric,dbp numeric,
              glucose_mg_dl numeric,glucose_type text)
language sql stable set search_path='' as $$
  select t.id,t.kind,t.source_pcucode,t.source_pid,p.display_name,h.house_no,t.community,t.screened_on,t.due_on,
         t.sbp,t.dbp,t.glucose_mg_dl,t.glucose_type
  from private.ncd_main_targets_v2201 t
  join public.health_persons p on p.source_pcucode=t.source_pcucode and p.source_pid=t.source_pid
  join public.houses h on h.source_pcucode=p.house_pcucode and h.hcode=p.hcode and h.hcode=t.hcode
  join public.profiles a on a.user_id=auth.uid() and a.active
  where t.active and t.due_on>=timezone('Asia/Bangkok',now())::date
    and p.active and p.service_population_eligible and p.jhcis_typelive in (1,3)
    and h.superseded_by is null and h.verification_status='verified_jhcis'
    and coalesce(h.house_id_11,'')<>'52010046170'
    and (a.role='admin'
      or (a.role='staff' and nullif(btrim(a.community),'') is not null
          and private.community_key(a.community)=private.community_key(t.community)
          and private.community_key(t.community)=private.community_key(h.community))
      or (a.role='user' and t.owner_pid=a.volunteer_pid and h.volunteer_pid=t.owner_pid));
$$;
revoke all on function private.ncd_main_cases_v2201() from public,anon,authenticated;

-- Keep the existing client contract, including pagination, with Main as the only target source.
create or replace function public.ncd_field_worklist_page_v2196(
  p_kind text default 'all', p_search text default '', p_offset integer default 0
) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare v_result jsonb;
begin
  if not exists(select 1 from public.profiles where user_id=auth.uid() and active) then raise exception 'AUTH_REQUIRED'; end if;
  with matches as materialized (
    select * from private.ncd_main_cases_v2201() c
    where (p_kind='all' or c.kind=p_kind)
      and strpos(lower(concat_ws(' ',c.display_name,c.house_no,c.community)),lower(left(coalesce(p_search,''),160)))>0
  ), page as (
    select * from matches order by due_on,display_name,source_screen_id
    limit 50 offset greatest(coalesce(p_offset,0),0)
  ), summaries as (
    select p.*, history.measurement_count, coalesce(streak.consecutive,0) as bp_days_consecutive
    from page p
    cross join lateral (
      select count(*) as measurement_count from private.ncd_field_results_v2203 m
      where m.main_target_id=p.source_screen_id and m.kind=p.kind
    ) history
    left join lateral (
      select max(run.days) as consecutive
      from (
        select count(*) as days from (
          select m.measured_on,m.measured_on-row_number() over(order by m.measured_on)::integer as streak
          from private.ncd_field_results_v2203 m
          where m.main_target_id=p.source_screen_id and m.kind='bp'
          group by m.measured_on having count(distinct (m.period,m.sequence))=4
        ) complete_days group by complete_days.streak
      ) run
    ) streak on p.kind='bp'
  )
  select jsonb_build_object(
    'items',coalesce((select jsonb_agg(to_jsonb(s) order by s.due_on,s.display_name,s.source_screen_id) from summaries s),'[]'::jsonb),
    'total',(select count(*) from matches)) into v_result;
  return v_result;
end;
$$;

create or replace function public.ncd_field_case_history_v2196(p_source_screen_id uuid,p_kind text)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare v_result jsonb;
begin
  if not exists(select 1 from private.ncd_main_cases_v2201() c
    where c.source_screen_id=p_source_screen_id and c.kind=p_kind) then raise exception 'CASE_NOT_ALLOWED'; end if;
  select coalesce(jsonb_agg(to_jsonb(m) order by m.measured_on,m.period,m.sequence),'[]'::jsonb)
  into v_result from (
    select measured_on,kind,period,sequence,sbp,dbp,pulse,dtx,fasting
    from private.ncd_field_results_v2203 where main_target_id=p_source_screen_id and kind=p_kind
  ) m;
  return v_result;
end;
$$;

create or replace function public.ncd_field_worklist_v2203()
returns jsonb language plpgsql stable security definer set search_path='' as $$
begin
  if not exists(select 1 from public.profiles where user_id=auth.uid() and active) then raise exception 'AUTH_REQUIRED'; end if;
  return coalesce((
    select jsonb_agg(to_jsonb(c)||jsonb_build_object('measurements',
      public.ncd_field_case_history_v2196(c.source_screen_id,c.kind)) order by c.due_on,c.display_name)
    from private.ncd_main_cases_v2201() c
  ),'[]'::jsonb);
end;
$$;

create or replace function public.save_ncd_field_result_v2203(p_source_screen_id uuid,p_kind text,p_measured_on date,p_request_id uuid,p_sbp integer default null,p_dbp integer default null,p_pulse integer default null,p_period text default null,p_sequence smallint default null,p_dtx integer default null,p_fasting boolean default null)
returns jsonb language plpgsql security definer set search_path='' as $$
declare c record; result uuid;
begin
 perform pg_catalog.pg_advisory_xact_lock(2201,6116);
 select * into c from private.ncd_main_cases_v2201() where source_screen_id=p_source_screen_id and kind=p_kind;
 if c.source_screen_id is null then raise exception 'CASE_NOT_ALLOWED';end if;
 if p_measured_on is null or p_measured_on<=c.screened_on or p_measured_on>timezone('Asia/Bangkok',now())::date then raise exception 'FOLLOWUP_DATE_INVALID';end if;
 if p_request_id is null then raise exception 'REQUEST_ID_REQUIRED';end if;
 if p_kind='bp' and(p_sbp is null or p_dbp is null or p_pulse is null or p_period is null or p_sequence is null or p_sbp not between 70 and 260 or p_dbp not between 40 and 180 or p_sbp<=p_dbp or p_pulse not between 20 and 250 or p_period not in('morning','evening') or p_sequence not in(1,2) or p_dtx is not null or p_fasting is not null) then raise exception 'BP_FIELDS_INVALID';end if;
 if p_kind='dtx' and(p_dtx is null or p_dtx not between 20 and 700 or p_fasting is null or p_sbp is not null or p_dbp is not null or p_pulse is not null or p_period is not null or p_sequence is not null) then raise exception 'DTX_FIELDS_INVALID';end if;
 
 select id into result from private.ncd_field_results_v2203 where request_id=p_request_id and main_target_id=p_source_screen_id and kind=p_kind and recorded_by=auth.uid()
 and (measured_on,sbp,dbp,pulse,period,sequence,dtx,fasting)
     is not distinct from (p_measured_on,p_sbp,p_dbp,p_pulse,p_period,p_sequence,p_dtx,p_fasting);
 if result is not null then return jsonb_build_object('ok',true,'id',result,'replayed',true);end if;
 insert into private.ncd_field_results_v2203(request_id,main_target_id,kind,measured_on,sbp,dbp,pulse,period,sequence,dtx,fasting,recorded_by)
 values(p_request_id,p_source_screen_id,p_kind,p_measured_on,p_sbp,p_dbp,p_pulse,p_period,p_sequence,p_dtx,p_fasting,auth.uid()) returning id into result;
 return jsonb_build_object('ok',true,'id',result);
end $$;

revoke all on function public.ncd_field_worklist_page_v2196(text,text,integer),
  public.ncd_field_case_history_v2196(uuid,text), public.ncd_field_worklist_v2203(),
  public.save_ncd_field_result_v2203(uuid,text,date,uuid,integer,integer,integer,text,smallint,integer,boolean)
  from public,anon;
grant execute on function public.ncd_field_worklist_page_v2196(text,text,integer),
  public.ncd_field_case_history_v2196(uuid,text), public.ncd_field_worklist_v2203(),
  public.save_ncd_field_result_v2203(uuid,text,date,uuid,integer,integer,integer,text,smallint,integer,boolean)
  to authenticated;

notify pgrst,'reload schema';
