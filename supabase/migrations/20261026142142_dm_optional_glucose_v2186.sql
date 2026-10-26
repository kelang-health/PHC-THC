-- Allow a genuinely unmeasured glucose only for a known DM patient.
-- Preserve all existing authorization, idempotency, BP and clinical guards.
alter table public.health_ncd_screenings alter column glucose_mg_dl drop not null;
DO $migration$
DECLARE definition text; original text;
BEGIN
 select pg_get_functiondef(p.oid) into definition
 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
 where n.nspname='public' and p.proname='save_health_ncd_screening';
 original := definition;
 definition := replace(definition,
  'if p_glucose_mg_dl is null or p_glucose_mg_dl not between 20 and 700 then raise exception ''invalid glucose''; end if;',
  'if p_glucose_mg_dl is null then
     if not coalesce(v_person.has_dm,false) then raise exception ''GLUCOSE_REQUIRED_WITHOUT_DM_HISTORY''; end if;
   elsif p_glucose_mg_dl not between 20 and 700 then raise exception ''invalid glucose''; end if;');
 definition := replace(definition,
  'if coalesce(p_glucose_type,'''') not in (''fasting'',''random'',''unknown'') then raise exception ''invalid glucose type''; end if;',
  'if p_glucose_mg_dl is null then
     p_glucose_type := ''unknown'';
   elsif coalesce(p_glucose_type,'''') not in (''fasting'',''random'') then raise exception ''invalid glucose type''; end if;');
 definition := replace(definition, 'v_glucose := case',
  'v_glucose := case when p_glucose_mg_dl is null then ''ข้ามการวัดน้ำตาล: มีประวัติโรคเบาหวานแล้ว''');
 if definition=original or position('GLUCOSE_REQUIRED_WITHOUT_DM_HISTORY' in definition)=0
    or position('ข้ามการวัดน้ำตาล' in definition)=0 then
   raise exception 'BASE_SCREENING_FUNCTION_CHANGED_REVIEW_REQUIRED';
 end if;
 execute definition;
END $migration$;
notify pgrst, 'reload schema';
