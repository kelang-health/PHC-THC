CREATE OR REPLACE FUNCTION public.admin_member_worklist_v2215(p_scope text DEFAULT 'open'::text, p_limit integer DEFAULT 30, p_offset integer DEFAULT 0)
 RETURNS TABLE(id uuid, house_id uuid, house_no text, moo text, community text, full_name text, birth_date date, masked_citizen_id text, status text, jhcis_verification_status text, review_note text, jhcis_verification_note text, created_at timestamp with time zone, updated_at timestamp with time zone, linked_person_id bigint, assigned_volunteer_pid bigint, requester_name text, requester_community text, requester_user_id uuid, requester_line_connected boolean, roster_found boolean, owner_account_ready boolean, workflow_state text, total_count bigint)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
#variable_conflict use_column
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
$function$
