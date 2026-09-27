ALTER TABLE private.hcv_demo_bookings_v2094
 ADD COLUMN IF NOT EXISTS contact_phone text NOT NULL DEFAULT '';
ALTER TABLE private.hcv_demo_bookings_v2094
 ADD CONSTRAINT hcv_demo_phone_v2099 CHECK (contact_phone='' OR contact_phone ~ '^0[0-9]{8,9}$');
COMMENT ON COLUMN private.hcv_demo_bookings_v2094.contact_phone IS
 'Test-only contact number, admin service report only, removed by demo reset; older records blank';
CREATE OR REPLACE FUNCTION public.book_hcv_demo_real_v2094(p_event uuid, p_pcucode text, p_pid bigint, p_slot text, p_hcv boolean, p_hbsag boolean, p_contact_phone text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
 DECLARE a public.cloud_announcements_v2083%rowtype;
         v_user uuid; vhv bigint; community text; v_existing uuid;
         cap integer; occupied integer; booking uuid;
 BEGIN
  v_user:=auth.uid();
  SELECT p.volunteer_pid,p.community INTO vhv,community
    FROM public.profiles p
    WHERE p.user_id=v_user AND p.active AND p.role IN ('user','staff');
  IF v_user IS NULL OR NOT FOUND OR vhv IS NULL THEN
    RAISE EXCEPTION 'เน€เธเธเธฒเธฐเธเธฑเธเธเธต เธญเธชเธก. User/Staff เธ—เธตเนเนเธ”เนเธฃเธฑเธเธกเธญเธเธซเธกเธฒเธข' USING ERRCODE='42501';
  END IF;
  IF p_pcucode IS NULL OR length(p_pcucode)>30 OR p_pid IS NULL OR p_pid<=0
     OR p_slot NOT IN ('A','B') OR p_slot IS NULL
     OR (p_hcv IS NOT TRUE AND p_hbsag IS NOT TRUE) THEN
    RAISE EXCEPTION 'เธเนเธญเธกเธนเธฅเธ—เธ”เธชเธญเธเนเธกเนเธ–เธนเธเธ•เนเธญเธ' USING ERRCODE='22023';
  END IF;
  IF p_contact_phone IS NULL OR p_contact_phone !~ '^0[0-9]{8,9}$' THEN
   RAISE EXCEPTION 'เธเธฃเธธเธ“เธฒเธเธฃเธญเธเน€เธเธญเธฃเนเธ•เธดเธ”เธ•เนเธญ 9โ€“10 เธซเธฅเธฑเธเธเธถเนเธเธ•เนเธเธ”เนเธงเธข 0' USING ERRCODE='22023';
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
    event_id,source_pcucode,source_pid,booked_by,slot_key,hcv_selected,hbsag_selected,contact_phone)
  VALUES(p_event,p_pcucode,p_pid,v_user,p_slot,p_hcv IS TRUE,p_hbsag IS TRUE,p_contact_phone)
  RETURNING id INTO booking;
  RETURN jsonb_build_object('status','booked','booking_id',booking,
    'remaining',cap-occupied-1,'is_demo',true,'verification_status','pending_review');
 END $function$
;
REVOKE ALL ON FUNCTION public.book_hcv_demo_real_v2094(uuid,text,bigint,text,boolean,boolean,text) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.book_hcv_demo_real_v2094(uuid,text,bigint,text,boolean,boolean,text) TO authenticated,service_role;
CREATE OR REPLACE FUNCTION public.book_hcv_demo_real_v2094(p_event uuid,p_pcucode text,p_pid bigint,p_slot text,p_hcv boolean,p_hbsag boolean)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=''
AS $old$
BEGIN
 RAISE EXCEPTION 'เธเธฃเธธเธ“เธฒเธฃเธตเน€เธเธฃเธเธซเธเนเธฒ Cloud เน€เธเธทเนเธญเนเธเนเนเธเธเธเธญเธเธ—เธ”เธชเธญเธเธ—เธตเนเธกเธตเน€เธเธญเธฃเนเธ•เธดเธ”เธ•เนเธญ' USING ERRCODE='22023';
END $old$;
REVOKE ALL ON FUNCTION public.book_hcv_demo_real_v2094(uuid,text,bigint,text,boolean,boolean) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.book_hcv_demo_real_v2094(uuid,text,bigint,text,boolean,boolean) TO authenticated,service_role;
CREATE OR REPLACE FUNCTION public.service_hcv_demo_report_v2094()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE e uuid; summary jsonb; items jsonb;
BEGIN
 IF auth.role() IS DISTINCT FROM 'service_role' THEN RAISE EXCEPTION 'Admin service only' USING ERRCODE='42501';END IF;
 SELECT a.id INTO e FROM public.cloud_announcements_v2083 a
 WHERE a.is_demo AND a.event_subtype='hcv_hbsag' AND a.status='published'
 ORDER BY a.published_at DESC LIMIT 1;
 IF e IS NULL THEN RETURN jsonb_build_object('is_demo',true,'totals',jsonb_build_object('total',0),'bookings','[]'::jsonb);END IF;
 SELECT jsonb_build_object(
 'total',count(*) FILTER(WHERE status='booked'),
 'cancelled',count(*) FILTER(WHERE status='cancelled'),
 'anti_hcv_booked',count(*) FILTER(WHERE status='booked' AND hcv_selected),
 'hbsag_booked',count(*) FILTER(WHERE status='booked' AND hbsag_selected),
 'both_booked',count(*) FILTER(WHERE status='booked' AND hcv_selected AND hbsag_selected),
 'pending_review',count(*) FILTER(WHERE status='booked' AND verification_status='pending_review'),
 'appointment_confirmed',count(*) FILTER(WHERE status='booked' AND verification_status='appointment_confirmed'),
 'needs_follow_up',count(*) FILTER(WHERE status='booked' AND verification_status='needs_follow_up'),
 'ineligible',count(*) FILTER(WHERE status='booked' AND verification_status='ineligible'),
 'anti_hcv_performed',count(*) FILTER(WHERE status='booked' AND hcv_performed),
 'hbsag_performed',count(*) FILTER(WHERE status='booked' AND hbsag_performed),
 'slot_a',count(*) FILTER(WHERE status='booked' AND slot_key='A'),
 'slot_b',count(*) FILTER(WHERE status='booked' AND slot_key='B')
 ) INTO summary FROM private.hcv_demo_bookings_v2094 WHERE event_id=e;
 SELECT coalesce(jsonb_agg(to_jsonb(r) ORDER BY r.created_at DESC),'[]'::jsonb) INTO items
 FROM (
 SELECT b.id AS booking_id,b.event_id,b.source_pcucode,b.source_pid,
        hp.display_name,b.slot_key,b.hcv_selected,b.hbsag_selected,b.contact_phone,
        b.status,b.verification_status,b.hcv_performed,b.hbsag_performed,
        p.role AS booker_role,p.volunteer_pid AS booker_volunteer_pid,
        b.created_at,b.updated_at,b.reviewed_by,b.reviewed_at
 FROM private.hcv_demo_bookings_v2094 b
 LEFT JOIN public.health_persons hp ON hp.source_pcucode=b.source_pcucode AND hp.source_pid=b.source_pid
 LEFT JOIN public.profiles p ON p.user_id=b.booked_by
 WHERE b.event_id=e
 ORDER BY b.created_at DESC LIMIT 100
 ) r;
 RETURN jsonb_build_object('is_demo',true,'event_id',e,'totals',summary,'bookings',items,
 'scope','isolated_demo_only_private_contact_resettable');
END $function$
;
