DROP POLICY IF EXISTS cloud_announcements_v2083_reader ON public.cloud_announcements_v2083;
CREATE POLICY cloud_announcements_v2083_reader ON public.cloud_announcements_v2083
 FOR SELECT TO authenticated
 USING (status='published' AND (starts_at IS NULL OR starts_at<=now())
 AND (ends_at IS NULL OR ends_at>=now())
 AND EXISTS (
 SELECT 1 FROM public.profiles p
 WHERE p.user_id=auth.uid() AND p.active IS TRUE
 AND (cloud_announcements_v2083.audience='all'
 OR cloud_announcements_v2083.audience=p.role
 OR (cloud_announcements_v2083.event_subtype='hcv_hbsag'
     AND cloud_announcements_v2083.audience='user'
     AND p.role='staff')
 OR (cloud_announcements_v2083.is_demo=true
     AND cloud_announcements_v2083.event_subtype='hcv_hbsag'
     AND p.role='admin'))
 AND (cloud_announcements_v2083.target_community IS NULL
      OR p.role='admin' OR cloud_announcements_v2083.target_community=p.community)
 ));
