-- OSM-PHC Cloud v2.0.32
-- Operational ownership safety net:
--   user  -> own assigned households only
--   staff -> own work or whole assigned community
--   community rows without an active VHV/user account remain visible and fall back to staff
-- No JHCIS write-back. No automatic volunteer_pid reassignment.

begin;

create index if not exists profiles_operational_assignment_v2032
  on public.profiles(volunteer_pid,active,role)
  where volunteer_pid is not null;

create index if not exists houses_assignment_v2032
  on public.houses(volunteer_pid,community);

create index if not exists health_persons_house_scope_v2032
  on public.health_persons(house_pcucode,hcode)
  where active=true;

create or replace function public.assignment_summary_v2032(p_scope text default 'self')
returns jsonb
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
  v_result jsonb;
begin
  if v_uid is null then raise exception 'AUTH_REQUIRED'; end if;
  select role,community,volunteer_pid into v_role,v_community,v_pid
  from public.profiles
  where user_id=v_uid and active=true
  limit 1;
  if not found then raise exception 'PROFILE_NOT_ACTIVE'; end if;

  if v_role='admin' then
    v_scope:='all';
  elsif v_role='user' then
    v_scope:='self';
  elsif v_role='staff' then
    if v_scope not in ('self','community') then v_scope:='self'; end if;
  else
    raise exception 'ROLE_NOT_ALLOWED';
  end if;

  with active_ops as materialized (
    select distinct p.volunteer_pid
    from public.profiles p
    where p.active=true and p.role in ('user','staff') and p.volunteer_pid is not null
  ), scoped_houses as materialized (
    select h.*,
      case
        when nullif(private.community_key(h.community),'') is null then 'unresolved'
        when h.volunteer_pid is null then 'staff_fallback'
        when ao.volunteer_pid is null then 'staff_fallback'
        else 'assigned'
      end as assignment_status,
      case
        when nullif(private.community_key(h.community),'') is null then 'missing_community'
        when h.volunteer_pid is null then 'no_volunteer'
        when ao.volunteer_pid is null then 'no_active_user'
        else 'assigned'
      end as assignment_reason
    from public.houses h
    left join active_ops ao on ao.volunteer_pid=h.volunteer_pid
    where v_role='admin'
       or (v_scope='self' and v_pid is not null and h.volunteer_pid=v_pid)
       or (v_role='staff' and v_scope='community'
           and private.community_key(h.community)=private.community_key(v_community))
  ), people as materialized (
    select p.source_pcucode,p.source_pid,h.assignment_status,h.assignment_reason
    from public.health_persons p
    join scoped_houses h
      on h.source_pcucode=p.house_pcucode and h.hcode=p.hcode
    where p.active=true and coalesce(p.service_population_eligible,false)=true
  ), hstat as (
    select count(*)::bigint houses,
      count(*) filter(where assignment_status='assigned')::bigint assigned_houses,
      count(*) filter(where assignment_status='staff_fallback')::bigint fallback_houses,
      count(*) filter(where assignment_status='unresolved')::bigint unresolved_houses,
      count(*) filter(where assignment_reason='no_volunteer')::bigint no_volunteer_houses,
      count(*) filter(where assignment_reason='no_active_user')::bigint no_active_user_houses
    from scoped_houses
  ), pstat as (
    select count(*)::bigint people,
      count(*) filter(where assignment_status='assigned')::bigint assigned_people,
      count(*) filter(where assignment_status='staff_fallback')::bigint fallback_people,
      count(*) filter(where assignment_status='unresolved')::bigint unresolved_people,
      count(*) filter(where assignment_reason='no_volunteer')::bigint no_volunteer_people,
      count(*) filter(where assignment_reason='no_active_user')::bigint no_active_user_people
    from people
  )
  select jsonb_build_object(
    'version','2.0.32','role',v_role,'scope',v_scope,'community',coalesce(v_community,''),
    'houses',coalesce(h.houses,0),'assigned_houses',coalesce(h.assigned_houses,0),
    'fallback_houses',coalesce(h.fallback_houses,0),'unresolved_houses',coalesce(h.unresolved_houses,0),
    'no_volunteer_houses',coalesce(h.no_volunteer_houses,0),'no_active_user_houses',coalesce(h.no_active_user_houses,0),
    'people',coalesce(p.people,0),'assigned_people',coalesce(p.assigned_people,0),
    'fallback_people',coalesce(p.fallback_people,0),'unresolved_people',coalesce(p.unresolved_people,0),
    'no_volunteer_people',coalesce(p.no_volunteer_people,0),'no_active_user_people',coalesce(p.no_active_user_people,0),
    'fallback_policy','staff_community',
    'scope_label',case when v_role='admin' then 'เธ—เธธเธเธเธทเนเธเธ—เธตเน'
      when v_role='staff' and v_scope='community' then 'เธเธธเธกเธเธ '||coalesce(v_community,'')
      else 'เธเนเธฒเธเนเธฅเธฐเธเธฃเธฐเธเธฒเธเธเธ—เธตเนเธเธฑเธเธฃเธฑเธเธเธดเธ”เธเธญเธ' end
  ) into v_result
  from hstat h cross join pstat p;

  return v_result;
end;
$$;

revoke all on function public.assignment_summary_v2032(text) from public,anon;

grant execute on function public.assignment_summary_v2032(text) to authenticated;

create or replace function public.health_worklist_assignment_json_v2032(
  p_scope text default 'self',
  p_filter text default 'field_targets',
  p_stage text default null,
  p_search text default null,
  p_community text default null,
  p_assignment text default 'all',
  p_limit integer default 300
)
returns jsonb
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
  v_filter text:=lower(btrim(coalesce(p_filter,'field_targets')));
  v_assignment text:=lower(btrim(coalesce(p_assignment,'all')));
  v_stage text:=nullif(btrim(coalesce(p_stage,'')),'');
  v_search text:=left(regexp_replace(btrim(coalesce(p_search,'')),'[%_(),]','','g'),60);
  v_filter_community text:=nullif(btrim(coalesce(p_community,'')),'');
  v_limit integer:=least(greatest(coalesce(p_limit,300),1),300);
  v_result jsonb;
begin
  if v_uid is null then raise exception 'AUTH_REQUIRED'; end if;
  select role,community,volunteer_pid into v_role,v_community,v_pid
  from public.profiles where user_id=v_uid and active=true limit 1;
  if not found then raise exception 'PROFILE_NOT_ACTIVE'; end if;

  if v_role='admin' then
    v_scope:='all';
  elsif v_role='user' then
    v_scope:='self';
  elsif v_role='staff' then
    if v_scope not in ('self','community') then v_scope:='self'; end if;
  else
    raise exception 'ROLE_NOT_ALLOWED';
  end if;
  if v_filter not in ('field_targets','due','targets','known','all') then v_filter:='field_targets'; end if;
  if v_assignment not in ('all','assigned','fallback') then v_assignment:='all'; end if;
  if v_scope<>'community' and v_role<>'admin' then v_assignment:='all'; end if;

  -- Hot path: keep the existing v2.0.30 denormalized target cache for concurrent field use.
  if v_filter='field_targets' then
    with active_ops as materialized (
      select distinct p.volunteer_pid
      from public.profiles p
      where p.active=true and p.role in ('user','staff') and p.volunteer_pid is not null
    ), rows as (
      select c.*,
        case
          when nullif(private.community_key(c.community),'') is null then 'unresolved'
          when c.volunteer_pid is null or ao.volunteer_pid is null then 'staff_fallback'
          else 'assigned'
        end as assignment_status,
        case
          when nullif(private.community_key(c.community),'') is null then 'missing_community'
          when c.volunteer_pid is null then 'no_volunteer'
          when ao.volunteer_pid is null then 'no_active_user'
          else 'assigned'
        end as assignment_reason,
        case
          when nullif(private.community_key(c.community),'') is null then 'เนเธกเนเธฃเธฐเธเธธเธเธธเธกเธเธ ยท เธชเนเธเนเธซเน Admin เธ•เธฃเธงเธเธชเธญเธ'
          when c.volunteer_pid is null then 'เธขเธฑเธเนเธกเนเธกเธต เธญเธชเธก.เธฃเธฑเธเธเธดเธ”เธเธญเธ ยท Staff เธ”เธนเนเธฅเธเธฑเนเธงเธเธฃเธฒเธง'
          when ao.volunteer_pid is null then 'เธกเธต เธญเธชเธก.เนเธเธ—เธฐเน€เธเธตเธขเธเนเธ•เนเธขเธฑเธเนเธกเนเธกเธตเธเธฑเธเธเธตเนเธเนเธเธฒเธ ยท Staff เธ”เธนเนเธฅเธเธฑเนเธงเธเธฃเธฒเธง'
          else 'เธกเธตเธเธนเนเธฃเธฑเธเธเธดเธ”เธเธญเธ'
        end as assignment_label
      from public.health_screening_target_cache_v2030 c
      left join active_ops ao on ao.volunteer_pid=c.volunteer_pid
      where (
        v_role='admin'
        or (v_scope='self' and v_pid is not null and c.volunteer_pid=v_pid)
        or (v_role='staff' and v_scope='community'
            and private.community_key(c.community)=private.community_key(v_community))
      )
        and (v_filter_community is null or private.community_key(c.community)=private.community_key(v_filter_community))
        and (v_stage is null or c.life_stage=v_stage)
        and (v_search='' or c.display_name ilike ('%'||v_search||'%'))
        and (
          v_assignment='all'
          or (v_assignment='assigned' and c.volunteer_pid is not null and ao.volunteer_pid is not null)
          or (v_assignment='fallback' and (c.volunteer_pid is null or ao.volunteer_pid is null))
        )
      order by c.community,c.hcode,c.display_name
      limit v_limit
    )
    select coalesce(jsonb_agg(to_jsonb(r) order by r.community,r.hcode,r.display_name),'[]'::jsonb)
    into v_result from rows r;
    return v_result;
  end if;

  -- Secondary filters are opened on demand, so use the active worklist only for those requests.
  with active_ops as materialized (
    select distinct p.volunteer_pid
    from public.profiles p
    where p.active=true and p.role in ('user','staff') and p.volunteer_pid is not null
  ), rows as (
    select w.*,
      case
        when nullif(private.community_key(w.community),'') is null then 'unresolved'
        when w.volunteer_pid is null or ao.volunteer_pid is null then 'staff_fallback'
        else 'assigned'
      end as assignment_status,
      case
        when nullif(private.community_key(w.community),'') is null then 'missing_community'
        when w.volunteer_pid is null then 'no_volunteer'
        when ao.volunteer_pid is null then 'no_active_user'
        else 'assigned'
      end as assignment_reason,
      case
        when nullif(private.community_key(w.community),'') is null then 'เนเธกเนเธฃเธฐเธเธธเธเธธเธกเธเธ ยท เธชเนเธเนเธซเน Admin เธ•เธฃเธงเธเธชเธญเธ'
        when w.volunteer_pid is null then 'เธขเธฑเธเนเธกเนเธกเธต เธญเธชเธก.เธฃเธฑเธเธเธดเธ”เธเธญเธ ยท Staff เธ”เธนเนเธฅเธเธฑเนเธงเธเธฃเธฒเธง'
        when ao.volunteer_pid is null then 'เธกเธต เธญเธชเธก.เนเธเธ—เธฐเน€เธเธตเธขเธเนเธ•เนเธขเธฑเธเนเธกเนเธกเธตเธเธฑเธเธเธตเนเธเนเธเธฒเธ ยท Staff เธ”เธนเนเธฅเธเธฑเนเธงเธเธฃเธฒเธง'
        else 'เธกเธตเธเธนเนเธฃเธฑเธเธเธดเธ”เธเธญเธ'
      end as assignment_label
    from public.health_person_worklist_active_v1847 w
    left join active_ops ao on ao.volunteer_pid=w.volunteer_pid
    where (
      v_role='admin'
      or (v_scope='self' and v_pid is not null and w.volunteer_pid=v_pid)
      or (v_role='staff' and v_scope='community'
          and private.community_key(w.community)=private.community_key(v_community))
    )
      and (v_filter_community is null or private.community_key(w.community)=private.community_key(v_filter_community))
      and (v_stage is null or w.life_stage=v_stage)
      and (v_search='' or w.display_name ilike ('%'||v_search||'%'))
      and (
        v_filter='all'
        or (v_filter='due' and coalesce(w.ncd_target,false)=true and coalesce(w.screened_current_fy,false)=false)
        or (v_filter='targets' and coalesce(w.ncd_target,false)=true)
        or (v_filter='known' and coalesce(w.known_ncd,false)=true)
      )
      and (
        v_assignment='all'
        or (v_assignment='assigned' and w.volunteer_pid is not null and ao.volunteer_pid is not null)
        or (v_assignment='fallback' and (w.volunteer_pid is null or ao.volunteer_pid is null))
      )
    order by w.community,w.hcode,w.display_name
    limit v_limit
  )
  select coalesce(jsonb_agg(to_jsonb(r) order by r.community,r.hcode,r.display_name),'[]'::jsonb)
  into v_result from rows r;
  return v_result;
end;
$$;

revoke all on function public.health_worklist_assignment_json_v2032(text,text,text,text,text,text,integer) from public,anon;

grant execute on function public.health_worklist_assignment_json_v2032(text,text,text,text,text,text,integer) to authenticated;

create or replace function public.field_work_list_v2032(
  p_scope text default 'self',
  p_task_type text default '',
  p_status text default '',
  p_volunteer_pid bigint default null,
  p_community text default '',
  p_assignment text default 'all',
  p_limit integer default 100,
  p_offset integer default 0
)
returns table(
  source_pcucode text,source_pid bigint,display_name text,age_years integer,hcode text,house_no text,moo text,community text,volunteer_pid bigint,
  task_type text,task_label text,status text,progress_percent integer,priority text,last_activity_at timestamptz,completed_at timestamptz,
  assignment_status text,assignment_reason text,assignment_label text
)
language plpgsql
stable
security definer
set search_path=''
as $$
declare
  v_uid uuid:=auth.uid();v_role text;v_community text;v_pid bigint;
  v_scope text:=lower(btrim(coalesce(p_scope,'self')));
  v_assignment text:=lower(btrim(coalesce(p_assignment,'all')));
begin
  if v_uid is null then raise exception 'AUTH_REQUIRED'; end if;
  select role,profiles.community,profiles.volunteer_pid into v_role,v_community,v_pid
  from public.profiles where user_id=v_uid and active=true limit 1;
  if not found then raise exception 'PROFILE_NOT_ACTIVE'; end if;
  if v_role='admin' then v_scope:='all';
  elsif v_role='user' then v_scope:='self';
  elsif v_role='staff' and v_scope not in ('self','community') then v_scope:='self';
  elsif v_role not in ('admin','staff','user') then raise exception 'ROLE_NOT_ALLOWED';
  end if;
  if v_assignment not in ('all','assigned','fallback') then v_assignment:='all'; end if;
  if v_scope<>'community' and v_role<>'admin' then v_assignment:='all'; end if;

  return query
  with active_ops as materialized (
    select distinct p.volunteer_pid
    from public.profiles p
    where p.active=true and p.role in ('user','staff') and p.volunteer_pid is not null
  )
  select w.source_pcucode,w.source_pid,w.display_name,w.age_years,w.hcode,w.house_no,w.moo,w.community,w.volunteer_pid,
         w.task_type,w.task_label,w.status,w.progress_percent,w.priority,w.last_activity_at,w.completed_at,
         case
           when nullif(private.community_key(w.community),'') is null then 'unresolved'
           when w.volunteer_pid is null or ao.volunteer_pid is null then 'staff_fallback'
           else 'assigned'
         end::text,
         case
           when nullif(private.community_key(w.community),'') is null then 'missing_community'
           when w.volunteer_pid is null then 'no_volunteer'
           when ao.volunteer_pid is null then 'no_active_user'
           else 'assigned'
         end::text,
         case
           when nullif(private.community_key(w.community),'') is null then 'เนเธกเนเธฃเธฐเธเธธเธเธธเธกเธเธ ยท เธชเนเธเนเธซเน Admin เธ•เธฃเธงเธเธชเธญเธ'
           when w.volunteer_pid is null then 'เธขเธฑเธเนเธกเนเธกเธต เธญเธชเธก.เธฃเธฑเธเธเธดเธ”เธเธญเธ ยท Staff เธ”เธนเนเธฅเธเธฑเนเธงเธเธฃเธฒเธง'
           when ao.volunteer_pid is null then 'เธกเธต เธญเธชเธก.เนเธเธ—เธฐเน€เธเธตเธขเธเนเธ•เนเธขเธฑเธเนเธกเนเธกเธตเธเธฑเธเธเธตเนเธเนเธเธฒเธ ยท Staff เธ”เธนเนเธฅเธเธฑเนเธงเธเธฃเธฒเธง'
           else 'เธกเธตเธเธนเนเธฃเธฑเธเธเธดเธ”เธเธญเธ'
         end::text
  from public.field_work_items_v200 w
  left join active_ops ao on ao.volunteer_pid=w.volunteer_pid
  where (
      v_role='admin'
      or (v_scope='self' and v_pid is not null and w.volunteer_pid=v_pid)
      or (v_role='staff' and v_scope='community' and private.community_key(w.community)=private.community_key(v_community))
    )
    and (coalesce(btrim(p_task_type),'')='' or w.task_type=p_task_type)
    and (coalesce(btrim(p_status),'')='' or w.status=p_status)
    and (p_volunteer_pid is null or w.volunteer_pid=p_volunteer_pid)
    and (coalesce(btrim(p_community),'')='' or private.community_key(w.community)=private.community_key(p_community))
    and (
      v_assignment='all'
      or (v_assignment='assigned' and w.volunteer_pid is not null and ao.volunteer_pid is not null)
      or (v_assignment='fallback' and (w.volunteer_pid is null or ao.volunteer_pid is null))
    )
  order by case w.priority when 'red' then 0 when 'orange' then 1 when 'yellow' then 2 else 3 end,
           case w.status when 'due' then 0 when 'partial' then 1 else 2 end,w.community,w.house_no,w.display_name,w.task_type
  limit least(greatest(coalesce(p_limit,100),1),1000)
  offset greatest(coalesce(p_offset,0),0);
end;
$$;

revoke all on function public.field_work_list_v2032(text,text,text,bigint,text,text,integer,integer) from public,anon;

grant execute on function public.field_work_list_v2032(text,text,text,bigint,text,text,integer,integer) to authenticated;

insert into public.app_settings(key,value)
values('assignment_fallback_v2032',jsonb_build_object(
  'version','2.0.32',
  'policy','assigned owner + staff community fallback',
  'active_account_required_for_assigned',true,
  'no_volunteer_fallback','staff',
  'inactive_or_missing_user_fallback','staff',
  'missing_community_fallback','admin',
  'auto_reassign_volunteer_pid',false,
  'jhcis_write_back',false
)) on conflict(key) do update set value=excluded.value,updated_at=now();

notify pgrst,'reload schema';

commit;
