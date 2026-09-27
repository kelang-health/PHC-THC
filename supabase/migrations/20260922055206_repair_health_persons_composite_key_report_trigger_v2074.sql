CREATE OR REPLACE FUNCTION private.queue_report_snapshot_if_changed_v2074()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE v_changed boolean:=false;
BEGIN
  IF TG_OP='INSERT' THEN
    SELECT EXISTS(SELECT 1 FROM report_new_rows) INTO v_changed;
  ELSIF TG_OP='DELETE' THEN
    SELECT EXISTS(SELECT 1 FROM report_old_rows) INTO v_changed;
  ELSIF TG_OP='UPDATE' THEN
    IF TG_TABLE_NAME='houses' THEN
      SELECT EXISTS(
        SELECT 1 FROM report_new_rows n JOIN report_old_rows o USING(id)
        WHERE ROW(n.source_pcucode,n.hcode,n.community,n.latitude,n.longitude,n.volunteer_pid,n.review_required,n.superseded_by,n.verification_status)
          IS DISTINCT FROM ROW(o.source_pcucode,o.hcode,o.community,o.latitude,o.longitude,o.volunteer_pid,o.review_required,o.superseded_by,o.verification_status)
      ) INTO v_changed;
    ELSIF TG_TABLE_NAME='health_persons' THEN
      SELECT EXISTS(
        SELECT 1 FROM report_new_rows n FULL JOIN report_old_rows o
          ON n.source_pcucode=o.source_pcucode AND n.source_pid=o.source_pid
        WHERE n.source_pid IS NULL OR o.source_pid IS NULL
          OR ROW(n.source_pcucode,n.source_pid,n.house_pcucode,n.hcode,n.display_name,n.gender,n.birth_date,n.active,n.has_ht,n.has_dm,n.previous_screened_on,n.previous_weight_kg,n.previous_height_cm,n.previous_waist_cm,n.previous_sbp,n.previous_dbp,n.previous_glucose_mg_dl,n.previous_bmi,n.previous_source,n.ncd_base_eligible,n.jhcis_typelive,n.has_cvd,n.cvd_population_eligible,n.is_student,n.is_disabled,n.care_group_code,n.service_population_eligible,n.adl_group_code,n.adl_assessed_on,n.growth_previous_on,n.growth_previous_weight_kg,n.growth_previous_height_cm,n.growth_previous_source,n.growth_previous_synced_at)
          IS DISTINCT FROM ROW(o.source_pcucode,o.source_pid,o.house_pcucode,o.hcode,o.display_name,o.gender,o.birth_date,o.active,o.has_ht,o.has_dm,o.previous_screened_on,o.previous_weight_kg,o.previous_height_cm,o.previous_waist_cm,o.previous_sbp,o.previous_dbp,o.previous_glucose_mg_dl,o.previous_bmi,o.previous_source,o.ncd_base_eligible,o.jhcis_typelive,o.has_cvd,o.cvd_population_eligible,o.is_student,o.is_disabled,o.care_group_code,o.service_population_eligible,o.adl_group_code,o.adl_assessed_on,o.growth_previous_on,o.growth_previous_weight_kg,o.growth_previous_height_cm,o.growth_previous_source,o.growth_previous_synced_at)
      ) INTO v_changed;
    ELSIF TG_TABLE_NAME='volunteers' THEN
      SELECT EXISTS(
        SELECT 1 FROM report_new_rows n JOIN report_old_rows o USING(id)
        WHERE ROW(n.id,n.source_pcucode,n.source_pid,n.display_name,n.community,n.moo,n.active)
          IS DISTINCT FROM ROW(o.id,o.source_pcucode,o.source_pid,o.display_name,o.community,o.moo,o.active)
      ) INTO v_changed;
    ELSE
      RAISE EXCEPTION 'UNSUPPORTED_REPORT_SOURCE_%',TG_TABLE_NAME;
    END IF;
  END IF;
  IF v_changed THEN
    PERFORM private.enqueue_report_refresh_v2074(TG_TABLE_SCHEMA||'.'||TG_TABLE_NAME);
  END IF;
  RETURN NULL;
END;
$function$;
