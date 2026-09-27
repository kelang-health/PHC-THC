
create table if not exists private.login_lock_pid_map_v2068 (
 login_hash text primary key check (login_hash ~ '^[a-f0-9]{64}$'),
 volunteer_pid bigint,
 updated_at timestamptz not null default now()
);
revoke all on private.login_lock_pid_map_v2068 from public,anon,authenticated;
-- Only service_role on the public RPC may bind an attempted login to an existing auth account.
create or replace function public.security_bind_lock_pid_v2068(
 p_login_hash text,
 p_email text
)
returns boolean
language plpgsql
security definer
set search_path=''
as $$
declare
 v_pid bigint;
begin
 if auth.role()<>'service_role' then
   raise exception 'SERVICE_ROLE_REQUIRED';
 end if;
 if p_login_hash is null or p_login_hash !~ '^[a-f0-9]{64}$'
    or p_email is null or length(p_email)>320 or length(btrim(p_email))=0 then
   raise exception 'INVALID_LOOKUP';
 end if;

 select p.volunteer_pid into v_pid
 from auth.users u
 join public.profiles p on p.user_id=u.id
 where lower(u.email)=lower(btrim(p_email))
   and p.role in ('user','staff')
   and p.volunteer_pid is not null
 limit 1;

 insert into private.login_lock_pid_map_v2068(login_hash,volunteer_pid,updated_at)
 values(p_login_hash,v_pid,now())
 on conflict(login_hash) do update set
   volunteer_pid=excluded.volunteer_pid,
   updated_at=now();

 return v_pid is not null;
end;
$$;

revoke all on function public.security_bind_lock_pid_v2068(text,text) from public,anon,authenticated;
grant execute on function public.security_bind_lock_pid_v2068(text,text) to service_role;

create or replace function private.notify_login_lock_v2066()
returns trigger
language plpgsql
security definer
set search_path=''
as $$
declare
 v_pid bigint;
 v_body text;
begin
 if new.locked_until is not null
    and new.locked_until>now()
    and (tg_op='INSERT' or old.locked_until is distinct from new.locked_until) then

   select m.volunteer_pid into v_pid
   from private.login_lock_pid_map_v2068 m
   where m.login_hash=new.login_hash;

   v_body:=case
     when v_pid is not null then
       format('PID เธเธฑเธเธเธตเน€เธเนเธฒเธซเธกเธฒเธข: %s ยท เธ–เธนเธเธฅเนเธญเธเธเธฑเนเธงเธเธฃเธฒเธงเธซเธฅเธฑเธ Login เธเธดเธ” %s เธเธฃเธฑเนเธ (เนเธกเนเธขเธทเธเธขเธฑเธเธงเนเธฒเน€เธเนเธฒเธเธญเธเธเธฑเธเธเธตเน€เธเนเธเธเธนเนเธเธขเธฒเธขเธฒเธกเน€เธเนเธฒ)',v_pid,new.failed_attempts)
     else
       format('PID เธเธฑเธเธเธตเน€เธเนเธฒเธซเธกเธฒเธข: เนเธกเนเธเธเนเธเธ—เธฐเน€เธเธตเธขเธ Cloud ยท เธ–เธนเธเธฅเนเธญเธเธเธฑเนเธงเธเธฃเธฒเธงเธซเธฅเธฑเธ Login เธเธดเธ” %s เธเธฃเธฑเนเธ',new.failed_attempts)
   end;

   perform private.emit_admin_notification_v190(
     'security.login_lock',
     'alert',
     '๐  เธเธฑเธเธเธตเธ–เธนเธเธฅเนเธญเธเธเธฒเธเธเธฒเธฃ Login เธเธดเธ”เธเนเธณ',
     v_body,
     '',
     jsonb_build_object(
       'volunteer_pid',v_pid,
       'failed_attempts',new.failed_attempts,
       'locked_until',new.locked_until,
       'pid_source','matched_auth_user_profile'
     ),
     true
   );
 end if;
 return new;
end;
$$;

revoke all on function private.notify_login_lock_v2066() from public,anon,authenticated;
