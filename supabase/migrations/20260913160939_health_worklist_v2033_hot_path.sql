-- Cloud v2.0.33 hot path: branch before row-to-JSON conversion.
-- This keeps field_targets on the denormalized cache and converts only the
-- requested page (<= 51 rows), avoiding a multi-megabyte temporary JSON set.
begin;

create or replace function public.health_worklist_assignment_json_v2033(
  p_scope text default 'self',p_filter text default 'field_targets',p_stage text default null,
  p_search text default null,p_community text default null,p_assignment text default 'all',
  p_owner_pid bigint default null,p_limit integer default 50,p_offset integer default 0
)
returns jsonb language plpgsql stable security definer set search_path=''
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

  if v_filter='field_targets' then
    with active_vhv as materialized(select distinct v.source_pid from public.volunteers v where v.active=true),
    active_ops as materialized(select distinct v.source_pid from public.volunteers v join public.profiles p on p.volunteer_pid=v.source_pid where v.active=true and p.active=true and p.role in ('user','staff')),
    base as(
      select c.*,
        case when nullif(private.community_key(c.community),'') is null then 'unresolved'
          when c.volunteer_pid is null or av.source_pid is null or ao.source_pid is null then 'staff_fallback' else 'assigned' end assignment_status,
        case when nullif(private.community_key(c.community),'') is null then 'missing_community'
          when c.volunteer_pid is null then 'no_volunteer' when av.source_pid is null then 'inactive_volunteer'
          when ao.source_pid is null then 'no_active_user' else 'assigned' end assignment_reason
      from public.health_screening_target_cache_v2030 c
      left join active_vhv av on av.source_pid=c.volunteer_pid left join active_ops ao on ao.source_pid=c.volunteer_pid
      where (v_role='admin' or (v_scope in ('self','volunteer') and v_owner is not null and c.volunteer_pid=v_owner)
        or (v_role='staff' and v_scope='community' and private.community_key(c.community)=private.community_key(v_community)))
        and (v_filter_community is null or private.community_key(c.community)=private.community_key(v_filter_community))
        and (v_stage is null or c.life_stage=v_stage) and (v_search='' or c.display_name ilike('%'||v_search||'%'))
    ), filtered as(
      select b.*,case when b.assignment_reason='missing_community' then 'เนเธกเนเธฃเธฐเธเธธเธเธธเธกเธเธ ยท เธชเนเธเนเธซเน Admin เธ•เธฃเธงเธเธชเธญเธ'
        when b.assignment_reason='no_volunteer' then 'เธขเธฑเธเนเธกเนเธกเธต เธญเธชเธก.เธฃเธฑเธเธเธดเธ”เธเธญเธ ยท Staff เธ”เธนเนเธฅเธเธฑเนเธงเธเธฃเธฒเธง'
        when b.assignment_reason='inactive_volunteer' then 'เธญเธชเธก.เน€เธ”เธดเธกเนเธกเนเธเธเธดเธเธฑเธ•เธดเธเธฒเธเนเธฅเนเธง ยท Staff เธ”เธนเนเธฅเธเธฑเนเธงเธเธฃเธฒเธง'
        when b.assignment_reason='no_active_user' then 'เธกเธต เธญเธชเธก.เนเธ•เนเธขเธฑเธเนเธกเนเธกเธตเธเธฑเธเธเธตเนเธเนเธเธฒเธ ยท Staff เธ”เธนเนเธฅเธเธฑเนเธงเธเธฃเธฒเธง'
        else 'เธกเธตเธเธนเนเธฃเธฑเธเธเธดเธ”เธเธญเธ' end assignment_label
      from base b where v_assignment='all' or b.assignment_status=v_assignment
    ), page as materialized(
      select * from filtered order by community,hcode,display_name,source_pid limit v_limit+1 offset v_offset
    ), visible as(select * from page order by community,hcode,display_name,source_pid limit v_limit)
    select jsonb_build_object('version','2.0.33','rows',coalesce((select jsonb_agg(to_jsonb(v) order by community,hcode,display_name,source_pid) from visible v),'[]'::jsonb),
      'offset',v_offset,'limit',v_limit,'has_more',(select count(*)>v_limit from page)) into v_result;
    return v_result;
  end if;

  with active_vhv as materialized(select distinct v.source_pid from public.volunteers v where v.active=true),
  active_ops as materialized(select distinct v.source_pid from public.volunteers v join public.profiles p on p.volunteer_pid=v.source_pid where v.active=true and p.active=true and p.role in ('user','staff')),
  base as(
    select w.*,
      case when nullif(private.community_key(w.community),'') is null then 'unresolved'
        when w.volunteer_pid is null or av.source_pid is null or ao.source_pid is null then 'staff_fallback' else 'assigned' end assignment_status,
      case when nullif(private.community_key(w.community),'') is null then 'missing_community'
        when w.volunteer_pid is null then 'no_volunteer' when av.source_pid is null then 'inactive_volunteer'
        when ao.source_pid is null then 'no_active_user' else 'assigned' end assignment_reason
    from public.health_person_worklist_active_v1847 w
    left join active_vhv av on av.source_pid=w.volunteer_pid left join active_ops ao on ao.source_pid=w.volunteer_pid
    where (v_role='admin' or (v_scope in ('self','volunteer') and v_owner is not null and w.volunteer_pid=v_owner)
      or (v_role='staff' and v_scope='community' and private.community_key(w.community)=private.community_key(v_community)))
      and (v_filter_community is null or private.community_key(w.community)=private.community_key(v_filter_community))
      and (v_stage is null or w.life_stage=v_stage) and (v_search='' or w.display_name ilike('%'||v_search||'%'))
      and (v_filter='all' or (v_filter='due' and coalesce(w.ncd_target,false) and not coalesce(w.screened_current_fy,false))
        or (v_filter='targets' and coalesce(w.ncd_target,false)) or (v_filter='known' and coalesce(w.known_ncd,false)))
  ), filtered as(
    select b.*,case when b.assignment_reason='missing_community' then 'เนเธกเนเธฃเธฐเธเธธเธเธธเธกเธเธ ยท เธชเนเธเนเธซเน Admin เธ•เธฃเธงเธเธชเธญเธ'
      when b.assignment_reason='no_volunteer' then 'เธขเธฑเธเนเธกเนเธกเธต เธญเธชเธก.เธฃเธฑเธเธเธดเธ”เธเธญเธ ยท Staff เธ”เธนเนเธฅเธเธฑเนเธงเธเธฃเธฒเธง'
      when b.assignment_reason='inactive_volunteer' then 'เธญเธชเธก.เน€เธ”เธดเธกเนเธกเนเธเธเธดเธเธฑเธ•เธดเธเธฒเธเนเธฅเนเธง ยท Staff เธ”เธนเนเธฅเธเธฑเนเธงเธเธฃเธฒเธง'
      when b.assignment_reason='no_active_user' then 'เธกเธต เธญเธชเธก.เนเธ•เนเธขเธฑเธเนเธกเนเธกเธตเธเธฑเธเธเธตเนเธเนเธเธฒเธ ยท Staff เธ”เธนเนเธฅเธเธฑเนเธงเธเธฃเธฒเธง'
      else 'เธกเธตเธเธนเนเธฃเธฑเธเธเธดเธ”เธเธญเธ' end assignment_label
    from base b where v_assignment='all' or b.assignment_status=v_assignment
  ), page as materialized(
    select * from filtered order by community,hcode,display_name,source_pid limit v_limit+1 offset v_offset
  ), visible as(select * from page order by community,hcode,display_name,source_pid limit v_limit)
  select jsonb_build_object('version','2.0.33','rows',coalesce((select jsonb_agg(to_jsonb(v) order by community,hcode,display_name,source_pid) from visible v),'[]'::jsonb),
    'offset',v_offset,'limit',v_limit,'has_more',(select count(*)>v_limit from page)) into v_result;
  return v_result;
end;
$$;

revoke all on function public.health_worklist_assignment_json_v2033(text,text,text,text,text,text,bigint,integer,integer) from public,anon;
grant execute on function public.health_worklist_assignment_json_v2033(text,text,text,text,text,text,bigint,integer,integer) to authenticated;
notify pgrst,'reload schema';
commit;
