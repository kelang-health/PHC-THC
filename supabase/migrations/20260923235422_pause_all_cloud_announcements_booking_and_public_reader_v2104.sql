CREATE OR REPLACE FUNCTION public.cloud_announcements_pause_guard_v2104()
RETURNS trigger LANGUAGE plpgsql SET search_path=''
AS $fn$
BEGIN
 IF NEW.status='published' OR NEW.booking_enabled IS TRUE OR NEW.home_featured IS TRUE THEN
  RAISE EXCEPTION 'เธฃเธฐเธเธเธเธฃเธฐเธเธฒเธจเนเธฅเธฐเธเธดเธเธเธฃเธฃเธก Cloud เธเธดเธ”เธเธฑเนเธงเธเธฃเธฒเธงเน€เธเธทเนเธญเธเธฑเธ’เธเธฒเน€เธเธ“เธ‘เนเธซเธฅเธฑเธเธเนเธฒเธ'
  USING ERRCODE='22023';
 END IF;
 RETURN NEW;
END $fn$;
DROP TRIGGER IF EXISTS cloud_announcements_pause_guard_v2104
 ON public.cloud_announcements_v2083;
CREATE TRIGGER cloud_announcements_pause_guard_v2104
 BEFORE INSERT OR UPDATE OF status,booking_enabled,home_featured
 ON public.cloud_announcements_v2083
 FOR EACH ROW EXECUTE FUNCTION public.cloud_announcements_pause_guard_v2104();
DROP POLICY IF EXISTS cloud_announcements_v2083_reader ON public.cloud_announcements_v2083;
CREATE POLICY cloud_announcements_v2083_reader ON public.cloud_announcements_v2083
 FOR SELECT TO authenticated USING (false);
COMMENT ON POLICY cloud_announcements_v2083_reader ON public.cloud_announcements_v2083 IS
 'V2104: operator requested all announcements and activities hidden from Cloud during Local eligibility-rule development. Restore only with explicit approval.';
COMMENT ON TRIGGER cloud_announcements_pause_guard_v2104 ON public.cloud_announcements_v2083 IS
 'Prevent accidental republication while operator has paused all public announcements';
