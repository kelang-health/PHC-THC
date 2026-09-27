CREATE OR REPLACE FUNCTION public.search_h7_event_people_v2103(
 p_event uuid,p_query text,p_limit integer DEFAULT 20)
RETURNS TABLE(source_pcucode text,source_pid bigint,display_name text,birth_date date,
 house_no text,community text,age_at_service integer,gender text,
 eligibility_status text,reason_code text,can_request boolean)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path=''
AS $fn$
 SELECT person.source_pcucode,person.source_pid,person.display_name,
 person.birth_date,person.house_no,person.community,
 snap.age_at_service,snap.gender,
 CASE WHEN rule.rule_version IS NULL OR snap.rule_version IS DISTINCT FROM rule.rule_version
   OR snap.expires_at IS NULL OR snap.expires_at<=now()
   THEN 'stale'::text ELSE snap.status END AS eligibility_status,
 CASE WHEN rule.rule_version IS NULL OR snap.rule_version IS DISTINCT FROM rule.rule_version
   OR snap.expires_at IS NULL OR snap.expires_at<=now()
   THEN 'data_stale'::text ELSE snap.reason_code END AS reason_code,
 coalesce(snap.status='preliminary_eligible' AND snap.expires_at>now()
     AND snap.rule_version=rule.rule_version
     AND rule.signed_rule_reference=activity.pilot_target_rule_reference
     AND activity.pilot_target_confirmed_at IS NOT NULL,false) AS can_request
 FROM public.search_hcv_event_people_v2087(p_event,p_query,p_limit) person
 LEFT JOIN public.cloud_announcements_v2083 activity ON activity.id=p_event
 LEFT JOIN public.h7_event_rules_v2103 rule ON rule.event_id=p_event
 LEFT JOIN public.h7_eligibility_snapshots_v2103 snap
  ON snap.event_id=p_event AND snap.source_pcucode=person.source_pcucode
   AND snap.source_pid=person.source_pid
 ORDER BY person.display_name,person.source_pid
 LIMIT least(greatest(coalesce(p_limit,20),1),20)
$fn$;
REVOKE ALL ON FUNCTION public.search_h7_event_people_v2103(uuid,text,integer) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.search_h7_event_people_v2103(uuid,text,integer) TO authenticated,service_role;
