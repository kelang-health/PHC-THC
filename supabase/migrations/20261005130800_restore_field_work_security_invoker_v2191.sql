-- Restore original security-invoker behavior for field_work_items_v200
-- after replacing the view definition in v2.1.90.

begin;

alter view public.field_work_items_v200 set (security_invoker=true);

insert into public.app_settings(key,value)
values(
  'field_work_security_invoker_v2191',
  jsonb_build_object(
    'version','2.1.91',
    'security_invoker',true,
    'reason','preserve original RLS execution semantics after canonical NCD view replacement'
  )
)
on conflict(key) do update
set value=excluded.value,updated_at=now();

notify pgrst,'reload schema';

commit;
