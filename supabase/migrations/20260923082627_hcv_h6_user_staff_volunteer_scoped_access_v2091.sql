DROP POLICY IF EXISTS cloud_announcements_v2083_reader ON public.cloud_announcements_v2083;
CREATE POLICY cloud_announcements_v2083_reader ON public.cloud_announcements_v2083 FOR SELECT TO authenticated
USING (status='published' AND (starts_at IS NULL OR starts_at<=now())
AND (ends_at IS NULL OR ends_at>=now())
AND EXISTS (SELECT 1 FROM public.profiles p WHERE p.user_id=auth.uid() AND p.active IS TRUE
 AND (cloud_announcements_v2083.audience='all'
      OR cloud_announcements_v2083.audience=p.role
      OR (cloud_announcements_v2083.event_subtype='hcv_hbsag'
          AND cloud_announcements_v2083.audience='user' AND p.role='staff'))
 AND (cloud_announcements_v2083.target_community IS NULL OR p.role='admin'
      OR cloud_announcements_v2083.target_community=p.community)));
CREATE OR REPLACE FUNCTION public.book_hcv_hbsag_event_v2087(p_slot uuid, p_pcucode text, p_pid bigint, p_hcv boolean, p_hbsag boolean, p_contact_phone text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare s public.cloud_event_slots_v2085%rowtype;
 a public.cloud_announcements_v2083%rowtype;
 v_user uuid; v_volunteer_pid bigint; v_community text;
 v_existing uuid; v_new uuid; v_occupied integer;
begin
 v_user:=auth.uid();
 if v_user is null then raise exception 'เธเธฃเธธเธ“เธฒเน€เธเนเธฒเธชเธนเนเธฃเธฐเธเธ' using errcode='42501'; end if;
 select p.volunteer_pid,p.community into v_volunteer_pid,v_community
 from public.profiles p
 where p.user_id=v_user and p.active is true and p.role in ('user','staff');
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
end $function$
;
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
 where p.user_id=v_user and p.active is true and p.role in ('user','staff');
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
CREATE OR REPLACE FUNCTION public.get_hcv_hbsag_booking_v2087(p_event uuid, p_pcucode text, p_pid bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_user uuid; v_volunteer_pid bigint;
 v_booking public.cloud_event_bookings_v2085%rowtype;
 v_detail private.hcv_booking_details_v2087%rowtype;
begin
 v_user:=auth.uid();
 select p.volunteer_pid into v_volunteer_pid from public.profiles p
 where p.user_id=v_user and p.active is true and p.role in ('user','staff');
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
end $function$
;
CREATE OR REPLACE FUNCTION public.list_my_hcv_bookings_v2088(p_event uuid)
 RETURNS TABLE(booking_id uuid, display_name text, source_pcucode text, source_pid bigint, slot_starts_at timestamp with time zone, slot_location text, hcv_selected boolean, hbsag_selected boolean, verification_status text)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_user uuid; v_pid bigint;
begin
 v_user:=auth.uid();
 select p.volunteer_pid into v_pid from public.profiles p
 where p.user_id=v_user and p.active is true and p.role in ('user','staff');
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
end $function$
;
CREATE OR REPLACE FUNCTION public.search_hcv_event_people_v2087(p_event uuid, p_query text, p_limit integer DEFAULT 20)
 RETURNS TABLE(source_pcucode text, source_pid bigint, display_name text, birth_date date, house_no text, community text)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_pid bigint; v_query text;
begin
 select p.volunteer_pid into v_pid from public.profiles p
 where p.user_id=auth.uid() and p.active is true and p.role in ('user','staff');
 if not found or v_pid is null then
   raise exception 'เน€เธเธเธฒเธฐเธเธฑเธเธเธต เธญเธชเธก. เธ—เธตเนเธกเธตเธเนเธฒเธเธฃเธฑเธเธเธดเธ”เธเธญเธ' using errcode='42501';
 end if;
 if not exists(select 1 from public.cloud_announcements_v2083 a
   where a.id=p_event and a.kind='event' and a.event_subtype='hcv_hbsag'
   and a.status='published' and a.audience='user'
   and (a.target_community is null or a.target_community =
      (select p.community from public.profiles p where p.user_id=auth.uid()))) then
   raise exception 'เนเธกเนเธกเธตเธชเธดเธ—เธเธดเนเน€เธเนเธฒเธ–เธถเธเธเธดเธเธเธฃเธฃเธก' using errcode='42501';
 end if;
 v_query:=trim(coalesce(p_query,''));
 if char_length(v_query)<2 or char_length(v_query)>70 then return; end if;
 return query
 select hp.source_pcucode,hp.source_pid,hp.display_name,hp.birth_date,h.house_no,h.community
 from public.health_persons hp join public.houses h
  on h.source_pcucode=hp.house_pcucode and h.hcode=hp.hcode
 where hp.active is true and hp.service_population_eligible is true
   and h.superseded_by is null and h.verification_status='verified_jhcis'
   and h.volunteer_pid=v_pid
   and private.health_can_access_house(hp.house_pcucode,hp.hcode)
   and hp.display_name ilike ('%'||replace(replace(replace(v_query,'\','\\'),'%','\%'),'_','\_')||'%') escape '\'
 order by hp.display_name,hp.source_pid
 limit least(greatest(coalesce(p_limit,20),1),20);
end $function$
;
