-- Cloud v2.0.30c: denormalized target cache for high-concurrency field use.
begin;

create table if not exists public.health_screening_target_cache_v2030
as select * from public.health_screening_target_worklist_v2026 with no data;

create unique index if not exists health_screening_target_cache_pk_v2030
  on public.health_screening_target_cache_v2030(source_pcucode,source_pid);

create index if not exists health_screening_target_cache_volunteer_v2030
  on public.health_screening_target_cache_v2030(volunteer_pid,community,hcode,display_name);

create index if not exists health_screening_target_cache_community_v2030
  on public.health_screening_target_cache_v2030(community,hcode,display_name);

create index if not exists health_screening_target_cache_stage_v2030
  on public.health_screening_target_cache_v2030(life_stage,volunteer_pid);

alter table public.health_screening_target_cache_v2030 enable row level security;

revoke all on public.health_screening_target_cache_v2030 from public,anon,authenticated;

grant all on public.health_screening_target_cache_v2030 to service_role;

create or replace function public.refresh_screening_target_cache_v2030()
returns jsonb
language plpgsql
security definer
set search_path=''
as $$
declare
  v_count bigint;
begin
  if auth.role()<>'service_role' and (auth.uid() is null or private.current_role()<>'admin') then
    raise exception 'ADMIN_OR_SERVICE_REQUIRED';
  end if;
  truncate table public.health_screening_target_cache_v2030;
  insert into public.health_screening_target_cache_v2030
  select * from public.health_screening_target_worklist_v2026;
  get diagnostics v_count=row_count;
  return jsonb_build_object('ok',true,'cached_rows',v_count,'version','2.0.30');
end;
$$;

revoke all on function public.refresh_screening_target_cache_v2030() from public,anon;

grant execute on function public.refresh_screening_target_cache_v2030() to authenticated,service_role;

-- Initial cache build while migration runs as privileged owner.
truncate table public.health_screening_target_cache_v2030;

insert into public.health_screening_target_cache_v2030
select * from public.health_screening_target_worklist_v2026;

create or replace function public.my_screening_targets_v2030(
  p_scope text default 'self',
  p_stage text default null,
  p_search text default null,
  p_community text default null,
  p_limit integer default 300
)
returns setof public.health_screening_target_worklist_v2026
language plpgsql
stable
security definer
set search_path=''
as $$
declare
  v_uid uuid:=auth.uid();
  v_role text;
  v_community text;
  v_pid bigint;
  v_scope text:=lower(btrim(coalesce(p_scope,'self')));
  v_stage text:=nullif(btrim(coalesce(p_stage,'')),'');
  v_search text:=left(nullif(btrim(coalesce(p_search,'')),''),60);
  v_filter_community text:=nullif(btrim(coalesce(p_community,'')),'');
  v_limit integer:=greatest(1,least(coalesce(p_limit,300),300));
begin
  if v_uid is null then raise exception 'AUTH_REQUIRED'; end if;
  select pr.role,pr.community,pr.volunteer_pid into v_role,v_community,v_pid
  from public.profiles pr where pr.user_id=v_uid and pr.active=true limit 1;
  if not found then raise exception 'PROFILE_NOT_ACTIVE'; end if;

  if v_role='admin' then v_scope:='all';
  elsif v_role='user' then v_scope:='self';
  elsif v_role='staff' then
    if v_scope not in ('self','community') then v_scope:='self'; end if;
  else raise exception 'ROLE_NOT_ALLOWED';
  end if;

  return query
  select c.*
  from public.health_screening_target_cache_v2030 c
  where (
      v_role='admin'
      or (v_scope='self' and v_pid is not null and c.volunteer_pid=v_pid)
      or (v_role='staff' and v_scope='community'
          and private.community_key(c.community)=private.community_key(v_community))
    )
    and (v_filter_community is null or private.community_key(c.community)=private.community_key(v_filter_community))
    and (v_stage is null or c.life_stage=v_stage)
    and (v_search is null or c.display_name ilike ('%'||v_search||'%'))
  order by c.community,c.hcode,c.display_name
  limit v_limit;
end;
$$;

revoke all on function public.my_screening_targets_v2030(text,text,text,text,integer) from public,anon;

grant execute on function public.my_screening_targets_v2030(text,text,text,text,integer) to authenticated;

-- Keep the cache current for the person whose NCD record changes, without rebuilding all targets.
create or replace function private.sync_screening_target_cache_person_v2030()
returns trigger
language plpgsql
security definer
set search_path=''
as $$
declare
  v_pcucode text;
  v_pid bigint;
  v_app public.health_ncd_screenings%rowtype;
  v_person public.health_persons%rowtype;
  v_use_app boolean:=false;
begin
  if tg_op='DELETE' then
    v_pcucode:=old.source_pcucode; v_pid:=old.source_pid;
  else
    v_pcucode:=new.source_pcucode; v_pid:=new.source_pid;
  end if;

  select * into v_person from public.health_persons p
  where p.source_pcucode=v_pcucode and p.source_pid=v_pid;
  if not found then
    if tg_op='DELETE' then return old; else return new; end if;
  end if;

  select * into v_app from public.health_ncd_screenings s
  where s.source_pcucode=v_pcucode and s.source_pid=v_pid
  order by s.screened_on desc,s.recorded_at desc limit 1;
  v_use_app:=found and (v_person.previous_screened_on is null or v_app.screened_on>=v_person.previous_screened_on);

  update public.health_screening_target_cache_v2030 c set
    latest_screened_on=case when v_use_app then v_app.screened_on else v_person.previous_screened_on end,
    latest_ncd_status=case when v_use_app then v_app.ncd_status when v_person.previous_screened_on is not null then 'เธกเธตเธเธฃเธฐเธงเธฑเธ•เธดเธเธฑเธ”เธเธฃเธญเธเน€เธ”เธดเธก' else null end,
    latest_severity=case when v_use_app then v_app.severity else null end,
    screened_current_fy=case when v_use_app and coalesce(v_app.record_mode,'production')='production' then
      v_app.screened_on >= (case when extract(month from current_date)>=10 then make_date(extract(year from current_date)::int,10,1) else make_date(extract(year from current_date)::int-1,10,1) end)
      else false end,
    previous_screened_on=case when v_use_app then v_app.screened_on else v_person.previous_screened_on end,
    previous_weight_kg=case when v_use_app then v_app.weight_kg else v_person.previous_weight_kg end,
    previous_height_cm=case when v_use_app then v_app.height_cm else v_person.previous_height_cm end,
    previous_waist_cm=case when v_use_app then v_app.waist_cm else v_person.previous_waist_cm end,
    previous_sbp=case when v_use_app then v_app.sbp else v_person.previous_sbp end,
    previous_dbp=case when v_use_app then v_app.dbp else v_person.previous_dbp end,
    previous_glucose_mg_dl=case when v_use_app then v_app.glucose_mg_dl else v_person.previous_glucose_mg_dl end,
    previous_bmi=case when v_use_app then v_app.bmi else v_person.previous_bmi end,
    previous_source=case when v_use_app then 'เธญเธชเธก. เธเธฅเธฑเธช' else v_person.previous_source end,
    previous_smoking=case when v_use_app then coalesce(v_app.smoking_frequency,'') else '' end,
    previous_alcohol=case when v_use_app then coalesce(v_app.alcohol_frequency,'') else '' end,
    previous_exercise=case when v_use_app then coalesce(v_app.exercise_frequency,'') else '' end
  where c.source_pcucode=v_pcucode and c.source_pid=v_pid;
  if tg_op='DELETE' then return old; else return new; end if;
end;
$$;

drop trigger if exists health_ncd_target_cache_sync_v2030 on public.health_ncd_screenings;

create trigger health_ncd_target_cache_sync_v2030
after insert or update or delete on public.health_ncd_screenings
for each row execute function private.sync_screening_target_cache_person_v2030();

create or replace function public.admin_refresh_screening_targets_v2026()
returns jsonb
language plpgsql security definer
set search_path=''
as $$
declare v_refresh jsonb; v_cache jsonb;
begin
  if auth.uid() is null or private.current_role()<>'admin' then raise exception 'ADMIN_REQUIRED'; end if;
  v_refresh:=public.refresh_health_screening_plan_v2023(current_date);
  v_cache:=public.refresh_screening_target_cache_v2030();
  insert into public.health_audit_log(operator_id,action,entity,entity_id,severity,details)
  values(auth.uid(),'REFRESH','screening_targets','all','',v_refresh||jsonb_build_object('cache',v_cache));
  return v_refresh || jsonb_build_object('cache',v_cache,'settings',public.screening_target_settings_v2026());
end;
$$;

revoke all on function public.admin_refresh_screening_targets_v2026() from public,anon;

grant execute on function public.admin_refresh_screening_targets_v2026() to authenticated;

insert into public.app_settings(key,value)
values('screening_target_cache_v2030',jsonb_build_object(
  'version','2.0.30','strategy','denormalized_cache_explicit_scope_rpc',
  'runtime_joins',0,'runtime_nested_rls',false,'refresh','after_sync_or_admin_target_change',
  'per_person_ncd_trigger_sync',true,'jhcis_write_back',false
)) on conflict(key) do update set value=excluded.value,updated_at=now();

notify pgrst,'reload schema';

commit;
