-- Cloud v2.0.54: post-login health queue fast path. Auth/Login/LINE Login are intentionally unchanged.
begin;

create index if not exists health_target_cache_pid_pending_v2054_idx
  on public.health_screening_target_cache_v2030
  (volunteer_pid, screened_current_fy, latest_screened_on, community, hcode, display_name, source_pid);

create index if not exists health_target_cache_community_pending_v2054_idx
  on public.health_screening_target_cache_v2030
  (private.community_key(community), screened_current_fy, latest_screened_on, hcode, display_name, source_pid);

create index if not exists health_target_cache_stage_pid_v2054_idx
  on public.health_screening_target_cache_v2030
  (life_stage, volunteer_pid, screened_current_fy, latest_screened_on, hcode, display_name, source_pid);

create or replace function public.health_worklist_assignment_json_v2054(
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
  v_uid uuid:=auth.uid();
  v_role text;
  v_community text;
  v_pid bigint;
  v_owner bigint:=p_owner_pid;
  v_scope text:=lower(btrim(coalesce(p_scope,'self')));
  v_filter text:=lower(btrim(coalesce(p_filter,'field_targets')));
  v_assignment text:=lower(btrim(coalesce(p_assignment,'all')));
  v_stage text:=nullif(btrim(coalesce(p_stage,'')),'');
  v_search text:=left(regexp_replace(btrim(coalesce(p_search,'')),'[%_(),]','','g'),60);
  v_filter_community text:=nullif(btrim(coalesce(p_community,'')),'');
  v_limit integer:=least(greatest(coalesce(p_limit,50),1),100);
  v_offset integer:=greatest(coalesce(p_offset,0),0);
  v_result jsonb;
begin
  if v_uid is null then raise exception 'AUTH_REQUIRED'; end if;

  select role,community,volunteer_pid
    into v_role,v_community,v_pid
  from public.profiles
  where user_id=v_uid and active=true
  limit 1;
  if not found then raise exception 'PROFILE_NOT_ACTIVE'; end if;

  if v_role='admin' then
    v_scope:='all'; v_owner:=null;
  elsif v_role='user' then
    v_scope:='self'; v_owner:=v_pid;
  elsif v_role='staff' then
    if v_scope='volunteer' then
      if v_owner is null or not exists(
        select 1
        from public.profiles p
        join public.volunteers v on v.source_pid=p.volunteer_pid and v.active=true
        where p.active=true and p.role='user' and p.volunteer_pid=v_owner
          and private.community_key(p.community)=private.community_key(v_community)
      ) then raise exception 'VOLUNTEER_SCOPE_NOT_ALLOWED'; end if;
    elsif v_scope not in ('self','community') then
      v_scope:='self'; v_owner:=v_pid;
    else
      v_owner:=case when v_scope='self' then v_pid else null end;
    end if;
  else
    raise exception 'ROLE_NOT_ALLOWED';
  end if;

  if v_filter<>'field_targets' then
    return public.health_worklist_assignment_json_v2033(
      v_scope,v_filter,v_stage,v_search,v_filter_community,v_assignment,
      v_owner,v_limit,v_offset
    );
  end if;

  if v_assignment not in ('all','assigned','fallback','unresolved') then v_assignment:='all'; end if;
  if v_scope<>'community' and v_role<>'admin' then v_assignment:='all'; end if;

  -- Common mobile path: current user or one selected volunteer.
  -- No runtime joins are needed; the active authenticated profile already proves
  -- the operator is allowed to see this owner scope.
  if v_scope in ('self','volunteer') and v_owner is not null then
    with page as materialized (
      select c.*
      from public.health_screening_target_cache_v2030 c
      where c.volunteer_pid=v_owner
        and coalesce(c.screened_current_fy,false)=false
        and (c.latest_screened_on is null or c.latest_screened_on::date<>current_date)
        and (v_filter_community is null or private.community_key(c.community)=private.community_key(v_filter_community))
        and (v_stage is null or c.life_stage=v_stage)
        and (v_search='' or c.display_name ilike('%'||v_search||'%'))
      order by c.community,c.hcode,c.display_name,c.source_pid
      limit v_limit+1 offset v_offset
    ), visible as (
      select p.*,'assigned'::text assignment_status,'assigned'::text assignment_reason,
             'เธกเธตเธเธนเนเธฃเธฑเธเธเธดเธ”เธเธญเธ'::text assignment_label
      from page p
      order by community,hcode,display_name,source_pid
      limit v_limit
    )
    select jsonb_build_object(
      'version','2.0.54','source','health_screening_target_cache_v2030',
      'rows',coalesce((select jsonb_agg(to_jsonb(v) order by community,hcode,display_name,source_pid) from visible v),'[]'::jsonb),
      'offset',v_offset,'limit',v_limit,'has_more',(select count(*)>v_limit from page)
    ) into v_result;
    return v_result;
  end if;

  -- Staff community/admin default path: page the denormalized cache first,
  -- then classify assignment only for the <= 51 visible candidates.
  if v_assignment='all' then
    with candidates as materialized (
      select c.*
      from public.health_screening_target_cache_v2030 c
      where
        (v_role='admin'
          or (v_role='staff' and v_scope='community'
              and private.community_key(c.community)=private.community_key(v_community)))
        and (v_filter_community is null or private.community_key(c.community)=private.community_key(v_filter_community))
        and (v_stage is null or c.life_stage=v_stage)
        and (v_search='' or c.display_name ilike('%'||v_search||'%'))
        and coalesce(c.screened_current_fy,false)=false
        and (c.latest_screened_on is null or c.latest_screened_on::date<>current_date)
      order by c.community,c.hcode,c.display_name,c.source_pid
      limit v_limit+1 offset v_offset
    ), classified as (
      select c.*,
        case
          when nullif(private.community_key(c.community),'') is null then 'unresolved'
          when c.volunteer_pid is null then 'staff_fallback'
          when not exists(select 1 from public.volunteers v where v.source_pid=c.volunteer_pid and v.active=true) then 'staff_fallback'
          when not exists(select 1 from public.profiles p where p.volunteer_pid=c.volunteer_pid and p.active=true and p.role in ('user','staff')) then 'staff_fallback'
          else 'assigned'
        end::text assignment_status,
        case
          when nullif(private.community_key(c.community),'') is null then 'missing_community'
          when c.volunteer_pid is null then 'no_volunteer'
          when not exists(select 1 from public.volunteers v where v.source_pid=c.volunteer_pid and v.active=true) then 'inactive_volunteer'
          when not exists(select 1 from public.profiles p where p.volunteer_pid=c.volunteer_pid and p.active=true and p.role in ('user','staff')) then 'no_active_user'
          else 'assigned'
        end::text assignment_reason
      from candidates c
    ), visible as (
      select x.*,
        case x.assignment_reason
          when 'missing_community' then 'เนเธกเนเธฃเธฐเธเธธเธเธธเธกเธเธ ยท เธชเนเธเนเธซเน Admin เธ•เธฃเธงเธเธชเธญเธ'
          when 'no_volunteer' then 'เธขเธฑเธเนเธกเนเธกเธต เธญเธชเธก.เธฃเธฑเธเธเธดเธ”เธเธญเธ ยท Staff เธ”เธนเนเธฅเธเธฑเนเธงเธเธฃเธฒเธง'
          when 'inactive_volunteer' then 'เธญเธชเธก.เน€เธ”เธดเธกเนเธกเนเธเธเธดเธเธฑเธ•เธดเธเธฒเธเนเธฅเนเธง ยท Staff เธ”เธนเนเธฅเธเธฑเนเธงเธเธฃเธฒเธง'
          when 'no_active_user' then 'เธกเธต เธญเธชเธก.เนเธ•เนเธขเธฑเธเนเธกเนเธกเธตเธเธฑเธเธเธตเนเธเนเธเธฒเธ ยท Staff เธ”เธนเนเธฅเธเธฑเนเธงเธเธฃเธฒเธง'
          else 'เธกเธตเธเธนเนเธฃเธฑเธเธเธดเธ”เธเธญเธ'
        end::text assignment_label
      from classified x
      order by community,hcode,display_name,source_pid
      limit v_limit
    )
    select jsonb_build_object(
      'version','2.0.54','source','health_screening_target_cache_v2030',
      'rows',coalesce((select jsonb_agg(to_jsonb(v) order by community,hcode,display_name,source_pid) from visible v),'[]'::jsonb),
      'offset',v_offset,'limit',v_limit,'has_more',(select count(*)>v_limit from candidates)
    ) into v_result;
    return v_result;
  end if;

  -- Less common staff/admin assignment filters keep the validated v2033 path.
  return public.health_worklist_assignment_json_v2033(
    v_scope,v_filter,v_stage,v_search,v_filter_community,v_assignment,
    v_owner,v_limit,v_offset
  );
end;
$$;

revoke all on function public.health_worklist_assignment_json_v2054(text,text,text,text,text,text,bigint,integer,integer) from public,anon;

grant execute on function public.health_worklist_assignment_json_v2054(text,text,text,text,text,text,bigint,integer,integer) to authenticated;

insert into public.app_settings(key,value)
values('cloud_performance_hardening_v2054',jsonb_build_object(
  'version','2.0.54',
  'scope','post_login_only',
  'auth_login_unchanged',true,
  'line_login_unchanged',true,
  'target_source','health_screening_target_cache_v2030',
  'user_fast_path_runtime_joins',0,
  'community_classify_after_pagination',true,
  'request_coordination','browser sharedCall + 30s stable cache',
  'jhcis_write_back',false
))
on conflict(key) do update set value=excluded.value,updated_at=now();

notify pgrst,'reload schema';

commit;
