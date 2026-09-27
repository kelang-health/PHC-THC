
alter table private.login_lock_pid_map_v2068
 add column if not exists lookup_status text not null default 'legacy_unknown';

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
 v_profile_found boolean := false;
 v_status text;
begin
 if auth.role()<>'service_role' then
   raise exception 'SERVICE_ROLE_REQUIRED';
 end if;
 if p_login_hash is null or p_login_hash !~ '^[a-f0-9]{64}$'
    or p_email is null or length(p_email)>320 or length(btrim(p_email))=0 then
   raise exception 'INVALID_LOOKUP';
 end if;

 select u.id into v_user_id
 from auth.users u
 where lower(u.email)=lower(btrim(p_email))
 limit 1;

 if v_user_id is null then
   v_status:='auth_not_found';
 else
   select p.volunteer_pid,true into v_pid,v_profile_found
   from public.profiles p
   where p.user_id=v_user_id
   limit 1;
   v_status:=case when coalesce(v_profile_found,false) then 'profile_matched' else 'profile_not_found' end;
 end if;

 insert into private.login_lock_pid_map_v2068(
   login_hash,app_user_id,volunteer_pid,lookup_status,updated_at
 ) values (
   p_login_hash,v_user_id,v_pid,v_status,now()
 )
 on conflict(login_hash) do update set
   app_user_id=excluded.app_user_id,
   volunteer_pid=excluded.volunteer_pid,
   lookup_status=excluded.lookup_status,
   updated_at=now();

 return v_status='profile_matched';
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
 v_role text;
 v_status text:='lookup_unavailable';
 v_display_name text;
 v_profile_community text;
 v_body text;
 v_title text:='๐  เธเธฑเธเธเธตเธ–เธนเธเธฅเนเธญเธเธเธฒเธเธเธฒเธฃ Login เธเธดเธ”เธเนเธณ';
begin
 if new.locked_until is not null
    and new.locked_until>now()
    and (tg_op='INSERT' or old.locked_until is distinct from new.locked_until) then

   select m.volunteer_pid,m.lookup_status,p.display_name,p.community,p.role
     into v_pid,v_status,v_display_name,v_profile_community,v_role
   from private.login_lock_pid_map_v2068 m
   left join public.profiles p on p.user_id=m.app_user_id
   where m.login_hash=new.login_hash;

   if v_status='profile_matched' and v_role is not null then
     v_display_name:=nullif(btrim(left(regexp_replace(coalesce(v_display_name,''),'[[:cntrl:]]+',' ','g'),90)),'');
     v_profile_community:=nullif(btrim(left(regexp_replace(coalesce(v_profile_community,''),'[[:cntrl:]]+',' ','g'),90)),'');
     if v_display_name is not null and private.safe_notification_text_v190(v_display_name) then
       v_name:=v_display_name;
     end if;
     if v_profile_community is not null and private.safe_notification_text_v190(v_profile_community) then
       v_community:=v_profile_community;
     elsif v_role='admin' then
       v_community:='เธเธฑเธเธเธตเธเธนเนเธ”เธนเนเธฅเธฃเธฐเธเธ (เนเธกเนเธกเธตเธเธธเธกเธเธเธเธฃเธฐเธเธณ)';
     end if;
   end if;

   if v_status='auth_not_found' then
     v_title:='๐  เธเนเธญเธกเธนเธฅเน€เธเนเธฒเธชเธนเนเธฃเธฐเธเธเธ—เธตเนเนเธกเนเธ•เธฃเธเธเธฑเธเธเธฑเธเธเธตเธ–เธนเธเธฅเนเธญเธเธเธฑเนเธงเธเธฃเธฒเธง';
     v_body:=format(
       'เนเธกเนเธเธเธเธฑเธเธเธตเธ—เธตเนเธ•เธฃเธเธเธฑเธเธเนเธญเธกเธนเธฅเน€เธเนเธฒเธชเธนเนเธฃเธฐเธเธเนเธเธ—เธฐเน€เธเธตเธขเธ Auth ยท เธเนเธญเธกเธนเธฅเน€เธเนเธฒเธชเธนเนเธฃเธฐเธเธเธเธตเนเธ–เธนเธเธฃเธฐเธเธฑเธเธเธฑเนเธงเธเธฃเธฒเธงเธซเธฅเธฑเธเธฅเธญเธเธเธดเธ” %s เธเธฃเธฑเนเธ เน€เธเนเธเน€เธงเธฅเธฒ 10 เธเธฒเธ—เธต ยท เนเธกเนเธชเธฒเธกเธฒเธฃเธ–เธฃเธฐเธเธธเธเธทเนเธญ เธเธธเธกเธเธ เธซเธฃเธทเธญ PID เนเธ”เน เนเธฅเธฐเนเธกเนเธขเธทเธเธขเธฑเธเธ•เธฑเธงเธเธนเนเธเธขเธฒเธขเธฒเธกเน€เธเนเธฒ',
       new.failed_attempts
     );
   elsif v_status='profile_not_found' then
     v_body:=format(
       'เธเธเธเธฑเธเธเธต Auth เนเธ•เนเนเธกเนเธกเธตเนเธเธฃเนเธเธฅเนเนเธเธ—เธฐเน€เธเธตเธขเธ Cloud | เธเธทเนเธญเธเธฑเธเธเธต/เธเธธเธกเธเธ/PID: เนเธกเนเธเธเธเนเธญเธกเธนเธฅ | Login เธเธดเธ”: %s เธเธฃเธฑเนเธ | เธฃเธฐเธขเธฐเน€เธงเธฅเธฒเธฅเนเธญเธ: 10 เธเธฒเธ—เธต | เนเธกเนเธขเธทเธเธขเธฑเธเธงเนเธฒเน€เธเนเธฒเธเธญเธเธเธฑเธเธเธตเน€เธเนเธเธเธนเนเธเธขเธฒเธขเธฒเธกเน€เธเนเธฒ',
       new.failed_attempts
     );
   elsif v_status='profile_matched' then
     v_body:=format(
       'เธเธทเนเธญเธเธฑเธเธเธต: %s | เธเธธเธกเธเธ: %s | PID: %s | เธเธฃเธฐเน€เธ เธ—เธเธฑเธเธเธต: %s | Login เธเธดเธ”: %s เธเธฃเธฑเนเธ | เธฃเธฐเธขเธฐเน€เธงเธฅเธฒเธฅเนเธญเธ: 10 เธเธฒเธ—เธต | เธซเธกเธฒเธขเน€เธซเธ•เธธ: เน€เธเนเธเธเธฑเธเธเธตเธ—เธตเนเธ–เธนเธเธเธขเธฒเธขเธฒเธกเน€เธเนเธฒเธชเธนเนเธฃเธฐเธเธ เนเธกเนเธขเธทเธเธขเธฑเธเธงเนเธฒเน€เธเนเธฒเธเธญเธเธเธฑเธเธเธตเน€เธเนเธเธเธนเนเธเธฃเธญเธเธฃเธซเธฑเธชเธเธดเธ”เน€เธญเธ',
       v_name,v_community,
       case when v_pid is null and v_role='admin' then 'เนเธกเนเธกเธต PID (เธเธฑเธเธเธต admin)' else coalesce(v_pid::text,'เนเธกเนเธเธเธเนเธญเธกเธนเธฅเนเธเธ—เธฐเน€เธเธตเธขเธ Cloud') end,
       coalesce(v_role,'เนเธกเนเธ—เธฃเธฒเธ'),
       new.failed_attempts
     );
   else
     v_body:=format(
       'เนเธกเนเธชเธฒเธกเธฒเธฃเธ–เธเธฑเธเธเธนเนเธเนเธญเธกเธนเธฅเน€เธเนเธฒเธชเธนเนเธฃเธฐเธเธเธเธฑเธเธ—เธฐเน€เธเธตเธขเธ Cloud เนเธ”เน | Login เธเธดเธ”: %s เธเธฃเธฑเนเธ | เธฃเธฐเธขเธฐเน€เธงเธฅเธฒเธฅเนเธญเธ: 10 เธเธฒเธ—เธต | เนเธกเนเธขเธทเธเธขเธฑเธเธงเนเธฒเน€เธเนเธฒเธเธญเธเธเธฑเธเธเธตเน€เธเนเธเธเธนเนเธเธขเธฒเธขเธฒเธกเน€เธเนเธฒ',
       new.failed_attempts
     );
   end if;

   perform private.emit_admin_notification_v190(
     'security.login_lock',
     'alert',
     v_title,
     v_body,
     '',
     jsonb_build_object(
       'volunteer_pid',v_pid,
       'account_role',v_role,
       'lookup_status',coalesce(v_status,'lookup_unavailable'),
       'failed_attempts',new.failed_attempts,
       'locked_until',new.locked_until
     ),
     true
   );
 end if;
 return new;
end;
$$;

revoke all on function private.notify_login_lock_v2066() from public,anon,authenticated;
