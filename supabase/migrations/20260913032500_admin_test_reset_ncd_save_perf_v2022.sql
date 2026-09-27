-- Cloud v2.0.22
-- 1) Restrict person test-reset to Admin at the database contract.
-- 2) Add focused indexes used by NCD save audit enrichment and recent-history refresh.
-- JHCIS remains read-only.
begin;

create index if not exists health_audit_ncd_entity_lookup_v2022_idx
  on public.health_audit_log(operator_id, entity, entity_id);

create index if not exists health_ncd_recent_refresh_v2022_idx
  on public.health_ncd_screenings(screened_on desc, recorded_at desc);

create index if not exists health_ncd_production_person_recent_v2022_idx
  on public.health_ncd_screenings(source_pcucode, source_pid, screened_on desc, recorded_at desc)
  where record_mode='production';

-- The legacy RPC stays available only to database owners/service internals.
-- Browser users must go through the Admin-only wrapper below.
revoke execute on function public.reset_person_test_screening_v208(text,bigint,text,text) from authenticated;

create or replace function public.admin_reset_person_test_screening_v2022(
  p_source_pcucode text,
  p_source_pid bigint,
  p_route text default 'all',
  p_reason text default 'เธฃเธตเน€เธเธ—เธเนเธญเธกเธนเธฅเธ—เธ”เธชเธญเธเธเนเธญเธเน€เธเธดเธ”เนเธเนเธเธฃเธดเธ'
) returns jsonb
language plpgsql security definer
set search_path=''
as $$
begin
  if auth.uid() is null or private.current_role()<>'admin' then
    raise exception 'ADMIN_REQUIRED';
  end if;
  return public.reset_person_test_screening_v208(
    p_source_pcucode,p_source_pid,p_route,p_reason
  );
end;
$$;

revoke all on function public.admin_reset_person_test_screening_v2022(text,bigint,text,text) from public,anon;

grant execute on function public.admin_reset_person_test_screening_v2022(text,bigint,text,text) to authenticated;

comment on function public.admin_reset_person_test_screening_v2022(text,bigint,text,text) is
  'Admin-only pre-go-live person test reset. Source history from JHCIS/J-Report/3Doctor is preserved.';

insert into public.app_settings(key,value)
values('test_reset_v208',jsonb_build_object(
  'version','2.0.22','go_live_date','2026-10-01','pre_go_live_mode','test',
  'production_counting_before_go_live',false,'reset_visible_roles',jsonb_build_array('admin'),
  'person_reset_roles',jsonb_build_array('admin'),'admin_bulk_reset',true,
  'archive_before_delete',true,'preserve_source_history',jsonb_build_array('JHCIS','J-Report','3Doctor'),
  'jhcis_write_back',false
)) on conflict(key) do update set value=excluded.value,updated_at=now();

notify pgrst, 'reload schema';

commit;
