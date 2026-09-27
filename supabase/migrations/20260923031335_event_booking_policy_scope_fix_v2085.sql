drop policy if exists cloud_event_bookings_v2085_reader on public.cloud_event_bookings_v2085;
create policy cloud_event_bookings_v2085_reader on public.cloud_event_bookings_v2085
for select to authenticated using (
 exists(select 1 from public.profiles p where p.user_id=(select auth.uid()) and p.active is true)
 and exists(select 1 from public.health_persons hp
   where hp.source_pcucode=cloud_event_bookings_v2085.source_pcucode
     and hp.source_pid=cloud_event_bookings_v2085.source_pid
     and hp.active is true
     and private.health_can_access_house(hp.house_pcucode,hp.hcode))
);
