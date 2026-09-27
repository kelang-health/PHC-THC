
CREATE OR REPLACE FUNCTION private.sync_screening_target_house_v2075()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path=''
AS $fn$
BEGIN
  -- Only propagate changes affecting displayed house or owner. Metadata-only
  -- updates do not rewrite target rows or require a full cache refresh.
  WITH changed AS (
    SELECT n.source_pcucode,n.hcode,n.house_no,n.moo,n.community,n.volunteer_pid
    FROM report_houses_new n
    JOIN report_houses_old o USING(id)
    WHERE n.source_pcucode IS NOT DISTINCT FROM o.source_pcucode
      AND n.hcode IS NOT DISTINCT FROM o.hcode
      AND n.superseded_by IS NULL AND n.verification_status='verified_jhcis'
      AND ROW(n.house_no,n.moo,n.community,n.volunteer_pid)
        IS DISTINCT FROM ROW(o.house_no,o.moo,o.community,o.volunteer_pid)
  )
  UPDATE public.health_screening_target_cache_v2030 c
  SET house_no=x.house_no,moo=x.moo,community=x.community,volunteer_pid=x.volunteer_pid
  FROM changed x
  WHERE c.source_pcucode=x.source_pcucode AND c.hcode=x.hcode
    AND ROW(c.house_no,c.moo,c.community,c.volunteer_pid)
       IS DISTINCT FROM ROW(x.house_no,x.moo,x.community,x.volunteer_pid);

  -- House no longer verified/current: hide its derived screening target.
  -- Person/house records and screening submissions are never deleted here.
  DELETE FROM public.health_screening_target_cache_v2030 c
  USING report_houses_new n
  JOIN report_houses_old o USING(id)
  WHERE o.superseded_by IS NULL AND o.verification_status='verified_jhcis'
    AND (n.superseded_by IS NOT NULL OR n.verification_status IS DISTINCT FROM 'verified_jhcis'
      OR n.source_pcucode IS DISTINCT FROM o.source_pcucode OR n.hcode IS DISTINCT FROM o.hcode)
    AND c.source_pcucode=o.source_pcucode AND c.hcode=o.hcode;
  RETURN NULL;
END;
$fn$;

REVOKE ALL ON FUNCTION private.sync_screening_target_house_v2075() FROM PUBLIC,anon,authenticated;

CREATE TRIGGER screening_target_house_delta_v2075
AFTER UPDATE ON public.houses
REFERENCING OLD TABLE AS report_houses_old NEW TABLE AS report_houses_new
FOR EACH STATEMENT EXECUTE FUNCTION private.sync_screening_target_house_v2075();
