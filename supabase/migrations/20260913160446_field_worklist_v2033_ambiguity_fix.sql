-- Cloud v2.0.33 hotfix: qualify source_pid inside a RETURNS TABLE function.
begin;

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
  with active_vhv as materialized(select distinct v.source_pid from public.volunteers v where v.active=true),
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
notify pgrst,'reload schema';
commit;
