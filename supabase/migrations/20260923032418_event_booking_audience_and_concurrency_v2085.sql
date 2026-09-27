create or replace function public.book_health_event_v2085(
 p_slot uuid,p_pcucode text,p_pid bigint
) returns jsonb language plpgsql security definer set search_path='' as $$
declare s public.cloud_event_slots_v2085%rowtype;
 a public.cloud_announcements_v2083%rowtype;
 existing uuid; fresh uuid; occupied integer;
 p_role text; p_community text;
begin
 if auth.uid() is null then raise exception 'เธเธฃเธธเธ“เธฒเน€เธเนเธฒเธชเธนเนเธฃเธฐเธเธ' using errcode='42501'; end if;
 if p_pid is null or p_pcucode is null or length(p_pcucode)>30 then
   raise exception 'เธเนเธญเธกเธนเธฅเธเธธเธเธเธฅเนเธกเนเธ–เธนเธเธ•เนเธญเธ' using errcode='22023'; end if;
 select p.role,p.community into p_role,p_community from public.profiles p
 where p.user_id=auth.uid() and p.active is true;
 if p_role is null then raise exception 'เธเธฑเธเธเธตเนเธกเนเธกเธตเธชเธดเธ—เธเธดเน' using errcode='42501'; end if;
 if not exists(select 1 from public.health_persons hp
   where hp.source_pcucode=p_pcucode and hp.source_pid=p_pid and hp.active is true
     and private.health_can_access_house(hp.house_pcucode,hp.hcode)) then
   raise exception 'เนเธกเนเธกเธตเธชเธดเธ—เธเธดเนเน€เธฅเธทเธญเธเธเธธเธเธเธฅเธเธตเน' using errcode='42501'; end if;
 select * into s from public.cloud_event_slots_v2085 where id=p_slot for update;
 if not found then raise exception 'เนเธกเนเธเธเธฃเธญเธเธเธดเธเธเธฃเธฃเธก' using errcode='22023'; end if;
 select * into a from public.cloud_announcements_v2083 where id=s.announcement_id;
 if a.status<>'published' or a.kind<>'event' or not a.booking_enabled
    or (a.audience<>'all' and a.audience<>p_role)
    or (a.target_community is not null and p_role<>'admin' and a.target_community<>p_community)
    or (a.starts_at is not null and a.starts_at>now())
    or (a.ends_at is not null and a.ends_at<now())
    or (a.booking_opens_at is not null and a.booking_opens_at>now())
    or (a.booking_closes_at is not null and a.booking_closes_at<now())
    or s.status<>'open' or s.starts_at<=now() then
   raise exception 'เธเธดเธเธเธฃเธฃเธกเธซเธฃเธทเธญเธฃเธญเธเธเธตเนเธเธดเธ”เธฃเธฑเธเธเธญเธเนเธฅเนเธงเธซเธฃเธทเธญเนเธกเนเธกเธตเธชเธดเธ—เธเธดเน' using errcode='22023'; end if;
 select b.id into existing from public.cloud_event_bookings_v2085 b
 where b.announcement_id=a.id and b.source_pcucode=p_pcucode and b.source_pid=p_pid and b.status='booked'
 limit 1;
 if existing is not null then return jsonb_build_object('status','already_booked','booking_id',existing); end if;
 select count(*) into occupied from public.cloud_event_bookings_v2085 b
 where b.slot_id=s.id and b.status='booked';
 if occupied>=s.capacity then raise exception 'เธฃเธญเธเธเธตเนเน€เธ•เนเธกเนเธฅเนเธง' using errcode='22023'; end if;
 begin
   insert into public.cloud_event_bookings_v2085(announcement_id,slot_id,source_pcucode,source_pid,booked_by)
   values(a.id,s.id,p_pcucode,p_pid,auth.uid()) returning id into fresh;
 exception when unique_violation then
   select b.id into existing from public.cloud_event_bookings_v2085 b
   where b.announcement_id=a.id and b.source_pcucode=p_pcucode and b.source_pid=p_pid and b.status='booked'
   limit 1;
   if existing is not null then return jsonb_build_object('status','already_booked','booking_id',existing); end if;
   raise;
 end;
 return jsonb_build_object('status','booked','booking_id',fresh,'remaining',s.capacity-occupied-1);
end $$;
revoke all on function public.book_health_event_v2085(uuid,text,bigint) from public,anon;
grant execute on function public.book_health_event_v2085(uuid,text,bigint) to authenticated;
