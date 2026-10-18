
-- Additive workflow only; existing requests and JHCIS are not modified.
CREATE TABLE IF NOT EXISTS public.member_request_visibility_receipts_v2215 (
 request_id uuid PRIMARY KEY REFERENCES public.household_member_requests(id) ON DELETE RESTRICT,
 house_id uuid NOT NULL REFERENCES public.houses(id),
 linked_person_pcucode text NOT NULL,
 linked_person_id bigint NOT NULL,
 confirmed_by uuid NOT NULL REFERENCES auth.users(id),
 confirmed_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE public.member_request_visibility_receipts_v2215 ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.member_request_visibility_receipts_v2215 FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.field_confirm_member_visibility_v2215(p_request_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO ''
AS $fn$
DECLARE
 v_req public.household_member_requests%rowtype;
 v_house public.houses%rowtype;
 v_owner public.profiles%rowtype;
 v_person public.health_persons%rowtype;
BEGIN
 IF auth.uid() IS NULL THEN RAISE EXCEPTION 'AUTH_REQUIRED'; END IF;
 SELECT * INTO v_owner FROM public.profiles WHERE user_id=auth.uid() AND active AND role='user';
 IF NOT FOUND OR v_owner.volunteer_pid IS NULL THEN RAISE EXCEPTION 'VOLUNTEER_ACCOUNT_REQUIRED'; END IF;
 SELECT * INTO v_req FROM public.household_member_requests WHERE id=p_request_id FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'REQUEST_NOT_FOUND'; END IF;
 SELECT * INTO v_house FROM public.houses WHERE id=v_req.house_id;
 IF NOT FOUND OR v_house.superseded_by IS NOT NULL
 OR v_house.volunteer_pid IS DISTINCT FROM v_owner.volunteer_pid
 OR NOT private.health_can_access_house(v_house.source_pcucode,v_house.hcode)
 THEN RAISE EXCEPTION 'HOUSE_NOT_ASSIGNED_TO_YOU'; END IF;
 IF v_req.status<>'verified' OR v_req.jhcis_verification_status<>'verified_jhcis'
 OR v_req.linked_person_pcucode IS NULL OR v_req.linked_person_id IS NULL
 THEN RAISE EXCEPTION 'REQUEST_NOT_LINKED_TO_JHCIS'; END IF;
 SELECT * INTO v_person FROM public.health_persons
 WHERE source_pcucode=v_req.linked_person_pcucode AND source_pid=v_req.linked_person_id
 AND house_pcucode=v_house.source_pcucode AND hcode=v_house.hcode
 AND active AND service_population_eligible;
 IF NOT FOUND THEN RAISE EXCEPTION 'LINKED_PERSON_NOT_VISIBLE_IN_ASSIGNED_HOUSE'; END IF;
 INSERT INTO public.member_request_visibility_receipts_v2215(
 request_id,house_id,linked_person_pcucode,linked_person_id,confirmed_by)
 VALUES (v_req.id,v_house.id,v_req.linked_person_pcucode,v_req.linked_person_id,auth.uid())
 ON CONFLICT (request_id) DO UPDATE SET
 house_id=EXCLUDED.house_id,linked_person_pcucode=EXCLUDED.linked_person_pcucode,
 linked_person_id=EXCLUDED.linked_person_id,confirmed_by=EXCLUDED.confirmed_by,
 confirmed_at=now();
 INSERT INTO public.health_audit_log(operator_id,action,entity,entity_id,
 source_pcucode,source_pid,hcode,severity,details)
 VALUES(auth.uid(),'FIELD_MEMBER_VISIBLE','household_member_request',v_req.id::text,
 v_req.linked_person_pcucode,v_req.linked_person_id,v_house.hcode,'verified',
 jsonb_build_object('verified_by_assigned_volunteer',true,'jhcis_write_back',false));
 RETURN jsonb_build_object('ok',true,'request_id',v_req.id,'verified_member_visible',true);
END
$fn$;

CREATE OR REPLACE FUNCTION public.field_member_visibility_candidates_v2215(p_house_id uuid)
RETURNS TABLE(id uuid, full_name text, linked_person_id bigint, confirmed boolean)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO ''
AS $fn$
BEGIN
 IF auth.uid() IS NULL OR NOT EXISTS (
 SELECT 1 FROM public.profiles p JOIN public.houses h ON h.id=p_house_id
 WHERE p.user_id=auth.uid() AND p.active AND p.role='user'
 AND p.volunteer_pid IS NOT NULL AND p.volunteer_pid=h.volunteer_pid
 AND h.superseded_by IS NULL
 AND private.health_can_access_house(h.source_pcucode,h.hcode)
 ) THEN RAISE EXCEPTION 'HOUSE_OUT_OF_SCOPE'; END IF;
 RETURN QUERY
 SELECT r.id,r.full_name,r.linked_person_id,
 (v.request_id IS NOT NULL AND v.linked_person_id=r.linked_person_id
  AND v.linked_person_pcucode=r.linked_person_pcucode
  AND v.house_id=r.house_id AND v.confirmed_by=auth.uid())
 FROM public.household_member_requests r
 JOIN public.houses h ON h.id=r.house_id
 JOIN public.health_persons person ON person.source_pcucode=r.linked_person_pcucode
 AND person.source_pid=r.linked_person_id AND person.house_pcucode=h.source_pcucode
 AND person.hcode=h.hcode AND person.active AND person.service_population_eligible
 LEFT JOIN public.member_request_visibility_receipts_v2215 v ON v.request_id=r.id
 WHERE r.house_id=p_house_id AND r.status='verified'
 AND r.jhcis_verification_status='verified_jhcis'
 ORDER BY r.created_at DESC LIMIT 100;
END
$fn$;

CREATE OR REPLACE FUNCTION public.admin_return_member_correction_v2215(p_request_id uuid,p_reason text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO ''
AS $fn$
DECLARE v_req public.household_member_requests%rowtype;
        v_house public.houses%rowtype;
        v_reason text:=btrim(coalesce(p_reason,''));
BEGIN
 IF auth.uid() IS NULL OR private.current_role() IS DISTINCT FROM 'admin' THEN
   RAISE EXCEPTION 'ADMIN_REQUIRED'; END IF;
 IF char_length(v_reason) NOT BETWEEN 8 AND 300
 OR NOT private.safe_notification_text_v190(v_reason)
 THEN RAISE EXCEPTION 'CORRECTION_REASON_REQUIRED_8_TO_300_NO_SENSITIVE_DATA'; END IF;
 SELECT * INTO v_req FROM public.household_member_requests WHERE id=p_request_id FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'REQUEST_NOT_FOUND'; END IF;
 IF v_req.status NOT IN ('pending','verified','needs_correction')
 OR v_req.linked_person_id IS NOT NULL OR v_req.linked_person_pcucode IS NOT NULL
 OR v_req.jhcis_verification_status IN ('verified_jhcis','rejected','superseded')
 THEN RAISE EXCEPTION 'ONLY_UNLINKED_OPEN_REQUESTS_CAN_BE_RETURNED'; END IF;
 SELECT * INTO v_house FROM public.houses WHERE id=v_req.house_id;
 UPDATE public.household_member_requests SET status='needs_correction',
  jhcis_verification_status='review_required',
  review_note=left(v_reason,300),
  jhcis_verification_note='ส่งกลับแก้ไข: '||left(v_reason,300),
  reviewed_by=auth.uid(),reviewed_at=now(),jhcis_checked_at=now(),updated_at=clock_timestamp()
 WHERE id=v_req.id;
 INSERT INTO public.health_audit_log(operator_id,action,entity,entity_id,source_pcucode,hcode,severity,details)
 VALUES(auth.uid(),'MEMBER_RETURN_CORRECTION','household_member_request',v_req.id::text,
 v_house.source_pcucode,v_house.hcode,'needs_correction',
 jsonb_build_object('reason',v_reason,'prior_status',v_req.status,
 'prior_jhcis_status',v_req.jhcis_verification_status,'jhcis_write_back',false));
 RETURN jsonb_build_object('ok',true,'status','needs_correction','request_id',v_req.id);
END
$fn$;

CREATE OR REPLACE FUNCTION public.admin_member_worklist_v2215(
 p_scope text DEFAULT 'open',p_limit integer DEFAULT 30,p_offset integer DEFAULT 0)
RETURNS TABLE(
 id uuid,house_id uuid,house_no text,moo text,community text,
 full_name text,birth_date date,masked_citizen_id text,
 status text,jhcis_verification_status text,review_note text,
 jhcis_verification_note text,created_at timestamptz,updated_at timestamptz,
 linked_person_id bigint,assigned_volunteer_pid bigint,
 requester_name text,requester_community text,
 requester_user_id uuid,requester_line_connected boolean,
 roster_found boolean,owner_account_ready boolean,
 workflow_state text,total_count bigint)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO ''
AS $fn$
DECLARE v_scope text:=lower(btrim(coalesce(p_scope,'open')));
BEGIN
 IF auth.uid() IS NULL OR private.current_role() IS DISTINCT FROM 'admin' THEN
   RAISE EXCEPTION 'ADMIN_REQUIRED'; END IF;
 IF v_scope NOT IN ('all','open','pending','jhcis','field','correction','completed','cancelled','exception')
 THEN RAISE EXCEPTION 'INVALID_SCOPE'; END IF;
 IF p_limit IS NULL OR p_limit<1 OR p_limit>100 OR p_offset IS NULL OR p_offset<0
 THEN RAISE EXCEPTION 'INVALID_PAGINATION'; END IF;
 RETURN QUERY
 WITH base AS (
 SELECT r.id,r.house_id,h.house_no,h.moo,h.community,
 r.full_name,r.birth_date,('•••••••••'||r.citizen_id_last4)::text AS masked_citizen_id,
 r.status,r.jhcis_verification_status,r.review_note,r.jhcis_verification_note,
 r.created_at,r.updated_at,r.linked_person_id,h.volunteer_pid AS assigned_volunteer_pid,
 coalesce(nullif(btrim(sender.display_name),''),'ไม่ระบุ')::text AS requester_name,
 coalesce(nullif(btrim(sender.community),''),'ไม่ระบุ')::text AS requester_community,
 CASE WHEN sender.active AND EXISTS(SELECT 1 FROM public.user_line_links l
 WHERE l.app_user_id=r.submitted_by AND l.active) THEN r.submitted_by ELSE NULL::uuid END AS requester_user_id,
 (coalesce(sender.active,false) AND EXISTS(SELECT 1 FROM public.user_line_links l
 WHERE l.app_user_id=r.submitted_by AND l.active)) AS requester_line_connected,
 (person.source_pid IS NOT NULL AND person.active AND person.service_population_eligible AND
 h.superseded_by IS NULL) AS roster_found,
 EXISTS(SELECT 1 FROM public.profiles owner
 WHERE owner.active AND owner.role='user' AND owner.volunteer_pid=h.volunteer_pid
 AND h.volunteer_pid IS NOT NULL) AS owner_account_ready,
 (receipt.request_id IS NOT NULL AND receipt.house_id=h.id AND
 receipt.linked_person_pcucode=r.linked_person_pcucode AND
 receipt.linked_person_id=r.linked_person_id AND
 EXISTS(SELECT 1 FROM public.profiles confirmer WHERE confirmer.user_id=receipt.confirmed_by
 AND confirmer.active AND confirmer.role='user' AND confirmer.volunteer_pid=h.volunteer_pid)) AS field_confirmed
 FROM public.household_member_requests r
 JOIN public.houses h ON h.id=r.house_id
 LEFT JOIN public.profiles sender ON sender.user_id=r.submitted_by
 LEFT JOIN public.health_persons person
 ON person.source_pcucode=r.linked_person_pcucode AND person.source_pid=r.linked_person_id
 AND person.house_pcucode=h.source_pcucode AND person.hcode=h.hcode
 LEFT JOIN public.member_request_visibility_receipts_v2215 receipt ON receipt.request_id=r.id
 ),
 staged AS (
 SELECT base.*, CASE
 WHEN status='rejected' OR jhcis_verification_status='rejected' THEN 'cancelled'
 WHEN status='needs_correction' OR jhcis_verification_status='review_required' THEN 'correction'
 WHEN status='pending' THEN 'pending'
 WHEN jhcis_verification_status='verified_jhcis' AND linked_person_id IS NOT NULL
 AND roster_found AND owner_account_ready AND field_confirmed THEN 'completed'
 WHEN jhcis_verification_status='verified_jhcis' AND linked_person_id IS NOT NULL
 AND roster_found AND owner_account_ready THEN 'field'
 WHEN jhcis_verification_status='verified_jhcis' THEN 'exception'
 ELSE 'jhcis' END AS stage
 FROM base
 ),
 scoped AS (
 SELECT * FROM staged WHERE
 v_scope='all' OR (v_scope='open' AND stage NOT IN ('completed','cancelled'))
 OR (v_scope='exception' AND stage='exception')
 OR stage=v_scope
 )
 SELECT s.id,s.house_id,s.house_no,s.moo,s.community,
 s.full_name,s.birth_date,s.masked_citizen_id,s.status,s.jhcis_verification_status,
 s.review_note,s.jhcis_verification_note,s.created_at,s.updated_at,
 s.linked_person_id,s.assigned_volunteer_pid,
 s.requester_name,s.requester_community,s.requester_user_id,s.requester_line_connected,
 s.roster_found,s.owner_account_ready,s.stage,count(*) OVER ()::bigint
 FROM scoped s ORDER BY s.created_at DESC,s.id DESC
 LIMIT p_limit OFFSET p_offset;
END
$fn$;
REVOKE ALL ON FUNCTION public.admin_member_worklist_v2215(text,integer,integer) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.admin_return_member_correction_v2215(uuid,text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.field_confirm_member_visibility_v2215(uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.field_member_visibility_candidates_v2215(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_member_worklist_v2215(text,integer,integer) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_return_member_correction_v2215(uuid,text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.field_confirm_member_visibility_v2215(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.field_member_visibility_candidates_v2215(uuid) TO authenticated;
