create table if not exists private.linehub_notification_ingress_v1 (
  dedupe_key text primary key,
  notification_id uuid references public.notifications(id) on delete cascade,
  created_at timestamptz not null default now(),
  check (length(dedupe_key) between 1 and 180)
);

revoke all on table private.linehub_notification_ingress_v1 from public, anon, authenticated;

create or replace function public.linehub_admin_notification_v1(
  p_dedupe_key text,
  p_severity text,
  p_title text,
  p_body text
) returns jsonb
language plpgsql
security definer
set search_path=''
as $$
declare
  v_id uuid;
  v_inserted boolean;
begin
  if auth.role() <> 'service_role' then
    raise exception 'SERVICE_ROLE_REQUIRED';
  end if;
  if p_dedupe_key is null or length(p_dedupe_key) not between 1 and 180 then
    raise exception 'INVALID_DEDUPE_KEY';
  end if;
  if not private.safe_notification_text_v190(p_title)
     or not private.safe_notification_text_v190(p_body) then
    raise exception 'UNSAFE_NOTIFICATION_CONTENT';
  end if;

  insert into private.linehub_notification_ingress_v1(dedupe_key)
  values (p_dedupe_key)
  on conflict (dedupe_key) do nothing;
  v_inserted := found;

  if not v_inserted then
    select notification_id into v_id
      from private.linehub_notification_ingress_v1
     where dedupe_key = p_dedupe_key;
    return jsonb_build_object('ok',true,'duplicate',true,'notification_id',v_id);
  end if;

  v_id := private.emit_admin_notification_v190(
    'linehub.notice',
    case when p_severity in ('info','warning','critical') then p_severity else 'warning' end,
    left(coalesce(p_title,'[LINE HUB] แจ้งเตือน'),160),
    left(coalesce(p_body,''),500),
    '',
    jsonb_build_object('source','line-service-hub','dedupe_key',p_dedupe_key),
    true
  );

  update private.linehub_notification_ingress_v1
     set notification_id = v_id
   where dedupe_key = p_dedupe_key;

  return jsonb_build_object('ok',true,'duplicate',false,'notification_id',v_id);
end;
$$;

revoke all on function public.linehub_admin_notification_v1(text,text,text,text)
  from public, anon, authenticated;
grant execute on function public.linehub_admin_notification_v1(text,text,text,text)
  to service_role;