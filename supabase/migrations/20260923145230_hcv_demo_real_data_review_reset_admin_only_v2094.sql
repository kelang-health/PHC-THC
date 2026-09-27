CREATE OR REPLACE FUNCTION public.service_hcv_demo_review_v2094(
 p_booking uuid,p_status text,p_hcv_performed boolean,p_hbsag_performed boolean,p_actor text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=''
AS $f$
DECLARE b private.hcv_demo_bookings_v2094%rowtype; was_changed boolean;
BEGIN
 IF auth.role() IS DISTINCT FROM 'service_role' THEN RAISE EXCEPTION 'Admin service only' USING ERRCODE='42501';END IF;
 IF p_actor IS NULL OR length(p_actor) NOT BETWEEN 1 AND 100
  OR p_status NOT IN ('pending_review','appointment_confirmed','needs_follow_up','ineligible')
  OR p_status IS NULL OR p_hcv_performed IS NULL OR p_hbsag_performed IS NULL THEN
   RAISE EXCEPTION 'Review input invalid' USING ERRCODE='22023';END IF;
 SELECT * INTO b FROM private.hcv_demo_bookings_v2094 WHERE id=p_booking FOR UPDATE;
 IF NOT FOUND OR b.status<>'booked' OR NOT EXISTS(
  SELECT 1 FROM public.cloud_announcements_v2083 a
  WHERE a.id=b.event_id AND a.is_demo AND a.event_subtype='hcv_hbsag'
   AND a.status='published' AND NOT a.booking_enabled) THEN
  RAISE EXCEPTION 'เนเธกเนเธเธเธฃเธฒเธขเธเธฒเธฃเธเธญเธเธ—เธ”เธชเธญเธเธ—เธตเนเนเธเนเธเธฒเธเธญเธขเธนเน' USING ERRCODE='22023';END IF;
 IF (p_hcv_performed AND NOT b.hcv_selected) OR (p_hbsag_performed AND NOT b.hbsag_selected)
 OR ((p_hcv_performed OR p_hbsag_performed) AND p_status<>'appointment_confirmed') THEN
  RAISE EXCEPTION 'เธชเธ–เธฒเธเธฐเธเธฑเธเธ—เธถเธเธเธฃเธดเธเธฒเธฃเธเธณเธฅเธญเธเนเธกเนเธ•เธฃเธเธเธฑเธเธฃเธฒเธขเธเธฒเธฃเธ•เธฃเธงเธ' USING ERRCODE='22023';END IF;
 was_changed:= b.verification_status IS DISTINCT FROM p_status
 OR b.hcv_performed IS DISTINCT FROM p_hcv_performed
 OR b.hbsag_performed IS DISTINCT FROM p_hbsag_performed;
 IF was_changed THEN
  UPDATE private.hcv_demo_bookings_v2094
  SET verification_status=p_status,hcv_performed=p_hcv_performed,hbsag_performed=p_hbsag_performed,
      reviewed_by=p_actor,reviewed_at=now(),updated_at=now() WHERE id=b.id;
  INSERT INTO private.hcv_demo_review_audit_v2094(event_id,booking_id,actor,before_status,after_status,
   before_hcv_performed,after_hcv_performed,before_hbsag_performed,after_hbsag_performed)
  VALUES(b.event_id,b.id,p_actor,b.verification_status,p_status,
   b.hcv_performed,p_hcv_performed,b.hbsag_performed,p_hbsag_performed);
 END IF;
 RETURN jsonb_build_object('ok',true,'is_demo',true,'booking_id',b.id,
 'verification_status',p_status,'hcv_performed',p_hcv_performed,'hbsag_performed',p_hbsag_performed,
 'unchanged',NOT was_changed);
END $f$;
REVOKE ALL ON FUNCTION public.service_hcv_demo_review_v2094(uuid,text,boolean,boolean,text) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.service_hcv_demo_review_v2094(uuid,text,boolean,boolean,text) TO service_role;
CREATE OR REPLACE FUNCTION public.service_hcv_demo_reset_v2094(p_confirmation text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=''
AS $f$
DECLARE e uuid; bookings_deleted integer; audit_deleted integer; before_count integer;
BEGIN
 IF auth.role() IS DISTINCT FROM 'service_role' THEN RAISE EXCEPTION 'Admin service only' USING ERRCODE='42501'; END IF;
 IF p_confirmation IS DISTINCT FROM 'RESET_HCV_DEMO_ONLY' THEN
  RAISE EXCEPTION 'เธขเธทเธเธขเธฑเธเธเธฒเธฃเธฃเธตเน€เธเนเธ•เนเธซเธกเธ”เธ—เธ”เธฅเธญเธเนเธกเนเธ–เธนเธเธ•เนเธญเธ' USING ERRCODE='22023';END IF;
 SELECT a.id INTO e FROM public.cloud_announcements_v2083 a
 WHERE a.is_demo AND a.event_subtype='hcv_hbsag' AND a.status='published'
 ORDER BY a.published_at DESC LIMIT 1 FOR UPDATE;
 IF e IS NULL THEN RAISE EXCEPTION 'เนเธกเนเธเธเธเธดเธเธเธฃเธฃเธกเธ—เธ”เธชเธญเธเธ—เธตเนเน€เธเธดเธ”เนเธเนเธเธฒเธ' USING ERRCODE='22023';END IF;
 SELECT count(*) INTO before_count FROM private.hcv_demo_bookings_v2094 WHERE event_id=e;
 DELETE FROM private.hcv_demo_review_audit_v2094 WHERE event_id=e;
 GET DIAGNOSTICS audit_deleted=ROW_COUNT;
 DELETE FROM private.hcv_demo_bookings_v2094 WHERE event_id=e;
 GET DIAGNOSTICS bookings_deleted=ROW_COUNT;
 IF bookings_deleted<>before_count THEN RAISE EXCEPTION 'เธฃเธตเน€เธเนเธ•เธฃเธฒเธขเธเธฒเธฃเธ—เธ”เธชเธญเธเนเธกเนเธชเธกเธเธนเธฃเธ“เน';END IF;
 RETURN jsonb_build_object('ok',true,'is_demo',true,'event_id',e,
 'removed_demo_bookings',bookings_deleted,'removed_demo_review_audit',audit_deleted,
 'real_bookings_modified',false,'real_patient_records_modified',false);
END $f$;
REVOKE ALL ON FUNCTION public.service_hcv_demo_reset_v2094(text) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.service_hcv_demo_reset_v2094(text) TO service_role;
