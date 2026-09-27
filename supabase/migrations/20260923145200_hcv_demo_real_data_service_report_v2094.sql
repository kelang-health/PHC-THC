CREATE OR REPLACE FUNCTION public.service_hcv_demo_report_v2094()
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=''
AS $f$
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
        hp.display_name,b.slot_key,b.hcv_selected,b.hbsag_selected,
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
 'scope','isolated_demo_only_no_clinical_result_no_phone');
END $f$;
REVOKE ALL ON FUNCTION public.service_hcv_demo_report_v2094() FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.service_hcv_demo_report_v2094() TO service_role;
