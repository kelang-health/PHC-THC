CREATE OR REPLACE FUNCTION public.book_hcv_demo_real_v2094(
 p_event uuid,p_pcucode text,p_pid bigint,p_slot text,p_hcv boolean,p_hbsag boolean)
 RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=''
 AS $f$
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
   OR a.status<>'published' OR a.booking_enabled IS DISTINCT FROM false
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
 END $f$;
REVOKE ALL ON FUNCTION public.book_hcv_demo_real_v2094(uuid,text,bigint,text,boolean,boolean) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.book_hcv_demo_real_v2094(uuid,text,bigint,text,boolean,boolean) TO authenticated;
