-- H3: booking owner can view own contact details and cancel own HCV reservation.
create or replace function public.get_hcv_hbsag_booking_v2087(
 p_event uuid,p_pcucode text,p_pid bigint
) returns jsonb language plpgsql security definer set search_path='' as $$
declare v_user uuid; v_volunteer_pid bigint;
 v_booking public.cloud_event_bookings_v2085%rowtype;
 v_detail private.hcv_booking_details_v2087%rowtype;
begin
 v_user:=auth.uid();
 select p.volunteer_pid into v_volunteer_pid from public.profiles p
 where p.user_id=v_user and p.active is true and p.role='user';
 if v_user is null or not found or v_volunteer_pid is null then
   raise exception 'เน€เธเธเธฒเธฐเธเธฑเธเธเธต เธญเธชเธก. เธ—เธตเนเนเธ”เนเธฃเธฑเธเธกเธญเธเธซเธกเธฒเธข' using errcode='42501';
 end if;
 if not exists(
   select 1 from public.health_persons hp
   join public.houses h on h.source_pcucode=hp.house_pcucode and h.hcode=hp.hcode
   where hp.source_pcucode=p_pcucode and hp.source_pid=p_pid and hp.active is true
     and hp.service_population_eligible is true
     and h.superseded_by is null and h.verification_status='verified_jhcis'
     and h.volunteer_pid=v_volunteer_pid
     and private.health_can_access_house(hp.house_pcucode,hp.hcode)
 ) then raise exception 'เนเธกเนเธกเธตเธชเธดเธ—เธเธดเนเน€เธเนเธฒเธ–เธถเธเธเธธเธเธเธฅเธเธตเน' using errcode='42501'; end if;
 if not exists(select 1 from public.cloud_announcements_v2083 a
  where a.id=p_event and a.event_subtype='hcv_hbsag'
  and a.audience='user') then
   raise exception 'เนเธกเนเธเธเธเธดเธเธเธฃเธฃเธก HCV/HBsAg' using errcode='22023';
 end if;
 select * into v_booking from public.cloud_event_bookings_v2085 b
 where b.announcement_id=p_event and b.source_pcucode=p_pcucode
   and b.source_pid=p_pid and b.status='booked' limit 1;
 if not found then return jsonb_build_object('status','not_booked'); end if;
 if v_booking.booked_by<>v_user then
   return jsonb_build_object('status','already_booked');
 end if;
 select * into v_detail from private.hcv_booking_details_v2087 d
 where d.booking_id=v_booking.id;
 if not found then
   raise exception 'เนเธกเนเธเธเธฃเธฒเธขเธฅเธฐเน€เธญเธตเธขเธ”เธเธฒเธฃเธเธญเธเธเธตเน' using errcode='22023';
 end if;
 return jsonb_build_object('status','booked','booking_id',v_booking.id,
  'slot_id',v_booking.slot_id,'booked_at',v_booking.created_at,
  'hcv_selected',v_detail.hcv_selected,'hbsag_selected',v_detail.hbsag_selected,
  'contact_phone',v_detail.contact_phone,
  'verification_status',v_detail.verification_status);
end $$;
revoke all on function public.get_hcv_hbsag_booking_v2087(uuid,text,bigint) from public,anon;
grant execute on function public.get_hcv_hbsag_booking_v2087(uuid,text,bigint) to authenticated;

create or replace function public.cancel_hcv_hbsag_booking_v2087(p_booking uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_user uuid; v_volunteer_pid bigint;
 v_booking public.cloud_event_bookings_v2085%rowtype;
begin
 v_user:=auth.uid();
 select p.volunteer_pid into v_volunteer_pid from public.profiles p
 where p.user_id=v_user and p.active is true and p.role='user';
 if v_user is null or not found or v_volunteer_pid is null then
   raise exception 'เน€เธเธเธฒเธฐเธเธฑเธเธเธต เธญเธชเธก. เธ—เธตเนเนเธ”เนเธฃเธฑเธเธกเธญเธเธซเธกเธฒเธข' using errcode='42501';
 end if;
 select * into v_booking from public.cloud_event_bookings_v2085 b
 where b.id=p_booking for update;
 if not found then raise exception 'เนเธกเนเธเธเธเธฒเธฃเธเธญเธ' using errcode='22023'; end if;
 if v_booking.booked_by<>v_user or not exists (
   select 1 from public.cloud_announcements_v2083 a
   where a.id=v_booking.announcement_id and a.event_subtype='hcv_hbsag'
 ) or not exists(
   select 1 from public.health_persons hp
   join public.houses h on h.source_pcucode=hp.house_pcucode and h.hcode=hp.hcode
   where hp.source_pcucode=v_booking.source_pcucode
     and hp.source_pid=v_booking.source_pid and hp.active is true
     and h.superseded_by is null and h.verification_status='verified_jhcis'
     and h.volunteer_pid=v_volunteer_pid
     and private.health_can_access_house(hp.house_pcucode,hp.hcode)
 ) then raise exception 'เนเธกเนเธกเธตเธชเธดเธ—เธเธดเนเธขเธเน€เธฅเธดเธเธเธฒเธฃเธเธญเธเธเธตเน' using errcode='42501'; end if;
 if v_booking.status='cancelled' then
   return jsonb_build_object('status','already_cancelled','booking_id',v_booking.id);
 end if;
 update public.cloud_event_bookings_v2085
 set status='cancelled',updated_at=now() where id=v_booking.id;
 return jsonb_build_object('status','cancelled','booking_id',v_booking.id);
end $$;
revoke all on function public.cancel_hcv_hbsag_booking_v2087(uuid) from public,anon;
grant execute on function public.cancel_hcv_hbsag_booking_v2087(uuid) to authenticated;
