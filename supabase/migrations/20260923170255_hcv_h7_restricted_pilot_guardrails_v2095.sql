ALTER TABLE public.cloud_announcements_v2083
 ADD COLUMN IF NOT EXISTS pilot_mode boolean NOT NULL DEFAULT false,
 ADD COLUMN IF NOT EXISTS pilot_approved_at timestamptz,
 ADD COLUMN IF NOT EXISTS pilot_approved_by text,
 ADD COLUMN IF NOT EXISTS pilot_approval_ref text;
ALTER TABLE public.cloud_announcements_v2083
 ADD CONSTRAINT hcv_pilot_approval_required_v2095
 CHECK (event_subtype <> 'hcv_hbsag' OR booking_enabled = false OR
 (is_demo = false AND pilot_mode = true
  AND pilot_approved_at IS NOT NULL
  AND length(trim(coalesce(pilot_approved_by,''))) BETWEEN 3 AND 100
  AND length(trim(coalesce(pilot_approval_ref,''))) BETWEEN 3 AND 150));
CREATE TABLE IF NOT EXISTS private.hcv_pilot_allowlist_v2095 (
 volunteer_pid bigint PRIMARY KEY,
 enabled boolean NOT NULL DEFAULT true,
 created_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE private.hcv_pilot_allowlist_v2095 ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE private.hcv_pilot_allowlist_v2095 FROM PUBLIC,anon,authenticated;
CREATE OR REPLACE FUNCTION private.hcv_pilot_can_access_v2095(p_event uuid)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path=''
AS $$
 SELECT EXISTS (
  SELECT 1 FROM public.cloud_announcements_v2083 a
  JOIN public.profiles p ON p.user_id=auth.uid()
  JOIN private.hcv_pilot_allowlist_v2095 allow_user
   ON allow_user.volunteer_pid=p.volunteer_pid AND allow_user.enabled IS TRUE
  WHERE a.id=p_event AND a.pilot_mode IS TRUE AND a.is_demo IS FALSE
   AND p.active IS TRUE AND p.role IN ('user','staff') AND p.volunteer_pid IS NOT NULL
   AND (a.target_community IS NULL OR a.target_community=p.community)
 )
$$;
REVOKE ALL ON FUNCTION private.hcv_pilot_can_access_v2095(uuid) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION private.hcv_pilot_can_access_v2095(uuid) TO authenticated,service_role;
INSERT INTO private.hcv_pilot_allowlist_v2095(volunteer_pid,enabled) VALUES
(18779,true),(2097,true)
ON CONFLICT(volunteer_pid) DO UPDATE SET enabled=EXCLUDED.enabled;
COMMENT ON TABLE private.hcv_pilot_allowlist_v2095 IS 'Restricted HCV pilot volunteer access; must not be used to infer clinic approval';
