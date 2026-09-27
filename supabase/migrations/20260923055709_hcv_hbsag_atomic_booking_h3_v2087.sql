-- H3: atomic reservation; one active booking per person/event, one slot even if both tests selected.
create or replace function public.book_hcv_hbsag_event_v2087(
 p_slot uuid,p_pcucode text,p_pid bigint,
 p_hcv boolean,p_hbsag boolean,p_contact_phone text
) returns jsonb language plpgsql security definer set search_path='' as $$
declare s public.cloud_event_slots_v2085%rowtype;
 a public.cloud_announcements_v2083%rowtype;
 v_user uuid; v_volunteer_pid bigint; v_community text;
 v_existing uuid; v_new uuid; v_occupied integer;
begin
 v_user:=auth.uid();
 if v_user is null then raise exception 'เธเธฃเธธเธ“เธฒเน€เธเนเธฒเธชเธนเนเธฃเธฐเธเธ' using errcode='42501'; end if;
 select p.volunteer_pid,p.community into v_volunteer_pid,v_community
 from public.profiles p
 where p.user_id=v_user and p.active is true and p.role='user';
 if not found or v_volunteer_pid is null then
   raise exception 'เน€เธเธเธฒเธฐเธเธฑเธเธเธต เธญเธชเธก. เธ—เธตเนเธกเธตเธเนเธฒเธเธฃเธฑเธเธเธดเธ”เธเธญเธ' using errcode='42501';
 end if;
 if p_pcucode is null or char_length(p_pcucode)>30 or p_pid is null or p_pid<=0 then
   raise exception 'เธฃเธซเธฑเธชเธเธธเธเธเธฅเนเธกเนเธ–เธนเธเธ•เนเธญเธ' using errcode='22023';
 end if;
 if p_hcv is not true and p_hbsag is not true then
   raise exception 'เธเธฃเธธเธ“เธฒเน€เธฅเธทเธญเธเธฃเธฒเธขเธเธฒเธฃเธ•เธฃเธงเธเธญเธขเนเธฒเธเธเนเธญเธขเธซเธเธถเนเธเธฃเธฒเธขเธเธฒเธฃ' using errcode='22023';
 end if;
 if p_contact_phone is null or p_contact_phone !~ '^0[0-9]{8,9}$' then
   raise exception 'เน€เธเธญเธฃเนเนเธ—เธฃเธชเธณเธซเธฃเธฑเธเธ•เธดเธ”เธ•เนเธญเนเธกเนเธ–เธนเธเธ•เนเธญเธ' using errcode='22023';
 end if;
 if not exists(
  select 1 from public.health_persons hp
  join public.houses h on h.source_pcucode=hp.house_pcucode and h.hcode=hp.hcode
  where hp.source_pcucode=p_pcucode and hp.source_pid=p_pid
    and hp.active is true and hp.service_population_eligible is true
    and h.superseded_by is null and h.verification_status='verified_jhcis'
    and h.volunteer_pid=v_volunteer_pid
    and private.health_can_access_house(hp.house_pcucode,hp.hcode)
 ) then raise exception 'เธเธธเธเธเธฅเธเธตเนเนเธกเนเธญเธขเธนเนเนเธเธเธงเธฒเธกเธฃเธฑเธเธเธดเธ”เธเธญเธ' using errcode='42501'; end if;
 select * into s from public.cloud_event_slots_v2085 where id=p_slot for update;
 if not found then raise exception 'เนเธกเนเธเธเธฃเธญเธเธเธฃเธดเธเธฒเธฃ' using errcode='22023'; end if;
 select * into a from public.cloud_announcements_v2083
 where id=s.announcement_id for share;
 if not found or a.kind<>'event' or a.event_subtype<>'hcv_hbsag'
     or a.status<>'published' or a.audience<>'user' or not a.booking_enabled
     or (a.target_community is not null and a.target_community<>v_community)
     or (p_hcv is true and not a.hcv_enabled)
     or (p_hbsag is true and not a.hbsag_enabled)
     or (a.starts_at is not null and a.starts_at>now())
     or (a.ends_at is not null and a.ends_at<now())
     or (a.booking_opens_at is not null and a.booking_opens_at>now())
     or (a.booking_closes_at is not null and a.booking_closes_at<now())
     or s.status<>'open' or s.starts_at<=now() then
    raise exception 'เธเธดเธเธเธฃเธฃเธกเธซเธฃเธทเธญเธฃเธญเธเธเธตเนเธขเธฑเธเนเธกเนเน€เธเธดเธ”เธฃเธฑเธเธเธญเธเธซเธฃเธทเธญเนเธกเนเธกเธตเธชเธดเธ—เธเธดเน' using errcode='22023';
 end if;
 select b.id into v_existing from public.cloud_event_bookings_v2085 b
 where b.announcement_id=a.id and b.source_pcucode=p_pcucode
   and b.source_pid=p_pid and b.status='booked'
 limit 1;
 if v_existing is not null then
    return jsonb_build_object('status','already_booked','booking_id',v_existing);
 end if;
 select count(*) into v_occupied from public.cloud_event_bookings_v2085 b
 where b.slot_id=s.id and b.status='booked';
 if v_occupied>=s.capacity then
    raise exception 'เธฃเธญเธเธเธตเนเน€เธ•เนเธกเนเธฅเนเธง' using errcode='22023';
 end if;
 begin
   insert into public.cloud_event_bookings_v2085(
     announcement_id,slot_id,source_pcucode,source_pid,booked_by)
   values(a.id,s.id,p_pcucode,p_pid,v_user) returning id into v_new;
 exception when unique_violation then
   select b.id into v_existing from public.cloud_event_bookings_v2085 b
   where b.announcement_id=a.id and b.source_pcucode=p_pcucode
     and b.source_pid=p_pid and b.status='booked' limit 1;
   if v_existing is not null then
     return jsonb_build_object('status','already_booked','booking_id',v_existing);
   end if;
   raise;
 end;
 insert into private.hcv_booking_details_v2087(
   booking_id,hcv_selected,hbsag_selected,contact_phone,verification_status)
 values(v_new,p_hcv is true,p_hbsag is true,p_contact_phone,'pending_review');
 return jsonb_build_object('status','booked','booking_id',v_new,
   'remaining',s.capacity-v_occupied-1,'verification_status','pending_review');
end $$;
revoke all on function public.book_hcv_hbsag_event_v2087(uuid,text,bigint,boolean,boolean,text)
 from public,anon;
grant execute on function public.book_hcv_hbsag_event_v2087(uuid,text,bigint,boolean,boolean,text)
 to authenticated;
