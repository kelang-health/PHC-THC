CREATE OR REPLACE FUNCTION public.book_hcv_demo_real_v2094(p_event uuid, p_pcucode text, p_pid bigint, p_slot text, p_hcv boolean, p_hbsag boolean)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
 DECLARE a public.cloud_announcements_v2083%rowtype;
         user_id uuid; vhv bigint; community text; v_existing uuid;
         cap integer; occupied integer; booking uuid;
 BEGIN
  user_id:=auth.uid();
  SELECT p.volunteer_pid,p.community INTO vhv,community
    FROM public.profiles p
    WHERE p.user_id=user_id AND p.active AND p.role IN ('user','staff');
  IF user_id IS NULL OR NOT FOUND OR vhv IS NULL THEN
    RAISE EXCEPTION 'เน€เธเธเธฒเธฐเธเธฑเธเธเธต เธญเธชเธก. User/Staff เธ—เธตเนเนเธ”เนเธฃเธฑเธเธกเธญเธเธซเธกเธฒเธข' USING ERRCODE='42501';
  END IF;
  IF p_pcucode IS NULL OR length(p_pcucode)>30 OR p_pid IS NULL OR p_pid<=0
     OR p_slot NOT IN ('A','B') OR p_slot IS NULL
     OR (p_hcv IS NOT TRUE AND p_hbsag IS NOT TRUE) THEN
    RAISE EXCEPTION 'เธเนเธญเธกเธนเธฅเธ—เธ”เธชเธญเธเนเธกเนเธ–เธนเธเธ•เนเธญเธ' USING ERRCODE='22023';
  END IF;
  SELECT * INTO a FROM public.cloud_announcements_v2083
   WHERE id=p_event FOR UPDATE;
  IF NOT FOUND OR NOT a.is_demo OR a.event_subtype<>'hcv_hbsag'
   OR a.status<>'published' OR a.booking_enabled IS DISTINCT FROM false OR a.demo_real_data_enabled IS DISTINCT FROM true
   OR a.audience<>'user'
   OR (a.starts_at IS NOT NULL AND a.starts_at>now())
   OR (a.ends_at IS NOT NULL AND a.ends_at<now())
   OR (a.target_community IS NOT NULL AND a.target_community<>community)
   OR (p_hcv IS TRUE AND NOT a.hcv_enabled)
   OR (p_hbsag IS TRUE AND NOT a.hbsag_enabled) THEN
   RAISE EXCEPTION 'เธเธดเธเธเธฃเธฃเธกเธเธตเนเนเธกเนเธญเธขเธนเนเนเธเนเธซเธกเธ”เธ—เธ”เธชเธญเธเธ—เธตเนเน€เธเธดเธ”เนเธเนเธเธฒเธ' USING ERRCODE='22023';
  END IF;
  IF NOT EXISTS(
    SELECT 1 FROM public.health_persons hp
    JOIN public.houses h ON h.source_pcucode=hp.house_pcucode AND h.hcode=hp.hcode
    WHERE hp.source_pcucode=p_pcucode AND hp.source_pid=p_pid
    AND hp.active AND hp.service_population_eligible
    AND h.superseded_by IS NULL AND h.verification_status='verified_jhcis'
    AND h.volunteer_pid=vhv
    AND private.health_can_access_house(hp.house_pcucode,hp.hcode)
  ) THEN RAISE EXCEPTION 'เธเธธเธเธเธฅเนเธกเนเธญเธขเธนเนเนเธเธเนเธฒเธเธ—เธตเนเธ—เนเธฒเธเธฃเธฑเธเธเธดเธ”เธเธญเธ' USING ERRCODE='42501';END IF;
  SELECT b.id INTO v_existing FROM private.hcv_demo_bookings_v2094 b
   WHERE b.event_id=p_event AND b.source_pcucode=p_pcucode AND b.source_pid=p_pid
     AND b.status='booked' LIMIT 1;
  IF v_existing IS NOT NULL THEN
   RETURN jsonb_build_object('status','already_booked','booking_id',v_existing,'is_demo',true);
  END IF;
  cap:=CASE WHEN p_slot='A' THEN 1 ELSE 5 END;
  SELECT count(*) INTO occupied FROM private.hcv_demo_bookings_v2094 b
    WHERE b.event_id=p_event AND b.slot_key=p_slot AND b.status='booked';
  IF occupied>=cap THEN RAISE EXCEPTION 'เธฃเธญเธเธ—เธ”เธชเธญเธเธเธตเนเน€เธ•เนเธกเนเธฅเนเธง' USING ERRCODE='22023';END IF;
  INSERT INTO private.hcv_demo_bookings_v2094(
    event_id,source_pcucode,source_pid,booked_by,slot_key,hcv_selected,hbsag_selected)
  VALUES(p_event,p_pcucode,p_pid,user_id,p_slot,p_hcv IS TRUE,p_hbsag IS TRUE)
  RETURNING id INTO booking;
  RETURN jsonb_build_object('status','booked','booking_id',booking,
    'remaining',cap-occupied-1,'is_demo',true,'verification_status','pending_review');
 END $function$
;
CREATE OR REPLACE FUNCTION public.hcv_demo_slots_v2094(p_event uuid)
 RETURNS TABLE(slot_key text, slot_label text, capacity integer, remaining integer)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
 DECLARE a public.cloud_announcements_v2083%rowtype;
 BEGIN
  IF auth.uid() IS NULL OR NOT EXISTS(
   SELECT 1 FROM public.profiles p WHERE p.user_id=auth.uid() AND p.active
      AND p.role IN ('user','staff') AND p.volunteer_pid IS NOT NULL)
    THEN RAISE EXCEPTION 'เธเธฑเธเธเธต เธญเธชเธก. เธ—เธตเนเนเธ”เนเธฃเธฑเธเธญเธเธธเธเธฒเธ•เน€เธ—เนเธฒเธเธฑเนเธ' USING ERRCODE='42501';END IF;
  SELECT * INTO a FROM public.cloud_announcements_v2083
   WHERE id=p_event AND is_demo AND event_subtype='hcv_hbsag' AND status='published'
    AND booking_enabled=false AND demo_real_data_enabled=true AND (ends_at IS NULL OR ends_at>=now());
  IF NOT FOUND THEN RAISE EXCEPTION 'เนเธกเนเธเธเธเธดเธเธเธฃเธฃเธกเธ—เธ”เธชเธญเธเธ—เธตเนเน€เธเธดเธ”เนเธเนเธเธฒเธ' USING ERRCODE='22023';END IF;
  RETURN QUERY
  SELECT vals.key,vals.label,vals.cap,
    GREATEST(vals.cap-(SELECT count(*)::integer FROM private.hcv_demo_bookings_v2094 b
      WHERE b.event_id=p_event AND b.slot_key=vals.key AND b.status='booked'),0)
  FROM (VALUES('A'::text,'เธฃเธญเธเธ—เธ”เธฅเธญเธ A ยท เธฃเธฑเธ 1 เธฃเธฒเธขเธเธฒเธฃ'::text,1),
              ('B'::text,'เธฃเธญเธเธ—เธ”เธฅเธญเธ B ยท เธฃเธฑเธ 5 เธฃเธฒเธขเธเธฒเธฃ'::text,5)) vals(key,label,cap);
 END $function$
;
CREATE OR REPLACE FUNCTION public.list_my_hcv_demo_v2094(p_event uuid)
 RETURNS TABLE(booking_id uuid, source_pcucode text, source_pid bigint, display_name text, slot_key text, hcv_selected boolean, hbsag_selected boolean, verification_status text, hcv_performed boolean, hbsag_performed boolean, created_at timestamp with time zone)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE u uuid; vhv bigint;
BEGIN
 u:=auth.uid();
 SELECT p.volunteer_pid INTO vhv FROM public.profiles p
  WHERE p.user_id=u AND p.active AND p.role IN ('user','staff');
 IF u IS NULL OR NOT FOUND OR vhv IS NULL THEN
  RAISE EXCEPTION 'เน€เธเธเธฒเธฐเธเธฑเธเธเธต เธญเธชเธก. เธ—เธตเนเนเธ”เนเธฃเธฑเธเธชเธดเธ—เธเธดเน' USING ERRCODE='42501';END IF;
 IF NOT EXISTS(SELECT 1 FROM public.cloud_announcements_v2083 a
    WHERE a.id=p_event AND a.is_demo AND a.event_subtype='hcv_hbsag'
     AND a.status='published' AND NOT a.booking_enabled AND a.demo_real_data_enabled=true) THEN
  RAISE EXCEPTION 'เธเธดเธเธเธฃเธฃเธกเธ—เธ”เธชเธญเธเธเธตเนเนเธกเนเน€เธเธดเธ”เนเธเนเธเธฒเธ' USING ERRCODE='22023';END IF;
 RETURN QUERY SELECT b.id,b.source_pcucode,b.source_pid,hp.display_name,
 b.slot_key,b.hcv_selected,b.hbsag_selected,b.verification_status,
 b.hcv_performed,b.hbsag_performed,b.created_at
 FROM private.hcv_demo_bookings_v2094 b
 JOIN public.health_persons hp ON hp.source_pcucode=b.source_pcucode AND hp.source_pid=b.source_pid
 JOIN public.houses h ON h.source_pcucode=hp.house_pcucode AND h.hcode=hp.hcode
 WHERE b.event_id=p_event AND b.booked_by=u AND b.status='booked'
 AND hp.active AND hp.service_population_eligible
 AND h.superseded_by IS NULL AND h.verification_status='verified_jhcis'
 AND h.volunteer_pid=vhv AND private.health_can_access_house(hp.house_pcucode,hp.hcode)
 ORDER BY b.created_at DESC LIMIT 50;
END $function$
;
