create or replace function public.service_hcv_booking_review_v2089(
 p_event uuid,p_booking uuid,p_status text,
 p_hcv_performed boolean,p_hbsag_performed boolean,p_actor text
) returns jsonb language plpgsql security definer set search_path='' as $$
declare b public.cloud_event_bookings_v2085%rowtype;
 d private.hcv_booking_details_v2087%rowtype;
 v_actor text;
begin
 if auth.role() is distinct from 'service_role' then
   raise exception 'เน€เธเธเธฒเธฐเธเธฃเธดเธเธฒเธฃเน€เธเนเธฒเธซเธเนเธฒเธ—เธตเนเธ เธฒเธขเนเธ' using errcode='42501';
 end if;
 v_actor:=trim(coalesce(p_actor,''));
 if char_length(v_actor)<1 or char_length(v_actor)>100 then
   raise exception 'เธเธนเนเธเธฑเธเธ—เธถเธเนเธกเนเธ–เธนเธเธ•เนเธญเธ' using errcode='22023';
 end if;
 if p_status not in ('pending_review','appointment_confirmed','needs_follow_up','ineligible')
    or p_status is null or p_hcv_performed is null or p_hbsag_performed is null then
   raise exception 'เธชเธ–เธฒเธเธฐเธเธฒเธฃเธ•เธฃเธงเธเธชเธญเธเนเธกเนเธ–เธนเธเธ•เนเธญเธ' using errcode='22023';
 end if;
 select * into b from public.cloud_event_bookings_v2085
   where id=p_booking and announcement_id=p_event for update;
 if not found or b.status<>'booked' then
   raise exception 'เนเธกเนเธเธเธเธฒเธฃเธเธญเธเธ—เธตเนเธขเธฑเธเนเธเนเธเธฒเธเธญเธขเธนเน' using errcode='22023';
 end if;
 if not exists(select 1 from public.cloud_announcements_v2083 a
   where a.id=p_event and a.kind='event' and a.event_subtype='hcv_hbsag') then
   raise exception 'เนเธกเนเธเธเธเธดเธเธเธฃเธฃเธก HCV/HBsAg' using errcode='22023';
 end if;
 select * into d from private.hcv_booking_details_v2087
 where booking_id=p_booking for update;
 if not found then raise exception 'เนเธกเนเธเธเธเนเธญเธกเธนเธฅเธฃเธฒเธขเธเธฒเธฃเธ•เธฃเธงเธ' using errcode='22023'; end if;
 if (p_hcv_performed and not d.hcv_selected) or
    (p_hbsag_performed and not d.hbsag_selected) then
   raise exception 'เนเธกเนเธชเธฒเธกเธฒเธฃเธ–เธเธฑเธเธ—เธถเธเธงเนเธฒเนเธ”เนเธฃเธฑเธเธเธฃเธดเธเธฒเธฃเธ—เธตเนเนเธกเนเนเธ”เนเน€เธฅเธทเธญเธ' using errcode='22023';
 end if;
 if (p_hcv_performed or p_hbsag_performed) and p_status<>'appointment_confirmed' then
   raise exception 'เธเธฒเธฃเธเธฑเธเธ—เธถเธเธงเนเธฒเนเธ”เนเธฃเธฑเธเธเธฃเธดเธเธฒเธฃเธเธฃเธดเธเธ•เนเธญเธเธเนเธฒเธเธเธฒเธฃเธขเธทเธเธขเธฑเธเธเธฑเธ”เธเนเธญเธ' using errcode='22023';
 end if;
 if d.verification_status=p_status and d.hcv_performed=p_hcv_performed
    and d.hbsag_performed=p_hbsag_performed then
   return jsonb_build_object('ok',true,'unchanged',true,'booking_id',p_booking,
     'verification_status',p_status,'hcv_performed',d.hcv_performed,
     'hbsag_performed',d.hbsag_performed);
 end if;
 update private.hcv_booking_details_v2087
 set verification_status=p_status,hcv_performed=p_hcv_performed,
     hbsag_performed=p_hbsag_performed,reviewed_by=v_actor,
     reviewed_at=now(),updated_at=now()
 where booking_id=p_booking;
 insert into private.hcv_booking_review_audit_v2089(
   booking_id,actor,previous_status,new_status,
   previous_hcv_performed,new_hcv_performed,
   previous_hbsag_performed,new_hbsag_performed)
 values(p_booking,v_actor,d.verification_status,p_status,
   d.hcv_performed,p_hcv_performed,d.hbsag_performed,p_hbsag_performed);
 return jsonb_build_object('ok',true,'unchanged',false,'booking_id',p_booking,
   'verification_status',p_status,'hcv_performed',p_hcv_performed,
   'hbsag_performed',p_hbsag_performed);
end $$;
revoke all on function public.service_hcv_booking_review_v2089(uuid,uuid,text,boolean,boolean,text)
 from public,anon,authenticated;
grant execute on function public.service_hcv_booking_review_v2089(uuid,uuid,text,boolean,boolean,text)
 to service_role;
