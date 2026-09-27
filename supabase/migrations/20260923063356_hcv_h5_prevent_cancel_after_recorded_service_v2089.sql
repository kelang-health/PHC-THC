CREATE OR REPLACE FUNCTION public.cancel_hcv_hbsag_booking_v2087(p_booking uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
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
 if exists(select 1 from private.hcv_booking_details_v2087 d
    where d.booking_id=v_booking.id and (d.hcv_performed or d.hbsag_performed)) then
   raise exception 'เธฃเธฒเธขเธเธฒเธฃเธ—เธตเนเธเธฑเธเธ—เธถเธเธงเนเธฒเนเธ”เนเธฃเธฑเธเธเธฃเธดเธเธฒเธฃเนเธฅเนเธงเนเธกเนเธชเธฒเธกเธฒเธฃเธ–เธขเธเน€เธฅเธดเธเธเธฒเธฃเธเธญเธเนเธ”เน เธเธฃเธธเธ“เธฒเธ•เธดเธ”เธ•เนเธญเน€เธเนเธฒเธซเธเนเธฒเธ—เธตเน' using errcode='22023';
 end if;
 update public.cloud_event_bookings_v2085
 set status='cancelled',updated_at=now() where id=v_booking.id;
 return jsonb_build_object('status','cancelled','booking_id',v_booking.id);
end $function$
;
