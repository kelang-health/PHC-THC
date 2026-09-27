-- OSM-PHC Cloud v2.0.1
-- Admin LINE linkage UI support + passwordless LINE login device-code flow.
-- LINE user IDs remain encrypted/hashed in user_line_links; login grants are short-lived and private.

begin;

create table if not exists private.line_login_requests_v201 (
  id uuid primary key default extensions.gen_random_uuid(),
  code_hash text not null unique,
  browser_secret_hash text not null,
  status text not null default 'pending' check (status in ('pending','approved','issuing','consumed','expired')),
  app_user_id uuid references auth.users(id) on delete cascade,
  created_at timestamptz not null default now(),
  expires_at timestamptz not null,
  approved_at timestamptz,
  issuing_at timestamptz,
  consumed_at timestamptz
);

create index if not exists line_login_requests_v201_expiry_idx on private.line_login_requests_v201(expires_at,status);

revoke all on private.line_login_requests_v201 from public,anon,authenticated;

create or replace function public.line_login_start_v201()
returns jsonb
language plpgsql security definer
set search_path=''
as $$
declare
  v_code text;
  v_secret text;
  v_id uuid;
begin
  if auth.role()<>'service_role' then raise exception 'SERVICE_ROLE_REQUIRED'; end if;

  update private.line_login_requests_v201
     set status='expired'
   where status in ('pending','approved','issuing') and expires_at<=now();
  delete from private.line_login_requests_v201
   where created_at < now()-interval '1 day';

  v_code:=upper(substr(replace(extensions.gen_random_uuid()::text,'-',''),1,8));
  v_secret:=replace(extensions.gen_random_uuid()::text,'-','')||replace(extensions.gen_random_uuid()::text,'-','');

  insert into private.line_login_requests_v201(code_hash,browser_secret_hash,expires_at)
  values(
    private.cid_hash_v190('LINELOGIN:'||v_code),
    private.cid_hash_v190('LINELOGINSECRET:'||v_secret),
    now()+interval '3 minutes'
  ) returning id into v_id;

  return jsonb_build_object(
    'request_id',v_id,
    'code',v_code,
    'browser_secret',v_secret,
    'expires_at',now()+interval '3 minutes'
  );
end;
$$;

revoke all on function public.line_login_start_v201() from public,anon,authenticated;

grant execute on function public.line_login_start_v201() to service_role;

create or replace function public.line_login_approve_v201(p_code text,p_line_user_id text)
returns jsonb
language plpgsql security definer
set search_path=''
as $$
declare
  v_hash text;
  v_line_hash text;
  v_uid uuid;
  v_req private.line_login_requests_v201%rowtype;
  v_name text;
  v_role text;
begin
  if auth.role()<>'service_role' then raise exception 'SERVICE_ROLE_REQUIRED'; end if;
  if coalesce(length(btrim(p_line_user_id)),0)<5 then raise exception 'INVALID_LINE_USER_ID'; end if;

  v_line_hash:=private.cid_hash_v190('LINEID:'||btrim(p_line_user_id));
  select l.app_user_id,p.display_name,p.role
    into v_uid,v_name,v_role
  from public.user_line_links l
  join public.profiles p on p.user_id=l.app_user_id and p.active=true
  where l.line_user_hash=v_line_hash and l.active=true;
  if v_uid is null then raise exception 'LINE_NOT_REGISTERED'; end if;

  v_hash:=private.cid_hash_v190('LINELOGIN:'||upper(btrim(coalesce(p_code,''))));
  select * into v_req
  from private.line_login_requests_v201
  where code_hash=v_hash and status='pending' and expires_at>now()
  for update;
  if not found then raise exception 'LOGIN_CODE_INVALID_OR_EXPIRED'; end if;

  update private.line_login_requests_v201
     set status='approved',app_user_id=v_uid,approved_at=now()
   where id=v_req.id;

  insert into public.health_audit_log(operator_id,action,entity,entity_id,severity,details)
  values(v_uid,'LINE_LOGIN_APPROVE','line_login',v_req.id::text,'audit',jsonb_build_object('role',v_role));

  return jsonb_build_object('ok',true,'request_id',v_req.id,'display_name',v_name,'role',v_role);
end;
$$;

revoke all on function public.line_login_approve_v201(text,text) from public,anon,authenticated;

grant execute on function public.line_login_approve_v201(text,text) to service_role;

create or replace function public.line_login_claim_v201(p_request_id uuid,p_browser_secret text)
returns jsonb
language plpgsql security definer
set search_path=''
as $$
declare
  v private.line_login_requests_v201%rowtype;
  v_secret_hash text;
begin
  if auth.role()<>'service_role' then raise exception 'SERVICE_ROLE_REQUIRED'; end if;
  v_secret_hash:=private.cid_hash_v190('LINELOGINSECRET:'||coalesce(p_browser_secret,''));

  select * into v from private.line_login_requests_v201 where id=p_request_id for update;
  if not found then return jsonb_build_object('status','not_found'); end if;
  if v.browser_secret_hash<>v_secret_hash then raise exception 'LOGIN_BROWSER_SECRET_INVALID'; end if;

  if v.expires_at<=now() then
    update private.line_login_requests_v201 set status='expired' where id=v.id and status<>'consumed';
    return jsonb_build_object('status','expired');
  end if;
  if v.status='pending' then return jsonb_build_object('status','pending'); end if;
  if v.status='consumed' then return jsonb_build_object('status','consumed'); end if;
  if v.status='issuing' and v.issuing_at>now()-interval '30 seconds' then return jsonb_build_object('status','pending'); end if;
  if v.status not in ('approved','issuing') or v.app_user_id is null then return jsonb_build_object('status',v.status); end if;

  update private.line_login_requests_v201 set status='issuing',issuing_at=now() where id=v.id;
  return jsonb_build_object('status','approved','app_user_id',v.app_user_id);
end;
$$;

revoke all on function public.line_login_claim_v201(uuid,text) from public,anon,authenticated;

grant execute on function public.line_login_claim_v201(uuid,text) to service_role;

create or replace function public.line_login_finish_v201(p_request_id uuid,p_ok boolean)
returns void
language plpgsql security definer
set search_path=''
as $$
begin
  if auth.role()<>'service_role' then raise exception 'SERVICE_ROLE_REQUIRED'; end if;
  if p_ok then
    update private.line_login_requests_v201
       set status='consumed',consumed_at=now()
     where id=p_request_id and status='issuing';
  else
    update private.line_login_requests_v201
       set status=case when expires_at>now() then 'approved' else 'expired' end,
           issuing_at=null
     where id=p_request_id and status='issuing';
  end if;
end;
$$;

revoke all on function public.line_login_finish_v201(uuid,boolean) from public,anon,authenticated;

grant execute on function public.line_login_finish_v201(uuid,boolean) to service_role;

insert into public.app_settings(key,value)
values('line_login_v201',jsonb_build_object(
  'version','2.0.1',
  'enabled',true,
  'channel','existing_ncd_line_oa',
  'expires_minutes',3,
  'requires_existing_line_link',true,
  'supabase_auth_remains_source_of_truth',true,
  'raw_line_user_id_exported',false
)) on conflict(key) do update set value=excluded.value,updated_at=now();

commit;
