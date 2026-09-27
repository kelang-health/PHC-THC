-- OSM-PHC v2.0.4 growth reference self-check.
-- Fails deployment if the version-locked DOH/JHCIS reference is incomplete or produces unexpected normal-band results.
begin;

do $$
declare
  j jsonb;
  v_age_count integer;
  v_wh_count integer;
begin
  select count(*) into v_age_count from private.growth_age_reference_v204 where reference_version='DOH-JHCIS-GROWTH-2026.09.12';
  select count(*) into v_wh_count from private.growth_wh_reference_v204 where reference_version='DOH-JHCIS-GROWTH-2026.09.12';
  if v_age_count<>868 then raise exception 'GROWTH_AGE_REFERENCE_COUNT_MISMATCH:%',v_age_count; end if;
  if v_wh_count<>666 then raise exception 'GROWTH_WH_REFERENCE_COUNT_MISMATCH:%',v_wh_count; end if;

  -- Male 12 months, 10 kg, 75 cm: JHCIS nutri_cal returns normal band (level 3) for W/A, H/A and W/H.
  j:=private.growth_interpret_v204(12,'เธเธฒเธข',10.0,75.0);
  if (j#>>'{weight_for_age,level}')::integer<>3
     or (j#>>'{height_for_age,level}')::integer<>3
     or (j#>>'{weight_for_height,level}')::integer<>3
     or j->>'overall_code'<>'good_growth' then
    raise exception 'GROWTH_SELFCHECK_12M_FAILED:%',j;
  end if;

  -- Male 72 months, 22 kg, 115 cm: school-age policy must use H/A + W/H and remain in normal band.
  j:=private.growth_interpret_v204(72,'เธเธฒเธข',22.0,115.0);
  if j ? 'weight_for_age'
     or (j#>>'{height_for_age,level}')::integer<>3
     or (j#>>'{weight_for_height,level}')::integer<>3
     or j->>'overall_code'<>'good_growth' then
    raise exception 'GROWTH_SELFCHECK_72M_FAILED:%',j;
  end if;

  -- Female 120 months, 30 kg, 136 cm: JHCIS reference returns normal H/A and W/H.
  j:=private.growth_interpret_v204(120,'เธซเธเธดเธ',30.0,136.0);
  if (j#>>'{height_for_age,level}')::integer<>3
     or (j#>>'{weight_for_height,level}')::integer<>3 then
    raise exception 'GROWTH_SELFCHECK_120M_FAILED:%',j;
  end if;
end $$;

commit;
