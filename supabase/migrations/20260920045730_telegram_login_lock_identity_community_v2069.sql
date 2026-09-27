
alter table private.login_lock_pid_map_v2068
 add column if not exists app_user_id uuid;

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
 v_user_id uuid;
begin
 if auth.role()<>'service_role' then
   raise exception 'SERVICE_ROLE_REQUIRED';
 end if;
 if p_login_hash is null or p_login_hash !~ '^[a-f0-9]{64}$'
    or p_email is null or length(p_email)>320 or length(btrim(p_email))=0 then
   raise exception 'INVALID_LOOKUP';
 end if;

 select u.id,p.volunteer_pid into v_user_id,v_pid
 from auth.users u
 join public.profiles p on p.user_id=u.id
 where lower(u.email)=lower(btrim(p_email))
   and p.role in ('user','staff')
   and p.volunteer_pid is not null
 limit 1;

 insert into private.login_lock_pid_map_v2068(login_hash,app_user_id,volunteer_pid,updated_at)
 values(p_login_hash,v_user_id,v_pid,now())
 on conflict(login_hash) do update set
   app_user_id=excluded.app_user_id,
   volunteer_pid=excluded.volunteer_pid,
   updated_at=now();

 return v_user_id is not null and v_pid is not null;
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
 v_name text:='เนเธกเนเธเธเธเนเธญเธกเธนเธฅเนเธเธ—เธฐเน€เธเธตเธขเธ Cloud';
 v_community text:='เนเธกเนเธเธเธเนเธญเธกเธนเธฅเนเธเธ—เธฐเน€เธเธตเธขเธ Cloud';
 v_display_name text;
 v_profile_community text;
 v_body text;
begin
 if new.locked_until is not null
    and new.locked_until>now()
    and (tg_op='INSERT' or old.locked_until is distinct from new.locked_until) then

   select m.volunteer_pid,p.display_name,p.community
     into v_pid,v_display_name,v_profile_community
   from private.login_lock_pid_map_v2068 m
   left join public.profiles p
     on p.user_id=m.app_user_id
     and p.volunteer_pid=m.volunteer_pid
     and p.role in ('user','staff')
   where m.login_hash=new.login_hash;

   v_display_name:=nullif(btrim(left(regexp_replace(coalesce(v_display_name,''),'[[:cntrl:]]+',' ','g'),90)),'');
   v_profile_community:=nullif(btrim(left(regexp_replace(coalesce(v_profile_community,''),'[[:cntrl:]]+',' ','g'),90)),'');
   if v_display_name is not null and private.safe_notification_text_v190(v_display_name) then
     v_name:=v_display_name;
   end if;
   if v_profile_community is not null and private.safe_notification_text_v190(v_profile_community) then
     v_community:=v_profile_community;
   end if;

   v_body:=format(
     'เธเธทเนเธญเธเธฑเธเธเธต: %s | เธเธธเธกเธเธ: %s | PID: %s | Login เธเธดเธ”: %s เธเธฃเธฑเนเธ | เธฃเธฐเธขเธฐเน€เธงเธฅเธฒเธฅเนเธญเธ: 10 เธเธฒเธ—เธต | เธซเธกเธฒเธขเน€เธซเธ•เธธ: เน€เธเนเธเธเธฑเธเธเธตเธ—เธตเนเธ–เธนเธเธเธขเธฒเธขเธฒเธกเน€เธเนเธฒเธชเธนเนเธฃเธฐเธเธ เนเธกเนเธขเธทเธเธขเธฑเธเธงเนเธฒเน€เธเนเธฒเธเธญเธเธเธฑเธเธเธตเน€เธเนเธเธเธนเนเธเธฃเธญเธเธฃเธซเธฑเธชเธเธดเธ”เน€เธญเธ',
     v_name,
     v_community,
     coalesce(v_pid::text,'เนเธกเนเธเธเธเนเธญเธกเธนเธฅเนเธเธ—เธฐเน€เธเธตเธขเธ Cloud'),
     new.failed_attempts
   );

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
       'account_identity_source','authenticated_account_matched_to_profile'
     ),
     true
   );
 end if;
 return new;
end;
$$;

revoke all on function private.notify_login_lock_v2066() from public,anon,authenticated;
