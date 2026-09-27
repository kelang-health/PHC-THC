ALTER TABLE public.cloud_announcements_v2083
 ADD COLUMN IF NOT EXISTS pilot_target_rule_reference text,
 ADD COLUMN IF NOT EXISTS pilot_target_confirmed_at timestamptz;
ALTER TABLE public.cloud_announcements_v2083
 ADD CONSTRAINT hcv_h7_target_policy_required_v2100 CHECK (
    event_subtype<>'hcv_hbsag' OR is_demo OR booking_enabled IS FALSE
    OR (pilot_target_confirmed_at IS NOT NULL
        AND length(trim(coalesce(pilot_target_rule_reference,''))) BETWEEN 3 AND 150
        AND length(trim(coalesce(eligibility_notice,''))) >= 30)
 );
COMMENT ON COLUMN public.cloud_announcements_v2083.pilot_target_rule_reference IS
 'Local clinic-signed eligibility rule reference for a real HCV pilot; metadata only, not evidence of automatic person-level eligibility.';
COMMENT ON COLUMN public.cloud_announcements_v2083.pilot_target_confirmed_at IS
 'Clinic admin attest date for eligibility rule; patient requires subsequent manual verification before clinical service.';
