ALTER TABLE public.health_ncd_screenings ADD COLUMN pulse integer CHECK (pulse IS NULL OR pulse BETWEEN 20 AND 250);
COMMENT ON COLUMN public.health_ncd_screenings.pulse IS 'Measured pulse, beats/minute; NULL means not measured. Technical input bounds only.';
CREATE OR REPLACE FUNCTION public.save_health_ncd_screening_v6(p_source_pcucode text, p_source_pid bigint, p_screened_on date, p_weight_kg numeric, p_height_cm numeric, p_waist_cm numeric, p_sbp integer, p_dbp integer, p_glucose_mg_dl integer, p_glucose_type text, p_danger_symptoms boolean, p_smoking_frequency text, p_alcohol_frequency text, p_exercise_frequency text, p_note text, p_request_id uuid, p_mental_2q_q1 boolean DEFAULT NULL::boolean, p_mental_2q_q2 boolean DEFAULT NULL::boolean, p_sbp_repeat integer DEFAULT NULL::integer, p_dbp_repeat integer DEFAULT NULL::integer, p_pulse integer DEFAULT NULL)
RETURNS public.health_ncd_screenings LANGUAGE plpgsql SECURITY DEFINER SET search_path TO '' AS $function$
DECLARE v_row public.health_ncd_screenings;
BEGIN
 IF auth.uid() IS NULL OR private.current_role() IS NULL THEN RAISE EXCEPTION 'Not authorized'; END IF;
 PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(auth.uid()::text||':'||p_request_id::text,0));
 SELECT * INTO v_row FROM public.health_ncd_screenings WHERE recorded_by=auth.uid() AND request_id=p_request_id;
 IF FOUND THEN RETURN v_row; END IF;
 IF p_pulse IS NOT NULL AND p_pulse NOT BETWEEN 20 AND 250 THEN RAISE EXCEPTION 'invalid pulse'; END IF;
 v_row := public.save_health_ncd_screening_v5(p_source_pcucode,p_source_pid,p_screened_on,p_weight_kg,p_height_cm,p_waist_cm,p_sbp,p_dbp,p_glucose_mg_dl,p_glucose_type,p_danger_symptoms,p_smoking_frequency,p_alcohol_frequency,p_exercise_frequency,p_note,p_request_id,p_mental_2q_q1,p_mental_2q_q2,p_sbp_repeat,p_dbp_repeat);
 UPDATE public.health_ncd_screenings SET pulse=p_pulse WHERE id=v_row.id RETURNING * INTO v_row;
 UPDATE public.health_audit_log SET details=coalesce(details,'{}'::jsonb)||jsonb_build_object('pulse',p_pulse)
 WHERE operator_id=auth.uid() AND entity='health_ncd_screening' AND entity_id=v_row.id::text;
 RETURN v_row;
END; $function$;
REVOKE ALL ON FUNCTION public.save_health_ncd_screening_v6(text,bigint,date,numeric,numeric,numeric,integer,integer,integer,text,boolean,text,text,text,text,uuid,boolean,boolean,integer,integer,integer) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.save_health_ncd_screening_v6(text,bigint,date,numeric,numeric,numeric,integer,integer,integer,text,boolean,text,text,text,text,uuid,boolean,boolean,integer,integer,integer) TO authenticated, service_role;
CREATE OR REPLACE VIEW public.field_export_ncd_v200 WITH (security_invoker=true) AS
 SELECT s.id,
    s.screened_on,
    s.recorded_at,
    s.source_pcucode,
    s.source_pid,
    p.display_name,
    h.hcode,
    h.house_no,
    h.moo,
    h.community,
    h.volunteer_pid,
    s.weight_kg,
    s.height_cm,
    s.waist_cm,
    s.bmi,
    s.sbp,
    s.dbp,
    s.glucose_mg_dl,
    s.glucose_type,
    s.ncd_status,
    s.severity,
    s.bp_status,
    s.glucose_status,
    s.mental_2q_status,
    s.mental_2q_result,
    s.cvd_risk_percent,
    s.cvd_risk_level,
    s.record_mode,
    s.calculation_version,
    s.pulse
   FROM ((health_ncd_screenings s
     JOIN health_persons p ON (((p.source_pcucode = s.source_pcucode) AND (p.source_pid = s.source_pid))))
     JOIN houses h ON (((h.source_pcucode = s.house_pcucode) AND (h.hcode = s.hcode))));
CREATE OR REPLACE VIEW public.health_ncd_history WITH (security_invoker=true) AS
 SELECT (s.id)::text AS id,
    s.screened_on,
    s.source_pcucode,
    s.source_pid,
    p.display_name,
    p.gender,
    p.birth_date,
    s.hcode,
    h.house_no,
    h.moo,
    h.community,
    s.weight_kg,
    s.height_cm,
    s.waist_cm,
    s.bmi,
    s.sbp,
    s.dbp,
    s.glucose_mg_dl,
    s.glucose_type,
    s.smoking_frequency,
    s.alcohol_frequency,
    s.exercise_frequency,
    s.ncd_status,
    s.severity,
    s.bp_status,
    s.glucose_status,
    s.advice,
        CASE
            WHEN (s.record_mode = 'test'::text) THEN 'อสม. พลัส · ทดสอบ'::text
            ELSE 'อสม. พลัส'::text
        END AS source_label,
    true AS quality_valid,
    '{}'::text[] AS quality_issues,
    ''::text AS legacy_cvd_risk,
    s.recorded_at,
    s.mental_2q_q1,
    s.mental_2q_q2,
    s.mental_2q_status,
    s.mental_2q_result,
    s.cvd_risk_percent,
    s.cvd_risk_level,
    s.cvd_risk_eligible,
    s.cvd_risk_reason,
    s.cvd_model_version,
    s.pulse
   FROM ((health_ncd_screenings s
     JOIN health_persons p ON (((p.source_pcucode = s.source_pcucode) AND (p.source_pid = s.source_pid))))
     JOIN houses h ON (((h.source_pcucode = s.house_pcucode) AND (h.hcode = s.hcode))));
CREATE OR REPLACE VIEW public.health_ncd_latest WITH (security_invoker=true) AS
 SELECT DISTINCT ON (source_pcucode, source_pid) id,
    source_pcucode,
    source_pid,
    house_pcucode,
    hcode,
    screened_on,
    weight_kg,
    height_cm,
    waist_cm,
    sbp,
    dbp,
    glucose_mg_dl,
    glucose_type,
    danger_symptoms,
    smoker,
    alcohol_risk,
    exercise_sufficient,
    known_ncd,
    bmi,
    waist_risk,
    bp_status,
    glucose_status,
    ncd_status,
    severity,
    advice,
    note,
    calculation_version,
    request_id,
    recorded_by,
    recorded_at,
    smoking_frequency,
    alcohol_frequency,
    exercise_frequency,
    pulse
   FROM health_ncd_screenings
  ORDER BY source_pcucode, source_pid, screened_on DESC, recorded_at DESC;
CREATE OR REPLACE VIEW public.health_ncd_latest_production WITH (security_invoker=true) AS
 SELECT DISTINCT ON (source_pcucode, source_pid) id,
    source_pcucode,
    source_pid,
    house_pcucode,
    hcode,
    screened_on,
    weight_kg,
    height_cm,
    waist_cm,
    sbp,
    dbp,
    glucose_mg_dl,
    glucose_type,
    danger_symptoms,
    smoker,
    alcohol_risk,
    exercise_sufficient,
    known_ncd,
    bmi,
    waist_risk,
    bp_status,
    glucose_status,
    ncd_status,
    severity,
    advice,
    note,
    calculation_version,
    request_id,
    recorded_by,
    recorded_at,
    smoking_frequency,
    alcohol_frequency,
    exercise_frequency,
    record_mode,
    pulse
   FROM health_ncd_screenings
  WHERE (record_mode = 'production'::text)
  ORDER BY source_pcucode, source_pid, screened_on DESC, recorded_at DESC;
NOTIFY pgrst, 'reload schema';
