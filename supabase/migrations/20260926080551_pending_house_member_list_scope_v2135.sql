-- v2.1.35: keep pending-house member reads aligned with the submission scope.
-- A field submitter can add a member request to their own pending house, so the
-- same submitter must be able to read the request back while JHCIS verifies it.

create or replace function public.household_member_requests_v2043(p_house_id uuid)
returns table(
  id uuid,
  full_name text,
  birth_date date,
  masked_citizen_id text,
  linked_person_id bigint,
  display_identifier text,
  status text,
  review_note text,
  linked boolean,
  created_at timestamptz,
  updated_at timestamptz
)
language plpgsql
stable
security definer
set search_path=''
as $$
begin
  if auth.uid() is null or not private.can_submit_member_request_v2050(p_house_id) then
    raise exception 'HOUSE_OUT_OF_SCOPE';
  end if;

  return query
  select r.id,
         r.full_name,
         r.birth_date,
         'โ€ขโ€ขโ€ขโ€ขโ€ขโ€ขโ€ขโ€ขโ€ข'||r.citizen_id_last4,
         r.linked_person_id,
         case when r.linked_person_id is not null
              then 'PID '||r.linked_person_id::text
              else 'โ€ขโ€ขโ€ขโ€ขโ€ขโ€ขโ€ขโ€ขโ€ข'||r.citizen_id_last4 end,
         r.status,
         case when r.status='needs_correction' then r.review_note else '' end,
         r.linked_person_id is not null,
         r.created_at,
         r.updated_at
  from public.household_member_requests r
  where r.house_id=p_house_id
  order by r.created_at desc;
end;
$$;

revoke all on function public.household_member_requests_v2043(uuid) from public, anon, authenticated;
grant execute on function public.household_member_requests_v2043(uuid) to authenticated;
