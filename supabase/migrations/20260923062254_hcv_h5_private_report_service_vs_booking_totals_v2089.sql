create or replace function public.service_hcv_booking_report_v2087(
 p_event uuid,p_limit integer default 100
) returns jsonb language plpgsql security definer set search_path='' as $$
declare v_slots jsonb; v_bookings jsonb; v_totals jsonb;
begin
 if auth.role() is distinct from 'service_role' then
  raise exception 'เน€เธเธเธฒเธฐเธเธฃเธดเธเธฒเธฃเธ เธฒเธขเนเธ' using errcode='42501';
 end if;
 if not exists(select 1 from public.cloud_announcements_v2083 a
   where a.id=p_event and a.kind='event' and a.event_subtype='hcv_hbsag') then
  raise exception 'เนเธกเนเธเธเธเธดเธเธเธฃเธฃเธก HCV/HBsAg' using errcode='22023';
 end if;
 select coalesce(jsonb_agg(to_jsonb(s) order by s.starts_at),'[]'::jsonb)
 into v_slots
 from (
   select s.id,s.starts_at,s.ends_at,s.location,s.capacity,s.status,
     (select count(*) from public.cloud_event_bookings_v2085 b
       where b.slot_id=s.id and b.status='booked') as booked
   from public.cloud_event_slots_v2085 s
   where s.announcement_id=p_event
 ) s;
 select coalesce(jsonb_agg(to_jsonb(b) order by b.created_at desc),'[]'::jsonb)
 into v_bookings
 from (
   select b.id,b.slot_id,b.source_pcucode,b.source_pid,b.booked_by,
      b.created_at,b.updated_at,b.status,hp.display_name,
      p.display_name as booked_by_name,d.hcv_selected,d.hbsag_selected,
      d.contact_phone,d.verification_status,
      d.hcv_performed,d.hbsag_performed,d.reviewed_at,d.reviewed_by
   from public.cloud_event_bookings_v2085 b
   join private.hcv_booking_details_v2087 d on d.booking_id=b.id
   left join public.health_persons hp
     on hp.source_pcucode=b.source_pcucode and hp.source_pid=b.source_pid
   left join public.profiles p on p.user_id=b.booked_by
   where b.announcement_id=p_event
   order by b.created_at desc
   limit least(greatest(coalesce(p_limit,100),1),100)
 ) b;
 select jsonb_build_object(
   'total_booked',count(*) filter (where b.status='booked'),
   'anti_hcv_booked',count(*) filter (where b.status='booked' and d.hcv_selected),
   'hbsag_booked',count(*) filter (where b.status='booked' and d.hbsag_selected),
   'both_booked',count(*) filter (where b.status='booked' and d.hcv_selected and d.hbsag_selected),
   'pending_review',count(*) filter (where b.status='booked' and d.verification_status='pending_review'),
   'appointment_confirmed',count(*) filter (where b.status='booked' and d.verification_status='appointment_confirmed'),
   'needs_follow_up',count(*) filter (where b.status='booked' and d.verification_status='needs_follow_up'),
   'ineligible',count(*) filter (where b.status='booked' and d.verification_status='ineligible'),
   'anti_hcv_performed',count(*) filter (where b.status='booked' and d.hcv_performed),
   'hbsag_performed',count(*) filter (where b.status='booked' and d.hbsag_performed)
 ) into v_totals
 from public.cloud_event_bookings_v2085 b
 join private.hcv_booking_details_v2087 d on d.booking_id=b.id
 where b.announcement_id=p_event;
 return jsonb_build_object('slots',v_slots,'bookings',v_bookings,
   'total_booked',v_totals->'total_booked','totals',v_totals,'limited_to',100);
end $$;
revoke all on function public.service_hcv_booking_report_v2087(uuid,integer)
 from public,anon,authenticated;
grant execute on function public.service_hcv_booking_report_v2087(uuid,integer) to service_role;
