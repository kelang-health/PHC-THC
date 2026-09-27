-- H4: on-demand list of this User's own HCV bookings (never includes phone or clinical risk).
create index if not exists cloud_event_bookings_v2085_owner_active_idx
on public.cloud_event_bookings_v2085(booked_by,announcement_id,created_at desc)
where status='booked';
create or replace function public.list_my_hcv_bookings_v2088(p_event uuid)
returns table(booking_id uuid,display_name text,source_pcucode text,source_pid bigint,
slot_starts_at timestamptz,slot_location text,hcv_selected boolean,hbsag_selected boolean,
verification_status text)
language plpgsql security definer set search_path='' as $$
declare v_user uuid; v_pid bigint;
begin
 v_user:=auth.uid();
 select p.volunteer_pid into v_pid from public.profiles p
 where p.user_id=v_user and p.active is true and p.role='user';
 if v_user is null or not found or v_pid is null then
    raise exception 'เน€เธเธเธฒเธฐเธเธฑเธเธเธต เธญเธชเธก. เธ—เธตเนเธกเธตเธเนเธฒเธเธฃเธฑเธเธเธดเธ”เธเธญเธ' using errcode='42501';
 end if;
 if not exists(select 1 from public.cloud_announcements_v2083 a
   where a.id=p_event and a.kind='event' and a.event_subtype='hcv_hbsag'
     and a.audience='user' and a.status='published') then
    raise exception 'เนเธกเนเธเธเธเธดเธเธเธฃเธฃเธกเธ—เธตเนเน€เธเนเธฒเธ–เธถเธเนเธ”เน' using errcode='42501';
 end if;
 return query
 select b.id,hp.display_name,b.source_pcucode,b.source_pid,s.starts_at,s.location,
     d.hcv_selected,d.hbsag_selected,d.verification_status
 from public.cloud_event_bookings_v2085 b
 join private.hcv_booking_details_v2087 d on d.booking_id=b.id
 join public.health_persons hp on hp.source_pcucode=b.source_pcucode and hp.source_pid=b.source_pid
 join public.houses h on h.source_pcucode=hp.house_pcucode and h.hcode=hp.hcode
 join public.cloud_event_slots_v2085 s on s.id=b.slot_id
 where b.booked_by=v_user and b.announcement_id=p_event and b.status='booked'
 and hp.active is true and hp.service_population_eligible is true
 and h.superseded_by is null and h.verification_status='verified_jhcis'
 and h.volunteer_pid=v_pid and private.health_can_access_house(hp.house_pcucode,hp.hcode)
 order by b.created_at desc limit 20;
end $$;
revoke all on function public.list_my_hcv_bookings_v2088(uuid) from public,anon;
grant execute on function public.list_my_hcv_bookings_v2088(uuid) to authenticated;
