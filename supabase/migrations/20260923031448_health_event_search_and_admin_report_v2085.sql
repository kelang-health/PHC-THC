create or replace function public.search_event_people_v2085(p_query text,p_limit integer default 20)
returns table(source_pcucode text,source_pid bigint,display_name text,house_no text,community text)
language plpgsql security definer set search_path='' as $$
declare q text;
begin
 if auth.uid() is null or not exists(select 1 from public.profiles p where p.user_id=auth.uid() and p.active is true) then
    raise exception 'เธเธฃเธธเธ“เธฒเน€เธเนเธฒเธชเธนเนเธฃเธฐเธเธ' using errcode='42501';
 end if;
 q:=trim(coalesce(p_query,''));
 if char_length(q)<2 or char_length(q)>70 then return; end if;
 return query select hp.source_pcucode,hp.source_pid,hp.display_name,h.house_no,h.community
 from public.health_persons hp
 join public.houses h on h.source_pcucode=hp.house_pcucode and h.hcode=hp.hcode
 where hp.active is true and h.superseded_by is null and h.verification_status='verified_jhcis'
 and hp.display_name ilike ('%'||replace(replace(replace(q,'\','\\'),'%','\%'),'_','\_')||'%') escape '\'
 and private.health_can_access_house(hp.house_pcucode,hp.hcode)
 order by hp.display_name,hp.source_pid limit least(greatest(p_limit,1),30);
end $$;
revoke all on function public.search_event_people_v2085(text,integer) from public,anon;
grant execute on function public.search_event_people_v2085(text,integer) to authenticated;

create or replace function public.health_event_admin_report_v2085(p_event uuid,p_limit integer default 100)
returns jsonb language plpgsql security definer set search_path='' as $$
declare p public.profiles%rowtype; totals jsonb; people jsonb;
begin
 select * into p from public.profiles where user_id=auth.uid() and active is true;
 if not found or p.role <> 'admin' then
  raise exception 'เน€เธเธเธฒเธฐเธเธนเนเธ”เธนเนเธฅเธฃเธฐเธเธ' using errcode='42501';
 end if;
 if not exists(select 1 from public.cloud_announcements_v2083 a where a.id=p_event and a.kind='event') then
  raise exception 'เนเธกเนเธเธเธเธดเธเธเธฃเธฃเธก' using errcode='22023';
 end if;
 select coalesce(jsonb_agg(to_jsonb(t) order by t.starts_at), '[]'::jsonb) into totals
 from (select s.id,s.starts_at,s.ends_at,s.location,s.capacity,s.status,
   (select count(*) from public.cloud_event_bookings_v2085 b
    where b.slot_id=s.id and b.status='booked') as booked
   from public.cloud_event_slots_v2085 s where s.announcement_id=p_event) t;
 select coalesce(jsonb_agg(to_jsonb(x) order by x.created_at), '[]'::jsonb) into people
 from (select b.id,b.slot_id,b.status,b.created_at,hp.display_name,
    hp.source_pcucode,hp.source_pid,h.house_no,h.community
    from public.cloud_event_bookings_v2085 b
    join public.health_persons hp on hp.source_pcucode=b.source_pcucode and hp.source_pid=b.source_pid
    left join public.houses h on h.source_pcucode=hp.house_pcucode and h.hcode=hp.hcode and h.superseded_by is null
    where b.announcement_id=p_event
    order by b.created_at desc
    limit least(greatest(p_limit,1),100)) x;
 return jsonb_build_object('slots',totals,'bookings',people,
   'total_booked',(select count(*) from public.cloud_event_bookings_v2085 b where b.announcement_id=p_event and b.status='booked'));
end $$;
revoke all on function public.health_event_admin_report_v2085(uuid,integer) from public,anon;
grant execute on function public.health_event_admin_report_v2085(uuid,integer) to authenticated;
