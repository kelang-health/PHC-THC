DO $patch$
DECLARE definition text; target regprocedure;
BEGIN
 SELECT p.oid::regprocedure,pg_get_functiondef(p.oid) INTO STRICT target,definition FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' AND p.proname='save_health_ncd_screening_v6';
 IF strpos(definition,'IF p_pulse IS NOT NULL AND p_pulse NOT BETWEEN 20 AND 250 THEN')=0 THEN RAISE EXCEPTION 'Unexpected function definition; no changes applied'; END IF;
 definition:=replace(definition,'IF p_pulse IS NOT NULL AND p_pulse NOT BETWEEN 20 AND 250 THEN','IF p_pulse IS NULL OR p_pulse NOT BETWEEN 20 AND 250 THEN');
 EXECUTE definition;
END $patch$;
