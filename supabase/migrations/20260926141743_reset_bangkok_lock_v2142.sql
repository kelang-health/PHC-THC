-- v2.1.42: Bangkok-time reset lock and single reset surface.
-- Reset remains Cloud app-screening only; source/master data is never modified.

begin;

create or replace function private.cloud_app_reset_open_v2142()
returns boolean
language sql
stable
security definer
set search_path=''
as $$
  select
    timezone('Asia/Bangkok', now()) < timestamp '2026-10-01 00:00:00'
    and not coalesce(
      (
        select (value->>'permanent_locked')::boolean
        from public.app_settings
        where key='reset_policy_v2142'
      ),
      false
    );
$$;

revoke all on function private.cloud_app_reset_open_v2142() from public,anon,authenticated;
grant execute on function private.cloud_app_reset_open_v2142() to service_role;

create or replace function public.admin_cloud_app_screening_reset_preview_v2142()
returns jsonb
language plpgsql
stable
security definer
set search_path=''
as $$
declare
  v_now_bkk timestamp:=timezone('Asia/Bangkok',now());
  v_locked boolean:=coalesce(
    (select (value->>'permanent_locked')::boolean
     from public.app_settings where key='reset_policy_v2142'),
    false
  );
begin
  if auth.uid() is null or private.current_role()<>'admin' then
    raise exception 'ADMIN_REQUIRED';
  end if;

  return jsonb_build_object(
    'policy','cloud_app_screenings_only',
    'timezone','Asia/Bangkok',
    'now_bangkok',v_now_bkk,
    'lock_after_bangkok','2026-10-01 00:00:00',
    'permanent_locked',v_locked,
    'reset_open',private.cloud_app_reset_open_v2142(),
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

revoke all on function public.admin_cloud_app_screening_reset_preview_v2142() from public,anon,service_role;
grant execute on function public.admin_cloud_app_screening_reset_preview_v2142() to authenticated;

create or replace function public.admin_reset_cloud_app_screenings_v2142(p_reason text)
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

  if not private.cloud_app_reset_open_v2142() then
    raise exception 'RESET_LOCKED_AFTER_GO_LIVE_BANGKOK';
  end if;

  v_result:=public.admin_reset_all_test_screenings_v208(p_reason);

  return coalesce(v_result,'{}'::jsonb) || jsonb_build_object(
    'policy','cloud_app_screenings_only',
    'timezone','Asia/Bangkok',
    'master_data_modified',false,
    'jhcis_modified',false,
    'jreport_modified',false,
    'local_operational_modified',false,
    'legacy_screening_modified',false
  );
end;
$$;

revoke all on function public.admin_reset_cloud_app_screenings_v2142(text) from public,anon,service_role;
grant execute on function public.admin_reset_cloud_app_screenings_v2142(text) to authenticated;

-- Remove bypasses: legacy bulk and per-person reset functions are internal/disabled to clients.
revoke execute on function public.admin_reset_all_test_screenings_v208(text) from authenticated,service_role;
revoke execute on function public.admin_reset_cloud_app_screenings_v2141(text) from authenticated,service_role;
revoke execute on function public.admin_cloud_app_screening_reset_preview_v2141() from authenticated,service_role;
revoke execute on function public.admin_reset_person_test_screening_v2022(text,bigint,text,text) from authenticated,service_role;
revoke execute on function public.reset_person_test_screening_v208(text,bigint,text,text) from authenticated,service_role;

insert into public.app_settings(key,value)
values(
  'reset_policy_v2142',
  jsonb_build_object(
    'version','2.1.42',
    'meaning','cloud_app_screenings_only',
    'timezone','Asia/Bangkok',
    'lock_after_bangkok','2026-10-01T00:00:00+07:00',
    'permanent_locked',false,
    'bulk_rpc','admin_reset_cloud_app_screenings_v2142',
    'preview_rpc','admin_cloud_app_screening_reset_preview_v2142',
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

create or replace function private.lock_cloud_app_reset_after_go_live_v2142()
returns jsonb
language plpgsql
security definer
set search_path=''
as $$
declare
  v_now_bkk timestamp:=timezone('Asia/Bangkok',now());
  v_changed boolean:=false;
begin
  if v_now_bkk >= timestamp '2026-10-01 00:00:00' then
    update public.app_settings
       set value=jsonb_set(value,'{permanent_locked}','true'::jsonb,true),
           updated_at=now()
     where key='reset_policy_v2142'
       and coalesce((value->>'permanent_locked')::boolean,false)=false;
    v_changed:=found;
  end if;

  return jsonb_build_object(
    'now_bangkok',v_now_bkk,
    'changed',v_changed,
    'permanent_locked',coalesce(
      (select (value->>'permanent_locked')::boolean
       from public.app_settings where key='reset_policy_v2142'),
      false
    )
  );
end;
$$;

revoke all on function private.lock_cloud_app_reset_after_go_live_v2142() from public,anon,authenticated;
grant execute on function private.lock_cloud_app_reset_after_go_live_v2142() to service_role;

select cron.unschedule(jobid)
from cron.job
where jobname='osm-phc-reset-permanent-lock-v2142';

select cron.schedule(
  'osm-phc-reset-permanent-lock-v2142',
  '5 17 * * *',
  $$select private.lock_cloud_app_reset_after_go_live_v2142();$$
);

notify pgrst,'reload schema';
commit;
