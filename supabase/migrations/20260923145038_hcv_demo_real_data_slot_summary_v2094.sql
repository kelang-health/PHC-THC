CREATE OR REPLACE FUNCTION public.hcv_demo_slots_v2094(p_event uuid)
 RETURNS TABLE(slot_key text,slot_label text,capacity integer,remaining integer)
 LANGUAGE plpgsql SECURITY DEFINER SET search_path=''
 AS $f$
 DECLARE a public.cloud_announcements_v2083%rowtype;
 BEGIN
  IF auth.uid() IS NULL OR NOT EXISTS(
   SELECT 1 FROM public.profiles p WHERE p.user_id=auth.uid() AND p.active
      AND p.role IN ('user','staff') AND p.volunteer_pid IS NOT NULL)
    THEN RAISE EXCEPTION 'เธเธฑเธเธเธต เธญเธชเธก. เธ—เธตเนเนเธ”เนเธฃเธฑเธเธญเธเธธเธเธฒเธ•เน€เธ—เนเธฒเธเธฑเนเธ' USING ERRCODE='42501';END IF;
  SELECT * INTO a FROM public.cloud_announcements_v2083
   WHERE id=p_event AND is_demo AND event_subtype='hcv_hbsag' AND status='published'
    AND booking_enabled=false AND (ends_at IS NULL OR ends_at>=now());
  IF NOT FOUND THEN RAISE EXCEPTION 'เนเธกเนเธเธเธเธดเธเธเธฃเธฃเธกเธ—เธ”เธชเธญเธเธ—เธตเนเน€เธเธดเธ”เนเธเนเธเธฒเธ' USING ERRCODE='22023';END IF;
  RETURN QUERY
  SELECT vals.key,vals.label,vals.cap,
    GREATEST(vals.cap-(SELECT count(*)::integer FROM private.hcv_demo_bookings_v2094 b
      WHERE b.event_id=p_event AND b.slot_key=vals.key AND b.status='booked'),0)
  FROM (VALUES('A'::text,'เธฃเธญเธเธ—เธ”เธฅเธญเธ A ยท เธฃเธฑเธ 1 เธฃเธฒเธขเธเธฒเธฃ'::text,1),
              ('B'::text,'เธฃเธญเธเธ—เธ”เธฅเธญเธ B ยท เธฃเธฑเธ 5 เธฃเธฒเธขเธเธฒเธฃ'::text,5)) vals(key,label,cap);
 END $f$;
REVOKE ALL ON FUNCTION public.hcv_demo_slots_v2094(uuid) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.hcv_demo_slots_v2094(uuid) TO authenticated;
