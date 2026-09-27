CREATE OR REPLACE FUNCTION public.service_hcv_booking_report_v2087(p_event uuid, p_limit integer DEFAULT 100)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_slots jsonb; v_bookings jsonb;
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
      b.created_at,b.updated_at,b.status,
      hp.display_name, p.display_name as booked_by_name,
      d.hcv_selected,d.hbsag_selected,d.contact_phone,d.verification_status
   from public.cloud_event_bookings_v2085 b
   join private.hcv_booking_details_v2087 d on d.booking_id=b.id
   left join public.health_persons hp
     on hp.source_pcucode=b.source_pcucode and hp.source_pid=b.source_pid
   left join public.profiles p on p.user_id=b.booked_by
   where b.announcement_id=p_event
   order by b.created_at desc
   limit least(greatest(coalesce(p_limit,100),1),100)
 ) b;
 return jsonb_build_object('slots',v_slots,'bookings',v_bookings,
   'total_booked',(select count(*) from public.cloud_event_bookings_v2085 b
      where b.announcement_id=p_event and b.status='booked'),
   'limited_to',100);
end $function$
;
CREATE OR REPLACE FUNCTION public.service_health_event_report_v2085(p_event uuid, p_limit integer DEFAULT 100)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare totals jsonb; people jsonb;
begin
 if auth.role() is distinct from 'service_role' then raise exception 'เน€เธเธเธฒเธฐเธเธฃเธดเธเธฒเธฃเธ เธฒเธขเนเธ' using errcode='42501'; end if;
 if not exists(select 1 from public.cloud_announcements_v2083 a where a.id=p_event and a.kind='event') then
   raise exception 'เนเธกเนเธเธเธเธดเธเธเธฃเธฃเธก' using errcode='22023';
 end if;
 select coalesce(jsonb_agg(to_jsonb(t) order by t.starts_at),'[]'::jsonb) into totals
 from (select s.id,s.starts_at,s.ends_at,s.location,s.capacity,s.status,
  (select count(*) from public.cloud_event_bookings_v2085 b where b.slot_id=s.id and b.status='booked') as booked
 from public.cloud_event_slots_v2085 s where s.announcement_id=p_event) t;
 select coalesce(jsonb_agg(to_jsonb(x) order by x.created_at desc),'[]'::jsonb) into people
 from (select b.id,b.slot_id,b.status,b.created_at,hp.display_name,
 b.source_pcucode,b.source_pid
 from public.cloud_event_bookings_v2085 b
 left join public.health_persons hp on hp.source_pcucode=b.source_pcucode and hp.source_pid=b.source_pid
 where b.announcement_id=p_event order by b.created_at desc
 limit least(greatest(p_limit,1),100)) x;
 return jsonb_build_object('slots',totals,'bookings',people,
   'total_booked',(select count(*) from public.cloud_event_bookings_v2085 b where b.announcement_id=p_event and b.status='booked'),
   'limited_to',100);
end $function$
;
