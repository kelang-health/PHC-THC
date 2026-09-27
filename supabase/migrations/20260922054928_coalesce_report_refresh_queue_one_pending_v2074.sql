
CREATE UNIQUE INDEX IF NOT EXISTS report_refresh_one_pending_v2074
  ON public.report_refresh_requests_v2031 ((true))
  WHERE processed_at IS NULL;

CREATE OR REPLACE FUNCTION private.enqueue_report_refresh_v2074(p_source text)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=''
AS $function$
BEGIN
  INSERT INTO public.report_refresh_requests_v2031(source,requested_at)
  VALUES(left(coalesce(nullif(btrim(p_source),''),'unknown'),120),clock_timestamp())
  ON CONFLICT ((true)) WHERE processed_at IS NULL
  DO UPDATE SET requested_at=GREATEST(public.report_refresh_requests_v2031.requested_at,EXCLUDED.requested_at);
END;
$function$;

REVOKE ALL ON FUNCTION private.enqueue_report_refresh_v2074(text) FROM public,anon,authenticated;

CREATE OR REPLACE FUNCTION private.queue_report_snapshot_refresh_v2031()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path=''
AS $function$
BEGIN
  PERFORM private.enqueue_report_refresh_v2074(tg_table_schema||'.'||tg_table_name);
  RETURN NULL;
END;
$function$;
