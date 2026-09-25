begin;

create or replace function public.daily_community_usage_v2134()
returns jsonb
language plpgsql
security definer
set search_path=''
as $function$
declare
  v_day date := (now() at time zone 'Asia/Bangkok')::date;
  v_start timestamptz := ((now() at time zone 'Asia/Bangkok')::date::timestamp at time zone 'Asia/Bangkok');
  v_end timestamptz := (((now() at time zone 'Asia/Bangkok')::date + 1)::timestamp at time zone 'Asia/Bangkok');
  v_rows jsonb;
  v_unmapped integer:=0;
begin
  if auth.role()<>'service_role' then
    raise exception 'SERVICE_ROLE_REQUIRED';
  end if;

  with active_profiles as materialized (
    select p.user_id,p.role,p.community,private.community_key(p.community) as community_key
    from public.profiles p
    where p.active=true and p.role in ('user','staff')
  ),
  line_links as materialized (
    select distinct l.app_user_id
    from public.user_line_links l
    where l.active=true
  ),
  stats as (
    select c.moo,c.name as community,
      count(ap.user_id)::int as active_accounts,
      count(ap.user_id) filter(where ap.role='user')::int as active_users,
      count(ap.user_id) filter(where ap.role='staff')::int as active_staff,
      count(ap.user_id) filter(where u.last_sign_in_at>=v_start and u.last_sign_in_at<v_end)::int as signed_in_today,
      count(ap.user_id) filter(where ll.app_user_id is not null)::int as line_connected
    from public.communities c
    left join active_profiles ap on ap.community_key=private.community_key(c.name)
    left join auth.users u on u.id=ap.user_id
    left join line_links ll on ll.app_user_id=ap.user_id
    where c.active=true
    group by c.moo,c.name
  )
  select coalesce(jsonb_agg(jsonb_build_object(
    'moo',s.moo,'community',s.community,'active_accounts',s.active_accounts,
    'active_users',s.active_users,'active_staff',s.active_staff,
    'signed_in_today',s.signed_in_today,'line_connected',s.line_connected
  ) order by nullif(btrim(s.moo),'')::int nulls last,s.community),'[]'::jsonb)
  into v_rows
  from stats s;

  select count(*)::int into v_unmapped
  from public.profiles p
  where p.active=true and p.role in ('user','staff')
    and not exists(
      select 1 from public.communities c
      where c.active=true and private.community_key(c.name)=private.community_key(p.community)
    );

  return jsonb_build_object(
    'version','2.1.34','summary_date',v_day,'timezone','Asia/Bangkok',
    'population','active profiles roles user/staff',
    'signin_source','auth.users.last_sign_in_at',
    'rows',v_rows,'unmapped_accounts',v_unmapped,'generated_at',now()
  );
end;
$function$;

revoke all on function public.daily_community_usage_v2134() from public,anon,authenticated;
grant execute on function public.daily_community_usage_v2134() to service_role;

insert into public.app_settings(key,value)
values('daily_community_usage_telegram_v2134',jsonb_build_object(
  'enabled',true,'delivery','reuse_daily_admin_summary_18_00','extra_cron_jobs',0,
  'roles',jsonb_build_array('user','staff'),
  'metrics',jsonb_build_array('signed_in_today','active_accounts','line_connected'),
  'communities','active canonical communities only'
))
on conflict(key) do update set value=excluded.value,updated_at=now();

commit;
