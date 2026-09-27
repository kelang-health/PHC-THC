ALTER TABLE public.cloud_announcements_v2083
 ADD COLUMN IF NOT EXISTS is_demo boolean NOT NULL DEFAULT false;
ALTER TABLE public.cloud_announcements_v2083
 ADD CONSTRAINT cloud_hcv_demo_no_live_booking_v2093 CHECK
 (NOT is_demo OR (kind='event' AND event_subtype='hcv_hbsag' AND audience='user' AND booking_enabled IS FALSE));
COMMENT ON COLUMN public.cloud_announcements_v2083.is_demo IS
 'HCV/HBsAg UI-only simulated test event. DB prevents real booking_enabled=true for this event.';
