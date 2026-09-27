-- Reset policy v2141: "Reset" means Cloud app-screening results only.
-- No JHCIS, J-Report, Local operational/master, house/person/volunteer/profile or LINE data is modified.
begin;

create or replace function public.admin_cloud_app_screening_reset_preview_v2141()
returns jsonb
language plpgsql
stable
security definer
set search_path=''
as $$
begin
  if auth.uid() is null or private.current_role()<>'admin' then
    raise exception 'ADMIN_REQUIRED';
  end if;

  return jsonb_build_object(
    'policy','cloud_app_screenings_only',
    'go_live_date','2026-10-01',
    'reset_open',current_date<date '2026-10-01',
    'sessions',(select count(*) from public.screening_sessions where screening_date<date '2026-10-01'),
    'ncd_test',(select count(*) from public.health_ncd_screenings where record_mode='test'),
    'growth',(select count(*) from public.health_growth_screenings g join public.screening_sessions s on s.id=g.session_id where s.screening_date<date '2026-10-01'),
    'child_development',(select count(*) from public.child_development_screenings d join public.screening_sessions s on s.id=d.session_id where s.screening_date<date '2026-10-01'),
    'mental_2q',(select count(*) from public.mental_health_2q_screenings_v206 m join public.screening_sessions s on s.id=m.session_id where s.screening_date<date '2026-10-01'),
    'elderly_domains',(select count(*) from public.elderly9_domain_results r join public.screening_sessions s on s.id=r.session_id where s.screening_date<date '2026-10-01'),
    'followups',(select count(*) from public.screening_followups f join public.screening_sessions s on s.id=f.session_id where s.screening_date<date '2026-10-01'),
    'archive_rows',(select count(*) from public.screening_test_reset_archive_v208),
    'retained',jsonb_build_array(
      'health_persons','houses','volunteers','profiles','LINE links',
      'JHCIS','J-Report','3Doctor','health_ncd_legacy_screenings'
    )
  );
end;
$$;

revoke all on function public.admin_cloud_app_screening_reset_preview_v2141() from public,anon;
grant execute on function public.admin_cloud_app_screening_reset_preview_v2141() to authenticated;

create or replace function public.admin_reset_cloud_app_screenings_v2141(p_reason text)
returns jsonb
language plpgsql
security definer
set search_path=''
as $$
declare
  v_result jsonb;
begin
  if auth.uid() is null or private.current_role()<>'admin' then
    raise exception 'ADMIN_REQUIRED';
  end if;

  v_result:=public.admin_reset_all_test_screenings_v208(p_reason);

  return coalesce(v_result,'{}'::jsonb) || jsonb_build_object(
    'policy','cloud_app_screenings_only',
    'master_data_modified',false,
    'jhcis_modified',false,
    'jreport_modified',false,
    'local_operational_modified',false,
    'legacy_screening_modified',false
  );
end;
$$;

revoke all on function public.admin_reset_cloud_app_screenings_v2141(text) from public,anon;
grant execute on function public.admin_reset_cloud_app_screenings_v2141(text) to authenticated;

-- Disable the old service-role NCD-only bulk reset so there is only one bulk-reset meaning.
revoke execute on function public.admin_reset_health_test_screenings(text) from service_role;
comment on function public.admin_reset_health_test_screenings(text) is
  'Deprecated v2141: NCD-only bulk reset disabled. Use admin_reset_cloud_app_screenings_v2141 for Cloud app-screening reset.';

comment on function public.admin_reset_cloud_app_screenings_v2141(text) is
  'Admin-only pre-go-live reset of screening results created through the Cloud app. Archives before delete; does not modify master/source data.';

insert into public.app_settings(key,value)
values(
  'reset_policy_v2141',
  jsonb_build_object(
    'version','2.1.41',
    'meaning','cloud_app_screenings_only',
    'go_live_date','2026-10-01',
    'bulk_rpc','admin_reset_cloud_app_screenings_v2141',
    'preview_rpc','admin_cloud_app_screening_reset_preview_v2141',
    'archive_before_delete',true,
    'reset_local_database',false,
    'reset_jhcis',false,
    'reset_jreport',false,
    'reset_house_person_volunteer',false,
    'reset_accounts_line',false,
    'preserve_legacy_screenings',true
  )
)
on conflict(key) do update set value=excluded.value,updated_at=now();

notify pgrst,'reload schema';
commit;
