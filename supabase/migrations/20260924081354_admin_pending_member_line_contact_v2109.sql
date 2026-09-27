create or replace function public.admin_pending_member_requests_v2109()
returns table (
  id uuid, house_no text, community text, full_name text, birth_date date,
  masked_citizen_id text, status text, created_at timestamptz,
  requester_name text, requester_community text,
  requester_user_id uuid, requester_line_connected boolean
)
language plpgsql stable security definer set search_path = '' as $$
begin
  if auth.uid() is null or private.current_role() <> 'admin' then
    raise exception 'ADMIN_REQUIRED';
  end if;
  return query
    select q.id, q.house_no, q.community, q.full_name, q.birth_date,
      q.masked_citizen_id, q.status, q.created_at,
      coalesce(nullif(btrim(p.display_name), ''), 'เนเธกเนเธฃเธฐเธเธธ')::text,
      coalesce(nullif(btrim(p.community), ''), 'เนเธกเนเธฃเธฐเธเธธ')::text,
      case when p.active and exists (
        select 1 from public.user_line_links l
        where l.app_user_id = r.submitted_by and l.active = true
      ) then r.submitted_by else null end,
      (coalesce(p.active, false) and exists (
        select 1 from public.user_line_links l
        where l.app_user_id = r.submitted_by and l.active = true
      ))
    from public.admin_cancellable_member_requests_v2070() q
    join public.household_member_requests r on r.id = q.id
    left join public.profiles p on p.user_id = r.submitted_by
    where q.status = 'pending'
    order by q.created_at desc;
end;
$$;
revoke all on function public.admin_pending_member_requests_v2109() from public, anon;
grant execute on function public.admin_pending_member_requests_v2109() to authenticated;
notify pgrst, 'reload schema';
