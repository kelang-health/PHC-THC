DO $migration$
DECLARE definition text;
BEGIN
 definition := pg_get_viewdef('public.field_work_items_v200'::regclass,true);
 IF position('b.age_years >= 0 AND b.age_years <= 14' in definition)=0 THEN
   RAISE EXCEPTION 'Expected growth age predicate missing';
 END IF;
 definition := replace(definition,'b.age_years >= 0 AND b.age_years <= 14','b.age_years >= 0 AND b.age_years <= 5');
 EXECUTE 'CREATE OR REPLACE VIEW public.field_work_items_v200 WITH (security_invoker=true) AS ' || definition;
END $migration$;
