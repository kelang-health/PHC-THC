-- OSM-PHC Cloud v2.0.5
-- Expose the signed-in user's appointment response in the existing LINE status RPC.
begin;

create or replace function public.my_line_status_v190()
returns jsonb
language plpgsql stable security definer
set search_path=''
as $$
declare
  v_connected boolean;
  v_linked_at timestamptz;
  v_next public.appointments%rowtype;
  v_response text;
begin
  if auth.uid() is null then raise exception 'AUTH_REQUIRED'; end if;

  select exists(
           select 1 from public.user_line_links
           where app_user_id=auth.uid() and active=true
         ),
         (select linked_at from public.user_line_links
          where app_user_id=auth.uid() and active=true limit 1)
    into v_connected,v_linked_at;

  select * into v_next
  from public.appointments
  where app_user_id=auth.uid()
    and status='scheduled'
    and appointment_at>=now()
  order by appointment_at
  limit 1;

  if v_next.id is not null then
    select ar.response into v_response
    from public.appointment_responses ar
    where ar.appointment_id=v_next.id and ar.app_user_id=auth.uid();
  end if;

  return jsonb_build_object(
    'connected',coalesce(v_connected,false),
    'linked_at',v_linked_at,
    'next_appointment',case when v_next.id is null then null else jsonb_build_object(
      'id',v_next.id,
      'title',v_next.title,
      'appointment_at',v_next.appointment_at,
      'location',v_next.location_text,
      'response',v_response
    ) end
  );
end;
$$;

revoke all on function public.my_line_status_v190() from public,anon;

grant execute on function public.my_line_status_v190() to authenticated;

commit;
