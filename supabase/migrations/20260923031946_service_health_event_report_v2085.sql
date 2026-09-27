create or replace function public.service_health_event_report_v2085(p_event uuid,p_limit integer default 100)
returns jsonb language plpgsql security definer set search_path='' as $$
declare totals jsonb; people jsonb;
begin
 if auth.role()<>'service_role' then raise exception 'เน€เธเธเธฒเธฐเธเธฃเธดเธเธฒเธฃเธ เธฒเธขเนเธ' using errcode='42501'; end if;
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
end $$;
revoke all on function public.service_health_event_report_v2085(uuid,integer) from public,anon,authenticated;
grant execute on function public.service_health_event_report_v2085(uuid,integer) to service_role;
