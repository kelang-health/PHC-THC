-- OSM-PHC Cloud v2.0.33 - Stabilization & Validation
-- Keeps the v2.0.32 ownership model and adds:
--   * explicit inactive-volunteer / no-account / unresolved classifications
--   * server-authorized staff switching to an active user in the same community
--   * paged worklists and indexed normalized-community filtering
-- JHCIS remains read-only. No fallback workflow updates houses.volunteer_pid.

begin;

create index if not exists health_target_community_key_v2033
  on public.health_screening_target_cache_v2030
  (private.community_key(community), volunteer_pid, hcode, display_name, source_pid);

create index if not exists houses_community_key_assignment_v2033
  on public.houses
  (private.community_key(community), volunteer_pid, source_pcucode, hcode);

create index if not exists volunteers_active_pid_v2033
  on public.volunteers(source_pid, source_pcucode)
  where active=true;

create index if not exists profiles_active_scope_v2033
  on public.profiles(community, volunteer_pid, role)
  where active=true and volunteer_pid is not null;

create or replace function public.staff_volunteer_scope_v2033()
returns table(volunteer_pid bigint,display_name text,community text,account_role text)
language plpgsql
stable
security definer
set search_path=''
as $$
declare
  v_uid uuid:=auth.uid();
  v_role text;
  v_community text;
begin
  if v_uid is null then raise exception 'AUTH_REQUIRED'; end if;
  select p.role,p.community into v_role,v_community
  from public.profiles p where p.user_id=v_uid and p.active=true limit 1;
  if not found then raise exception 'PROFILE_NOT_ACTIVE'; end if;
  if v_role not in ('admin','staff') then raise exception 'ROLE_NOT_ALLOWED'; end if;

  return query
  select p.volunteer_pid,
         coalesce(nullif(v.display_name,''),nullif(p.display_name,''),'เนเธกเนเธฃเธฐเธเธธเธเธทเนเธญ')::text,
         coalesce(nullif(p.community,''),v.community)::text,
         p.role::text
  from public.profiles p
  join public.volunteers v on v.source_pid=p.volunteer_pid and v.active=true
  where p.active=true and p.role='user' and p.volunteer_pid is not null
    and (v_role='admin' or private.community_key(p.community)=private.community_key(v_community))
  order by private.community_key(coalesce(p.community,v.community)),coalesce(v.display_name,p.display_name),p.volunteer_pid;
end;
$$;
revoke all on function public.staff_volunteer_scope_v2033() from public,anon;
grant execute on function public.staff_volunteer_scope_v2033() to authenticated;

create or replace function public.assignment_summary_v2033(
  p_scope text default 'self',
  p_owner_pid bigint default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path=''
as $$
declare
  v_uid uuid:=auth.uid();v_role text;v_community text;v_pid bigint;
  v_scope text:=lower(btrim(coalesce(p_scope,'self')));v_owner bigint:=p_owner_pid;v_result jsonb;
begin
  if v_uid is null then raise exception 'AUTH_REQUIRED'; end if;
  select role,community,volunteer_pid into v_role,v_community,v_pid
  from public.profiles where user_id=v_uid and active=true limit 1;
  if not found then raise exception 'PROFILE_NOT_ACTIVE'; end if;

  if v_role='admin' then v_scope:='all';v_owner:=null;
  elsif v_role='user' then v_scope:='self';v_owner:=v_pid;
  elsif v_role='staff' then
    if v_scope='volunteer' then
      if v_owner is null or not exists(
        select 1 from public.profiles p join public.volunteers v on v.source_pid=p.volunteer_pid and v.active=true
        where p.active=true and p.role='user' and p.volunteer_pid=v_owner
          and private.community_key(p.community)=private.community_key(v_community)
      ) then raise exception 'VOLUNTEER_SCOPE_NOT_ALLOWED'; end if;
    elsif v_scope not in ('self','community') then v_scope:='self';v_owner:=v_pid;
    else v_owner:=case when v_scope='self' then v_pid else null end;
    end if;
  else raise exception 'ROLE_NOT_ALLOWED';
  end if;

  with active_vhv as materialized(
    select distinct v.source_pid from public.volunteers v where v.active=true
  ), active_ops as materialized(
    select distinct v.source_pid
    from public.volunteers v join public.profiles p on p.volunteer_pid=v.source_pid
    where v.active=true and p.active=true and p.role in ('user','staff')
  ), scoped_houses as materialized(
    select h.*,
      case when nullif(private.community_key(h.community),'') is null then 'unresolved'
           when h.volunteer_pid is null or av.source_pid is null or ao.source_pid is null then 'staff_fallback'
           else 'assigned' end assignment_status,
      case when nullif(private.community_key(h.community),'') is null then 'missing_community'
           when h.volunteer_pid is null then 'no_volunteer'
           when av.source_pid is null then 'inactive_volunteer'
           when ao.source_pid is null then 'no_active_user'
           else 'assigned' end assignment_reason
    from public.houses h
    left join active_vhv av on av.source_pid=h.volunteer_pid
    left join active_ops ao on ao.source_pid=h.volunteer_pid
    where v_role='admin'
       or (v_scope in ('self','volunteer') and v_owner is not null and h.volunteer_pid=v_owner)
       or (v_role='staff' and v_scope='community' and private.community_key(h.community)=private.community_key(v_community))
  ), people as materialized(
    select p.source_pcucode,p.source_pid,h.assignment_status,h.assignment_reason
    from public.health_persons p join scoped_houses h on h.source_pcucode=p.house_pcucode and h.hcode=p.hcode
    where p.active=true and coalesce(p.service_population_eligible,false)=true
  ), hstat as(
    select count(*)::bigint houses,count(*) filter(where assignment_status='assigned')::bigint assigned_houses,
      count(*) filter(where assignment_status='staff_fallback')::bigint fallback_houses,
      count(*) filter(where assignment_status='unresolved')::bigint unresolved_houses,
      count(*) filter(where assignment_reason='no_volunteer')::bigint no_volunteer_houses,
      count(*) filter(where assignment_reason='inactive_volunteer')::bigint inactive_volunteer_houses,
      count(*) filter(where assignment_reason='no_active_user')::bigint no_active_user_houses from scoped_houses
  ), pstat as(
    select count(*)::bigint people,count(*) filter(where assignment_status='assigned')::bigint assigned_people,
      count(*) filter(where assignment_status='staff_fallback')::bigint fallback_people,
      count(*) filter(where assignment_status='unresolved')::bigint unresolved_people,
      count(*) filter(where assignment_reason='no_volunteer')::bigint no_volunteer_people,
      count(*) filter(where assignment_reason='inactive_volunteer')::bigint inactive_volunteer_people,
      count(*) filter(where assignment_reason='no_active_user')::bigint no_active_user_people from people
  )
  select jsonb_build_object(
    'version','2.0.33','role',v_role,'scope',v_scope,'community',coalesce(v_community,''),'owner_pid',v_owner,
    'houses',h.houses,'assigned_houses',h.assigned_houses,'fallback_houses',h.fallback_houses,'unresolved_houses',h.unresolved_houses,
    'no_volunteer_houses',h.no_volunteer_houses,'inactive_volunteer_houses',h.inactive_volunteer_houses,'no_active_user_houses',h.no_active_user_houses,
    'people',p.people,'assigned_people',p.assigned_people,'fallback_people',p.fallback_people,'unresolved_people',p.unresolved_people,
    'no_volunteer_people',p.no_volunteer_people,'inactive_volunteer_people',p.inactive_volunteer_people,'no_active_user_people',p.no_active_user_people,
    'fallback_policy','staff_community','auto_reassign_volunteer_pid',false,
    'scope_label',case when v_role='admin' then 'เธ—เธธเธเธเธทเนเธเธ—เธตเน'
      when v_scope='community' then 'เธเธธเธกเธเธ '||coalesce(v_community,'')
      when v_scope='volunteer' then 'เธเธฒเธเธเธญเธ เธญเธชเธก. เธ—เธตเนเน€เธฅเธทเธญเธ'
      else 'เธเนเธฒเธเนเธฅเธฐเธเธฃเธฐเธเธฒเธเธเธ—เธตเนเธเธฑเธเธฃเธฑเธเธเธดเธ”เธเธญเธ' end
  ) into v_result from hstat h cross join pstat p;
  return v_result;
end;
$$;
revoke all on function public.assignment_summary_v2033(text,bigint) from public,anon;
grant execute on function public.assignment_summary_v2033(text,bigint) to authenticated;

create or replace function public.report_snapshot_v2033(
  p_report_key text,
  p_scope text default 'self',
  p_owner_pid bigint default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path=''
as $$
declare
  v_uid uuid:=auth.uid();v_role text;v_community text;v_pid bigint;
  v_scope text:=lower(btrim(coalesce(p_scope,'self')));v_scope_type text;v_scope_key text;v_owner bigint:=p_owner_pid;
  v_payload jsonb;v_generated timestamptz;v_hdc jsonb;
begin
  if v_uid is null then raise exception 'AUTH_REQUIRED'; end if;
  select role,community,volunteer_pid into v_role,v_community,v_pid
  from public.profiles where user_id=v_uid and active=true limit 1;
  if not found then raise exception 'PROFILE_NOT_ACTIVE'; end if;
  if p_report_key not in ('care','field') then raise exception 'UNKNOWN_REPORT'; end if;

  if v_role='admin' then v_scope:='all';v_scope_type:='all';v_scope_key:='*';v_owner:=null;
  elsif v_role='user' then v_scope:='self';v_scope_type:='volunteer';v_scope_key:=v_pid::text;v_owner:=v_pid;
  elsif v_role='staff' and v_scope='community' then v_scope_type:='community';v_scope_key:=private.community_key(v_community);v_owner:=null;
  elsif v_role='staff' and v_scope='volunteer' then
    if v_owner is null or not exists(
      select 1 from public.profiles p join public.volunteers v on v.source_pid=p.volunteer_pid and v.active=true
      where p.active=true and p.role='user' and p.volunteer_pid=v_owner
        and private.community_key(p.community)=private.community_key(v_community)
    ) then raise exception 'VOLUNTEER_SCOPE_NOT_ALLOWED'; end if;
    v_scope_type:='volunteer';v_scope_key:=v_owner::text;
  elsif v_role='staff' then v_scope:='self';v_scope_type:='volunteer';v_scope_key:=v_pid::text;v_owner:=v_pid;
  else raise exception 'ROLE_NOT_ALLOWED'; end if;
  if nullif(v_scope_key,'') is null then raise exception 'PROFILE_SCOPE_NOT_READY'; end if;

  select c.payload,s.generated_at into v_payload,v_generated
  from public.report_snapshot_state_v2031 s
  join public.report_snapshot_cache_v2031 c on c.generation=s.current_generation
  where s.singleton=true and c.report_key=p_report_key and c.scope_type=v_scope_type and c.scope_key=v_scope_key;
  if not found then return null; end if;

  v_payload:=v_payload||jsonb_build_object('version','2.0.33','role',v_role,'scope',v_scope,'community',coalesce(v_community,''),
    'owner_pid',v_owner,'snapshot_generated_at',v_generated,'snapshot_source','scheduled_cache',
    'scope_label',case when v_role='admin' then 'เธ—เธธเธเธเธทเนเธเธ—เธตเนเธ•เธฒเธกเธชเธดเธ—เธเธดเนเธเธนเนเธ”เธนเนเธฅเธฃเธฐเธเธ'
      when v_scope='community' then 'เธเธธเธกเธเธ '||coalesce(v_community,'')
      when v_scope='volunteer' then 'เธเธฒเธเธเธญเธ เธญเธชเธก. เธ—เธตเนเน€เธฅเธทเธญเธ'
      else 'เธเนเธฒเธเนเธฅเธฐเธเธฃเธฐเธเธฒเธเธเธ—เธตเนเธเธฑเธเธฃเธฑเธเธเธดเธ”เธเธญเธ' end);
  if p_report_key='care' then
    v_payload:=v_payload-'hdc_reference';
    if v_role='admin' then select value into v_hdc from public.app_settings where key='care_reference_hdc' limit 1;
      v_payload:=v_payload||jsonb_build_object('hdc_reference',v_hdc); end if;
  else
    if v_role='user' then v_payload:=v_payload||jsonb_build_object('volunteers','[]'::jsonb,'communities','[]'::jsonb);
    elsif v_role='staff' then v_payload:=v_payload||jsonb_build_object('communities','[]'::jsonb); end if;
  end if;
  return v_payload;
end;
$$;
revoke all on function public.report_snapshot_v2033(text,text,bigint) from public,anon;
grant execute on function public.report_snapshot_v2033(text,text,bigint) to authenticated;

create or replace function public.health_worklist_assignment_json_v2033(
  p_scope text default 'self',p_filter text default 'field_targets',p_stage text default null,
  p_search text default null,p_community text default null,p_assignment text default 'all',
  p_owner_pid bigint default null,p_limit integer default 50,p_offset integer default 0
)
returns jsonb
language plpgsql
stable
security definer
set search_path=''
as $$
declare
  v_uid uuid:=auth.uid();v_role text;v_community text;v_pid bigint;v_owner bigint:=p_owner_pid;
  v_scope text:=lower(btrim(coalesce(p_scope,'self')));v_filter text:=lower(btrim(coalesce(p_filter,'field_targets')));
  v_assignment text:=lower(btrim(coalesce(p_assignment,'all')));v_stage text:=nullif(btrim(coalesce(p_stage,'')),'');
  v_search text:=left(regexp_replace(btrim(coalesce(p_search,'')),'[%_(),]','','g'),60);
  v_filter_community text:=nullif(btrim(coalesce(p_community,'')),'');
  v_limit integer:=least(greatest(coalesce(p_limit,50),1),100);v_offset integer:=greatest(coalesce(p_offset,0),0);v_result jsonb;
begin
  if v_uid is null then raise exception 'AUTH_REQUIRED'; end if;
  select role,community,volunteer_pid into v_role,v_community,v_pid from public.profiles where user_id=v_uid and active=true limit 1;
  if not found then raise exception 'PROFILE_NOT_ACTIVE'; end if;
  if v_role='admin' then v_scope:='all';v_owner:=null;
  elsif v_role='user' then v_scope:='self';v_owner:=v_pid;
  elsif v_role='staff' then
    if v_scope='volunteer' then
      if v_owner is null or not exists(select 1 from public.profiles p join public.volunteers v on v.source_pid=p.volunteer_pid and v.active=true
        where p.active=true and p.role='user' and p.volunteer_pid=v_owner and private.community_key(p.community)=private.community_key(v_community))
      then raise exception 'VOLUNTEER_SCOPE_NOT_ALLOWED'; end if;
    elsif v_scope not in ('self','community') then v_scope:='self';v_owner:=v_pid;
    else v_owner:=case when v_scope='self' then v_pid else null end; end if;
  else raise exception 'ROLE_NOT_ALLOWED'; end if;
  if v_filter not in ('field_targets','due','targets','known','all') then v_filter:='field_targets'; end if;
  if v_assignment not in ('all','assigned','fallback','unresolved') then v_assignment:='all'; end if;
  if v_scope<>'community' and v_role<>'admin' then v_assignment:='all'; end if;

  with source_rows as materialized(
    select to_jsonb(c) payload,c.source_pcucode,c.source_pid,c.display_name,c.life_stage,c.community,c.hcode,c.volunteer_pid,
      coalesce(c.ncd_target,false) ncd_target,coalesce(c.screened_current_fy,false) screened_current_fy,coalesce(c.known_ncd,false) known_ncd
    from public.health_screening_target_cache_v2030 c
    where v_filter='field_targets'
    union all
    select to_jsonb(w) payload,w.source_pcucode,w.source_pid,w.display_name,w.life_stage,w.community,w.hcode,w.volunteer_pid,
      coalesce(w.ncd_target,false),coalesce(w.screened_current_fy,false),coalesce(w.known_ncd,false)
    from public.health_person_worklist_active_v1847 w
    where v_filter<>'field_targets'
  ), active_vhv as materialized(select distinct source_pid from public.volunteers where active=true),
  active_ops as materialized(select distinct v.source_pid from public.volunteers v join public.profiles p on p.volunteer_pid=v.source_pid where v.active=true and p.active=true and p.role in ('user','staff')),
  base as materialized(
    select c.*,
      case when nullif(private.community_key(c.community),'') is null then 'unresolved'
           when c.volunteer_pid is null or av.source_pid is null or ao.source_pid is null then 'staff_fallback' else 'assigned' end assignment_status,
      case when nullif(private.community_key(c.community),'') is null then 'missing_community'
           when c.volunteer_pid is null then 'no_volunteer' when av.source_pid is null then 'inactive_volunteer'
           when ao.source_pid is null then 'no_active_user' else 'assigned' end assignment_reason
    from source_rows c
    left join active_vhv av on av.source_pid=c.volunteer_pid left join active_ops ao on ao.source_pid=c.volunteer_pid
    where (v_role='admin' or (v_scope in ('self','volunteer') and v_owner is not null and c.volunteer_pid=v_owner)
      or (v_role='staff' and v_scope='community' and private.community_key(c.community)=private.community_key(v_community)))
      and (v_filter_community is null or private.community_key(c.community)=private.community_key(v_filter_community))
      and (v_stage is null or c.life_stage=v_stage) and (v_search='' or c.display_name ilike('%'||v_search||'%'))
      and (v_filter in ('field_targets','all') or (v_filter='due' and c.ncd_target and not c.screened_current_fy)
        or (v_filter='targets' and c.ncd_target) or (v_filter='known' and c.known_ncd))
  ), filtered as(
    select b.*,b.payload||jsonb_build_object('assignment_status',b.assignment_status,'assignment_reason',b.assignment_reason,'assignment_label',case when b.assignment_reason='missing_community' then 'เนเธกเนเธฃเธฐเธเธธเธเธธเธกเธเธ ยท เธชเนเธเนเธซเน Admin เธ•เธฃเธงเธเธชเธญเธ'
      when b.assignment_reason='no_volunteer' then 'เธขเธฑเธเนเธกเนเธกเธต เธญเธชเธก.เธฃเธฑเธเธเธดเธ”เธเธญเธ ยท Staff เธ”เธนเนเธฅเธเธฑเนเธงเธเธฃเธฒเธง'
      when b.assignment_reason='inactive_volunteer' then 'เธญเธชเธก.เน€เธ”เธดเธกเนเธกเนเธเธเธดเธเธฑเธ•เธดเธเธฒเธเนเธฅเนเธง ยท Staff เธ”เธนเนเธฅเธเธฑเนเธงเธเธฃเธฒเธง'
      when b.assignment_reason='no_active_user' then 'เธกเธต เธญเธชเธก.เนเธ•เนเธขเธฑเธเนเธกเนเธกเธตเธเธฑเธเธเธตเนเธเนเธเธฒเธ ยท Staff เธ”เธนเนเธฅเธเธฑเนเธงเธเธฃเธฒเธง'
      else 'เธกเธตเธเธนเนเธฃเธฑเธเธเธดเธ”เธเธญเธ' end) row_payload
    from base b where v_assignment='all' or b.assignment_status=v_assignment
  ), page as(
    select * from filtered order by community,hcode,display_name,source_pid limit v_limit+1 offset v_offset
  ), visible as(select * from page order by community,hcode,display_name,source_pid limit v_limit)
  select jsonb_build_object('version','2.0.33','rows',coalesce((select jsonb_agg(v.row_payload order by community,hcode,display_name,source_pid) from visible v),'[]'::jsonb),
    'offset',v_offset,'limit',v_limit,'has_more',(select count(*)>v_limit from page)) into v_result;
  return v_result;
end;
$$;
revoke all on function public.health_worklist_assignment_json_v2033(text,text,text,text,text,text,bigint,integer,integer) from public,anon;
grant execute on function public.health_worklist_assignment_json_v2033(text,text,text,text,text,text,bigint,integer,integer) to authenticated;

create or replace function public.field_work_list_v2033(
  p_scope text default 'self',p_task_type text default '',p_status text default '',p_volunteer_pid bigint default null,
  p_community text default '',p_assignment text default 'all',p_owner_pid bigint default null,p_limit integer default 50,p_offset integer default 0
)
returns table(source_pcucode text,source_pid bigint,display_name text,age_years integer,hcode text,house_no text,moo text,community text,volunteer_pid bigint,
  task_type text,task_label text,status text,progress_percent integer,priority text,last_activity_at timestamptz,completed_at timestamptz,
  assignment_status text,assignment_reason text,assignment_label text)
language plpgsql stable security definer set search_path=''
as $$
declare
  v_uid uuid:=auth.uid();v_role text;v_community text;v_pid bigint;v_owner bigint:=p_owner_pid;
  v_scope text:=lower(btrim(coalesce(p_scope,'self')));v_assignment text:=lower(btrim(coalesce(p_assignment,'all')));
begin
  if v_uid is null then raise exception 'AUTH_REQUIRED'; end if;
  select role,profiles.community,profiles.volunteer_pid into v_role,v_community,v_pid from public.profiles where user_id=v_uid and active=true limit 1;
  if not found then raise exception 'PROFILE_NOT_ACTIVE'; end if;
  if v_role='admin' then v_scope:='all';v_owner:=null;
  elsif v_role='user' then v_scope:='self';v_owner:=v_pid;
  elsif v_role='staff' then
    if v_scope='volunteer' then
      if v_owner is null or not exists(select 1 from public.profiles p join public.volunteers v on v.source_pid=p.volunteer_pid and v.active=true
        where p.active=true and p.role='user' and p.volunteer_pid=v_owner and private.community_key(p.community)=private.community_key(v_community))
      then raise exception 'VOLUNTEER_SCOPE_NOT_ALLOWED'; end if;
    elsif v_scope not in ('self','community') then v_scope:='self';v_owner:=v_pid;
    else v_owner:=case when v_scope='self' then v_pid else null end; end if;
  else raise exception 'ROLE_NOT_ALLOWED'; end if;
  if v_assignment not in ('all','assigned','fallback','unresolved') then v_assignment:='all'; end if;
  if v_scope<>'community' and v_role<>'admin' then v_assignment:='all'; end if;

  return query
  with active_vhv as materialized(select distinct source_pid from public.volunteers where active=true),
  active_ops as materialized(select distinct v.source_pid from public.volunteers v join public.profiles p on p.volunteer_pid=v.source_pid where v.active=true and p.active=true and p.role in ('user','staff')),
  classified as(
    select w.*,case when nullif(private.community_key(w.community),'') is null then 'unresolved'
      when w.volunteer_pid is null or av.source_pid is null or ao.source_pid is null then 'staff_fallback' else 'assigned' end a_status,
      case when nullif(private.community_key(w.community),'') is null then 'missing_community' when w.volunteer_pid is null then 'no_volunteer'
      when av.source_pid is null then 'inactive_volunteer' when ao.source_pid is null then 'no_active_user' else 'assigned' end a_reason
    from public.field_work_items_v200 w left join active_vhv av on av.source_pid=w.volunteer_pid left join active_ops ao on ao.source_pid=w.volunteer_pid
    where (v_role='admin' or (v_scope in ('self','volunteer') and v_owner is not null and w.volunteer_pid=v_owner)
      or (v_role='staff' and v_scope='community' and private.community_key(w.community)=private.community_key(v_community)))
      and (coalesce(btrim(p_task_type),'')='' or w.task_type=p_task_type) and (coalesce(btrim(p_status),'')='' or w.status=p_status)
      and (p_volunteer_pid is null or w.volunteer_pid=p_volunteer_pid)
      and (coalesce(btrim(p_community),'')='' or private.community_key(w.community)=private.community_key(p_community))
  )
  select w.source_pcucode,w.source_pid,w.display_name,w.age_years,w.hcode,w.house_no,w.moo,w.community,w.volunteer_pid,
    w.task_type,w.task_label,w.status,w.progress_percent,w.priority,w.last_activity_at,w.completed_at,w.a_status::text,w.a_reason::text,
    case when w.a_reason='missing_community' then 'เนเธกเนเธฃเธฐเธเธธเธเธธเธกเธเธ ยท เธชเนเธเนเธซเน Admin เธ•เธฃเธงเธเธชเธญเธ'
      when w.a_reason='no_volunteer' then 'เธขเธฑเธเนเธกเนเธกเธต เธญเธชเธก.เธฃเธฑเธเธเธดเธ”เธเธญเธ ยท Staff เธ”เธนเนเธฅเธเธฑเนเธงเธเธฃเธฒเธง'
      when w.a_reason='inactive_volunteer' then 'เธญเธชเธก.เน€เธ”เธดเธกเนเธกเนเธเธเธดเธเธฑเธ•เธดเธเธฒเธเนเธฅเนเธง ยท Staff เธ”เธนเนเธฅเธเธฑเนเธงเธเธฃเธฒเธง'
      when w.a_reason='no_active_user' then 'เธกเธต เธญเธชเธก.เนเธ•เนเธขเธฑเธเนเธกเนเธกเธตเธเธฑเธเธเธตเนเธเนเธเธฒเธ ยท Staff เธ”เธนเนเธฅเธเธฑเนเธงเธเธฃเธฒเธง' else 'เธกเธตเธเธนเนเธฃเธฑเธเธเธดเธ”เธเธญเธ' end::text
  from classified w where v_assignment='all' or w.a_status=v_assignment
  order by case w.priority when 'red' then 0 when 'orange' then 1 when 'yellow' then 2 else 3 end,
    case w.status when 'due' then 0 when 'partial' then 1 else 2 end,w.community,w.house_no,w.display_name,w.task_type
  limit least(greatest(coalesce(p_limit,50),1),100) offset greatest(coalesce(p_offset,0),0);
end;
$$;
revoke all on function public.field_work_list_v2033(text,text,text,bigint,text,text,bigint,integer,integer) from public,anon;
grant execute on function public.field_work_list_v2033(text,text,text,bigint,text,text,bigint,integer,integer) to authenticated;

insert into public.app_settings(key,value) values('stabilization_validation_v2033',jsonb_build_object(
  'version','2.0.33','staff_scopes',jsonb_build_array('self','volunteer','community'),'page_size',50,
  'fallback_reasons',jsonb_build_array('no_volunteer','inactive_volunteer','no_active_user'),
  'missing_community_queue','admin','auto_reassign_volunteer_pid',false,'jhcis_write_back',false
)) on conflict(key) do update set value=excluded.value,updated_at=now();

notify pgrst,'reload schema';
commit;
