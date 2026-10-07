-- Free-plan compatible authorization hardening. No row changes or external sends.
DO $migration$
DECLARE r record; original text; fixed text; changed integer := 0;
BEGIN
 FOR r IN SELECT p.oid,p.prosrc FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
  WHERE n.nspname='public' AND p.prosecdef AND p.prosrc LIKE '%private.current_role()%'
 LOOP
  fixed := regexp_replace(r.prosrc, 'private[.]current_role\(\)[[:space:]]*<>[[:space:]]*''admin''', 'private.current_role() IS DISTINCT FROM ''admin''', 'g');
  fixed := regexp_replace(fixed, 'private[.]current_role\(\)[[:space:]]+not in', 'coalesce(private.current_role(),'''') not in', 'gi');
  fixed := regexp_replace(fixed, 'auth[.]role\(\)[[:space:]]*<>[[:space:]]*''service_role''', 'auth.role() IS DISTINCT FROM ''service_role''', 'g');
  IF r.oid::regprocedure::text LIKE 'sync_integrity_snapshot_v2193(%' THEN
   fixed := replace(fixed,'v_role<>''service_role''','v_role IS DISTINCT FROM ''service_role''');
  END IF;
  IF r.oid::regprocedure::text ~ '^coordinate_(audit_summary|boundary_review_worklist|movement_report)_v2132\(' THEN
   fixed := replace(fixed,'if v_role not in','if coalesce(v_role,'''') not in');
  END IF;
  IF fixed IS DISTINCT FROM r.prosrc THEN
   original := pg_get_functiondef(r.oid);
   EXECUTE replace(original,r.prosrc,fixed);
   changed := changed+1;
  END IF;
 END LOOP;
 IF changed <> 49 THEN RAISE EXCEPTION 'Unexpected changed function count: %; expected 49',changed; END IF;
END;
$migration$;

