
create or replace function public.service_field_house_requesters_v2163(p_house_ids uuid[])
returns table(
  house_id uuid,
  requester_name text,
  requester_community text,
  requester_role text,
  requester_volunteer_pid bigint
)
language plpgsql
stable
security definer
set search_path=''
as $body$
begin
  if coalesce(auth.role(),'') <> 'service_role' then
    raise exception 'SERVICE_ROLE_REQUIRED';
  end if;
  if p_house_ids is null or coalesce(array_length(p_house_ids,1),0) = 0 then
    return;
  end if;
  if coalesce(array_length(p_house_ids,1),0) > 50 then
    raise exception 'HOUSE_ID_LIMIT_EXCEEDED';
  end if;

  return query
  select
    h.id,
    coalesce(nullif(btrim(p.display_name),''),'ไม่ระบุ')::text,
    coalesce(nullif(btrim(p.community),''),nullif(btrim(h.community),''),'ไม่ระบุ')::text,
    coalesce(nullif(btrim(p.role),''),'ไม่ระบุ')::text,
    coalesce(p.volunteer_pid,h.created_by_volunteer_pid)
  from public.houses h
  left join public.profiles p on p.user_id=h.created_by_user_id
  where h.id=any(p_house_ids)
    and h.entry_source='field'
    and h.superseded_by is null;
end;
$body$;

revoke all on function public.service_field_house_requesters_v2163(uuid[]) from public, anon, authenticated;
grant execute on function public.service_field_house_requesters_v2163(uuid[]) to service_role;
notify pgrst, 'reload schema';
