-- OSM-PHC Cloud v2.0.12
-- One-tap LINE Login via LINE Login OAuth/OpenID Connect for accounts already linked in user_line_links.
-- Supabase Auth/profile remains the source of truth. LINE only proves ownership of the linked LINE account.

begin;

create table if not exists private.line_oauth_requests_v2012 (
  id uuid primary key default extensions.gen_random_uuid(),
  state_hash text not null unique,
  browser_secret_hash text not null,
  nonce_hash text not null,
  status text not null default 'pending' check (status in ('pending','approved','issuing','consumed','expired','failed')),
  app_user_id uuid references auth.users(id) on delete cascade,
  created_at timestamptz not null default now(),
  expires_at timestamptz not null,
  approved_at timestamptz,
  issuing_at timestamptz,
  consumed_at timestamptz,
  failed_at timestamptz,
  failure_code text not null default ''
);

create index if not exists line_oauth_requests_v2012_expiry_idx on private.line_oauth_requests_v2012(expires_at,status);

revoke all on private.line_oauth_requests_v2012 from public,anon,authenticated;

create or replace function public.line_oauth_start_v2012(
  p_state text,
  p_browser_secret text,
  p_nonce text
) returns jsonb
language plpgsql security definer
set search_path=''
as $$
declare v_id uuid; v_exp timestamptz:=now()+interval '5 minutes';
begin
  if auth.role()<>'service_role' then raise exception 'SERVICE_ROLE_REQUIRED'; end if;
  if length(coalesce(p_state,''))<32 or length(coalesce(p_browser_secret,''))<32 or length(coalesce(p_nonce,''))<16 then
    raise exception 'INVALID_OAUTH_ENTROPY';
  end if;
  update private.line_oauth_requests_v2012 set status='expired'
   where status in ('pending','approved','issuing') and expires_at<=now();
  delete from private.line_oauth_requests_v2012 where created_at<now()-interval '1 day';
  insert into private.line_oauth_requests_v2012(state_hash,browser_secret_hash,nonce_hash,expires_at)
  values(
    private.cid_hash_v190('LINEOAUTHSTATE:'||p_state),
    private.cid_hash_v190('LINEOAUTHSECRET:'||p_browser_secret),
    private.cid_hash_v190('LINEOAUTHNONCE:'||p_nonce),
    v_exp
  ) returning id into v_id;
  return jsonb_build_object('request_id',v_id,'expires_at',v_exp);
end;
$$;

revoke all on function public.line_oauth_start_v2012(text,text,text) from public,anon,authenticated;

grant execute on function public.line_oauth_start_v2012(text,text,text) to service_role;

create or replace function public.line_oauth_approve_v2012(
  p_state text,
  p_line_user_id text,
  p_nonce text
) returns jsonb
language plpgsql security definer
set search_path=''
as $$
declare
  v_state_hash text;
  v_nonce_hash text;
  v_line_hash text;
  v_uid uuid;
  v_req private.line_oauth_requests_v2012%rowtype;
  v_name text;
  v_role text;
begin
  if auth.role()<>'service_role' then raise exception 'SERVICE_ROLE_REQUIRED'; end if;
  if coalesce(length(btrim(p_line_user_id)),0)<5 then raise exception 'INVALID_LINE_USER_ID'; end if;
  v_state_hash:=private.cid_hash_v190('LINEOAUTHSTATE:'||coalesce(p_state,''));
  v_nonce_hash:=private.cid_hash_v190('LINEOAUTHNONCE:'||coalesce(p_nonce,''));
  select * into v_req from private.line_oauth_requests_v2012
   where state_hash=v_state_hash and status='pending' and expires_at>now() for update;
  if not found then raise exception 'OAUTH_STATE_INVALID_OR_EXPIRED'; end if;
  if v_req.nonce_hash<>v_nonce_hash then raise exception 'OAUTH_NONCE_INVALID'; end if;

  v_line_hash:=private.cid_hash_v190('LINEID:'||btrim(p_line_user_id));
  select l.app_user_id,p.display_name,p.role into v_uid,v_name,v_role
    from public.user_line_links l
    join public.profiles p on p.user_id=l.app_user_id and p.active=true
   where l.line_user_hash=v_line_hash and l.active=true;
  if v_uid is null then raise exception 'LINE_NOT_REGISTERED'; end if;

  update private.line_oauth_requests_v2012
     set status='approved',app_user_id=v_uid,approved_at=now()
   where id=v_req.id;
  insert into public.health_audit_log(operator_id,action,entity,entity_id,severity,details)
  values(v_uid,'LINE_OAUTH_LOGIN_APPROVE','line_oauth_login',v_req.id::text,'audit',jsonb_build_object('role',v_role,'method','openid_connect'));
  return jsonb_build_object('ok',true,'request_id',v_req.id,'app_user_id',v_uid,'display_name',v_name,'role',v_role);
end;
$$;

revoke all on function public.line_oauth_approve_v2012(text,text,text) from public,anon,authenticated;

grant execute on function public.line_oauth_approve_v2012(text,text,text) to service_role;

create or replace function public.line_oauth_fail_v2012(p_state text,p_failure_code text default 'oauth_failed')
returns void
language plpgsql security definer
set search_path=''
as $$
begin
  if auth.role()<>'service_role' then raise exception 'SERVICE_ROLE_REQUIRED'; end if;
  update private.line_oauth_requests_v2012
     set status='failed',failed_at=now(),failure_code=left(coalesce(p_failure_code,'oauth_failed'),80)
   where state_hash=private.cid_hash_v190('LINEOAUTHSTATE:'||coalesce(p_state,''))
     and status='pending';
end;
$$;

revoke all on function public.line_oauth_fail_v2012(text,text) from public,anon,authenticated;

grant execute on function public.line_oauth_fail_v2012(text,text) to service_role;

create or replace function public.line_oauth_claim_v2012(p_request_id uuid,p_browser_secret text)
returns jsonb
language plpgsql security definer
set search_path=''
as $$
declare v private.line_oauth_requests_v2012%rowtype; v_secret_hash text;
begin
  if auth.role()<>'service_role' then raise exception 'SERVICE_ROLE_REQUIRED'; end if;
  v_secret_hash:=private.cid_hash_v190('LINEOAUTHSECRET:'||coalesce(p_browser_secret,''));
  select * into v from private.line_oauth_requests_v2012 where id=p_request_id for update;
  if not found then return jsonb_build_object('status','not_found'); end if;
  if v.browser_secret_hash<>v_secret_hash then raise exception 'OAUTH_BROWSER_SECRET_INVALID'; end if;
  if v.expires_at<=now() then
    update private.line_oauth_requests_v2012 set status='expired' where id=v.id and status<>'consumed';
    return jsonb_build_object('status','expired');
  end if;
  if v.status in ('pending','failed','expired','consumed') then return jsonb_build_object('status',v.status,'failure_code',v.failure_code); end if;
  if v.status='issuing' and v.issuing_at>now()-interval '30 seconds' then return jsonb_build_object('status','pending'); end if;
  if v.status not in ('approved','issuing') or v.app_user_id is null then return jsonb_build_object('status',v.status); end if;
  update private.line_oauth_requests_v2012 set status='issuing',issuing_at=now() where id=v.id;
  return jsonb_build_object('status','approved','app_user_id',v.app_user_id);
end;
$$;

revoke all on function public.line_oauth_claim_v2012(uuid,text) from public,anon,authenticated;

grant execute on function public.line_oauth_claim_v2012(uuid,text) to service_role;

create or replace function public.line_oauth_finish_v2012(p_request_id uuid,p_ok boolean)
returns void
language plpgsql security definer
set search_path=''
as $$
begin
  if auth.role()<>'service_role' then raise exception 'SERVICE_ROLE_REQUIRED'; end if;
  if p_ok then
    update private.line_oauth_requests_v2012 set status='consumed',consumed_at=now() where id=p_request_id and status='issuing';
  else
    update private.line_oauth_requests_v2012 set status=case when expires_at>now() then 'approved' else 'expired' end,issuing_at=null
     where id=p_request_id and status='issuing';
  end if;
end;
$$;

revoke all on function public.line_oauth_finish_v2012(uuid,boolean) from public,anon,authenticated;

grant execute on function public.line_oauth_finish_v2012(uuid,boolean) to service_role;

insert into public.app_settings(key,value)
values('line_oauth_v2012',jsonb_build_object(
  'version','2.0.12',
  'enabled_when_secrets_present',true,
  'requires_existing_line_link',true,
  'source_of_truth','Supabase Auth + profiles',
  'line_identity_match','user_line_links.line_user_hash',
  'browser_secret','one-time, 5 minutes, sessionStorage only',
  'fallback','LINE OA device-code login v2.0.1',
  'raw_line_user_id_browser_exposed',false
)) on conflict(key) do update set value=excluded.value,updated_at=now();

commit;
