CREATE OR REPLACE FUNCTION public.list_my_hcv_demo_v2094(p_event uuid)
RETURNS TABLE(booking_id uuid,source_pcucode text,source_pid bigint,display_name text,
slot_key text,hcv_selected boolean,hbsag_selected boolean,verification_status text,
hcv_performed boolean,hbsag_performed boolean,created_at timestamptz)
LANGUAGE plpgsql SECURITY DEFINER SET search_path=''
AS $f$
DECLARE u uuid; vhv bigint;
BEGIN
 u:=auth.uid();
 SELECT p.volunteer_pid INTO vhv FROM public.profiles p
  WHERE p.user_id=u AND p.active AND p.role IN ('user','staff');
 IF u IS NULL OR NOT FOUND OR vhv IS NULL THEN
  RAISE EXCEPTION 'เน€เธเธเธฒเธฐเธเธฑเธเธเธต เธญเธชเธก. เธ—เธตเนเนเธ”เนเธฃเธฑเธเธชเธดเธ—เธเธดเน' USING ERRCODE='42501';END IF;
 IF NOT EXISTS(SELECT 1 FROM public.cloud_announcements_v2083 a
    WHERE a.id=p_event AND a.is_demo AND a.event_subtype='hcv_hbsag'
     AND a.status='published' AND NOT a.booking_enabled) THEN
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
END $f$;
CREATE OR REPLACE FUNCTION public.cancel_hcv_demo_v2094(p_booking uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=''
AS $f$
DECLARE b private.hcv_demo_bookings_v2094%rowtype; u uuid; vhv bigint;
BEGIN
 u:=auth.uid();
 SELECT p.volunteer_pid INTO vhv FROM public.profiles p
 WHERE p.user_id=u AND p.active AND p.role IN ('user','staff');
 IF u IS NULL OR NOT FOUND OR vhv IS NULL THEN RAISE EXCEPTION 'เนเธกเนเธกเธตเธชเธดเธ—เธเธดเนเธขเธเน€เธฅเธดเธ' USING ERRCODE='42501';END IF;
 SELECT * INTO b FROM private.hcv_demo_bookings_v2094 WHERE id=p_booking FOR UPDATE;
 IF NOT FOUND OR b.booked_by<>u THEN RAISE EXCEPTION 'เนเธกเนเธเธเธฃเธฒเธขเธเธฒเธฃเธ—เธ”เธฅเธญเธเธเธญเธเธ—เนเธฒเธ' USING ERRCODE='42501';END IF;
 IF NOT EXISTS(SELECT 1 FROM public.health_persons hp JOIN public.houses h ON h.source_pcucode=hp.house_pcucode AND h.hcode=hp.hcode
 WHERE hp.source_pcucode=b.source_pcucode AND hp.source_pid=b.source_pid AND hp.active
 AND h.volunteer_pid=vhv AND h.superseded_by IS NULL AND h.verification_status='verified_jhcis'
 AND private.health_can_access_house(hp.house_pcucode,hp.hcode)) THEN
 RAISE EXCEPTION 'เธเธธเธเธเธฅเนเธกเนเธญเธขเธนเนเนเธเธเธงเธฒเธกเธฃเธฑเธเธเธดเธ”เธเธญเธเธเธฑเธเธเธธเธเธฑเธ' USING ERRCODE='42501';END IF;
 IF b.status='cancelled' THEN RETURN jsonb_build_object('status','already_cancelled','is_demo',true);END IF;
 IF b.hcv_performed OR b.hbsag_performed THEN RAISE EXCEPTION 'เน€เธเนเธฒเธซเธเนเธฒเธ—เธตเนเธเธฑเธเธ—เธถเธเธเธฃเธดเธเธฒเธฃเธเธณเธฅเธญเธเนเธฅเนเธง เนเธกเนเธชเธฒเธกเธฒเธฃเธ–เธขเธเน€เธฅเธดเธ' USING ERRCODE='22023';END IF;
 UPDATE private.hcv_demo_bookings_v2094 SET status='cancelled',updated_at=now() WHERE id=b.id;
 RETURN jsonb_build_object('status','cancelled','is_demo',true);
END $f$;
REVOKE ALL ON FUNCTION public.list_my_hcv_demo_v2094(uuid) FROM PUBLIC,anon;
REVOKE ALL ON FUNCTION public.cancel_hcv_demo_v2094(uuid) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.list_my_hcv_demo_v2094(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.cancel_hcv_demo_v2094(uuid) TO authenticated;
