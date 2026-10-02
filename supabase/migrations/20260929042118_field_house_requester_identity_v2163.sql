
create or replace function public.admin_cancellable_field_houses_v2163()
returns table(
  id uuid, house_no text, house_id_11 text, moo text, community text,
  verification_status text, created_at timestamptz, open_member_requests bigint,
  requester_name text, requester_community text, requester_role text,
  requester_volunteer_pid bigint
)
language plpgsql stable security definer set search_path = ''
as $body$
begin
  if auth.uid() is null or private.current_role() <> 'admin' then
    raise exception 'ADMIN_REQUIRED';
  end if;

  return query
    select h.id, h.house_no, h.house_id_11, h.moo, h.community, h.verification_status,
      coalesce(h.field_created_at, h.updated_at),
      (select count(*) from public.household_member_requests r
        where r.house_id = h.id and (r.status <> 'rejected' or r.linked_person_id is not null)),
      coalesce(nullif(btrim(p.display_name), ''), 'ไม่ระบุ')::text,
      coalesce(nullif(btrim(p.community), ''), nullif(btrim(h.community), ''), 'ไม่ระบุ')::text,
      coalesce(nullif(btrim(p.role), ''), 'ไม่ระบุ')::text,
      coalesce(p.volunteer_pid, h.created_by_volunteer_pid)
    from public.houses h
    left join public.profiles p on p.user_id = h.created_by_user_id
    where h.entry_source = 'field' and h.superseded_by is null
      and h.verification_status in ('pending_jhcis_create','pending_jhcis_update','review_required')
    order by coalesce(h.field_created_at, h.updated_at) desc
    limit 100;
end;
$body$;

revoke all on function public.admin_cancellable_field_houses_v2163() from public, anon, authenticated;
grant execute on function public.admin_cancellable_field_houses_v2163() to authenticated;
notify pgrst, 'reload schema';
