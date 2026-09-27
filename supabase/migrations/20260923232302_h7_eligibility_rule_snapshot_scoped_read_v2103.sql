CREATE TABLE IF NOT EXISTS public.h7_event_rules_v2103(
 event_id uuid PRIMARY KEY REFERENCES public.cloud_announcements_v2083(id) ON DELETE RESTRICT,
 program_kind text NOT NULL CHECK(program_kind IN('hcv_hbsag','fit','influenza','age_sex_only')),
 rule_version integer NOT NULL CHECK(rule_version BETWEEN 1 AND 1000000),
 age_min integer CHECK(age_min BETWEEN 0 AND 120),
 age_max integer CHECK(age_max BETWEEN 0 AND 120),
 gender_filter text NOT NULL DEFAULT 'all' CHECK(gender_filter IN('all','male','female')),
 history_lookback_months integer CHECK(history_lookback_months BETWEEN 0 AND 120),
 history_required boolean NOT NULL DEFAULT true,
 signed_rule_reference text NOT NULL CHECK(length(trim(signed_rule_reference)) BETWEEN 3 AND 150),
 approved_at timestamptz NOT NULL,
 updated_at timestamptz NOT NULL DEFAULT now(),
 CHECK(age_min IS NULL OR age_max IS NULL OR age_max>=age_min),
 CHECK((program_kind <> 'fit') OR (history_required=true AND history_lookback_months IS NOT NULL)),
 CHECK((program_kind <> 'influenza') OR history_required=true)
);
CREATE TABLE IF NOT EXISTS public.h7_eligibility_snapshots_v2103(
 event_id uuid NOT NULL REFERENCES public.cloud_announcements_v2083(id) ON DELETE RESTRICT,
 source_pcucode text NOT NULL CHECK(length(source_pcucode) BETWEEN 1 AND 30),
 source_pid bigint NOT NULL CHECK(source_pid>0),
 rule_version integer NOT NULL,
 age_at_service integer CHECK(age_at_service BETWEEN 0 AND 120),
 gender text NOT NULL CHECK(gender IN('male','female','unknown')),
 status text NOT NULL CHECK(status IN('preliminary_eligible','review_required','ineligible','stale')),
 reason_code text NOT NULL CHECK(reason_code IN('age_outside','sex_outside','history_unverified','clinical_rule_pending','birth_unknown','sex_unknown','data_stale','age_sex_match')),
 source_checked_at timestamptz NOT NULL,
 expires_at timestamptz NOT NULL,
 synced_at timestamptz NOT NULL DEFAULT now(),
 PRIMARY KEY(event_id,source_pcucode,source_pid),
 CHECK(expires_at>source_checked_at)
);
CREATE INDEX IF NOT EXISTS h7_eligibility_expires_idx ON public.h7_eligibility_snapshots_v2103(event_id,expires_at);
ALTER TABLE public.h7_event_rules_v2103 ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.h7_eligibility_snapshots_v2103 ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.h7_event_rules_v2103 FROM PUBLIC,anon,authenticated;
REVOKE ALL ON public.h7_eligibility_snapshots_v2103 FROM PUBLIC,anon,authenticated;
GRANT SELECT,INSERT,UPDATE,DELETE ON public.h7_event_rules_v2103 TO service_role;
GRANT SELECT,INSERT,UPDATE,DELETE ON public.h7_eligibility_snapshots_v2103 TO service_role;
COMMENT ON TABLE public.h7_eligibility_snapshots_v2103 IS
 'H7 preliminary eligibility, no diagnosis/CID/history/test result/telephone; user access via scoped RPC only. A missing/stale row is NOT eligibility.';
CREATE OR REPLACE FUNCTION public.h7_my_eligibility_v2103(p_event uuid,p_pcucode text,p_pid bigint)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=''
AS $fn$
DECLARE u uuid; v_vhv bigint; v_rule public.h7_event_rules_v2103%rowtype;
        s public.h7_eligibility_snapshots_v2103%rowtype;
BEGIN
 u:=auth.uid();
 SELECT p.volunteer_pid INTO v_vhv FROM public.profiles p
 WHERE p.user_id=u AND p.active IS TRUE AND p.role IN('user','staff');
 IF u IS NULL OR v_vhv IS NULL THEN
  RAISE EXCEPTION 'เนเธกเนเธกเธตเธชเธดเธ—เธเธดเนเธ•เธฃเธงเธเธเนเธญเธกเธนเธฅเธเธธเธเธเธฅ' USING ERRCODE='42501';END IF;
 IF NOT EXISTS(
  SELECT 1 FROM public.health_persons hp
  JOIN public.houses h ON h.source_pcucode=hp.house_pcucode AND h.hcode=hp.hcode
  WHERE hp.source_pcucode=p_pcucode AND hp.source_pid=p_pid
  AND hp.active AND hp.service_population_eligible AND h.superseded_by IS NULL
  AND h.verification_status='verified_jhcis' AND h.volunteer_pid=v_vhv
  AND private.health_can_access_house(hp.house_pcucode,hp.hcode)
 ) THEN RAISE EXCEPTION 'เธเธธเธเธเธฅเธเธตเนเนเธกเนเธญเธขเธนเนเนเธเธเธงเธฒเธกเธฃเธฑเธเธเธดเธ”เธเธญเธ' USING ERRCODE='42501';END IF;
 IF NOT EXISTS(
  SELECT 1 FROM public.cloud_announcements_v2083 a
  WHERE a.id=p_event AND a.kind='event' AND a.is_demo=false
  AND a.status='published' AND a.pilot_mode=true
  AND a.pilot_approved_at IS NOT NULL AND a.pilot_target_confirmed_at IS NOT NULL
  AND private.hcv_pilot_can_access_v2095(a.id)
 ) THEN RAISE EXCEPTION 'เธเธดเธเธเธฃเธฃเธกเธเธตเนเนเธกเนเธญเธขเธนเนเนเธเธเธญเธเน€เธเธ•เธเธณเธฃเนเธญเธ' USING ERRCODE='42501';END IF;
 SELECT * INTO v_rule FROM public.h7_event_rules_v2103 WHERE event_id=p_event;
 SELECT * INTO s FROM public.h7_eligibility_snapshots_v2103
 WHERE event_id=p_event AND source_pcucode=p_pcucode AND source_pid=p_pid;
 IF NOT FOUND OR s.expires_at<=now() OR v_rule.rule_version IS NULL
    OR s.rule_version<>v_rule.rule_version THEN
  RETURN jsonb_build_object('status','stale','reason_code','data_stale','eligible_to_request',false);
 END IF;
 RETURN jsonb_build_object('status',s.status,'reason_code',s.reason_code,
  'age_at_service',s.age_at_service,'gender',s.gender,
  'source_checked_at',s.source_checked_at,'expires_at',s.expires_at,
  'eligible_to_request',s.status='preliminary_eligible',
  'rule_version',s.rule_version);
END $fn$;
REVOKE ALL ON FUNCTION public.h7_my_eligibility_v2103(uuid,text,bigint) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.h7_my_eligibility_v2103(uuid,text,bigint) TO authenticated,service_role;
