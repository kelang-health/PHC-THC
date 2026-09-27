ALTER TABLE public.cloud_announcements_v2083
 ADD COLUMN IF NOT EXISTS demo_real_data_enabled boolean NOT NULL DEFAULT false;
ALTER TABLE public.cloud_announcements_v2083
 ADD CONSTRAINT cloud_hcv_demo_real_flag_v2094
 CHECK (NOT demo_real_data_enabled OR (is_demo AND event_subtype='hcv_hbsag' AND booking_enabled=false));
COMMENT ON COLUMN public.cloud_announcements_v2083.demo_real_data_enabled IS
 'Authorizes scoped real-household read with isolated nonclinical demonstration bookings, no production appointments.';
