create or replace function private.screening_followup_scope_v2195(
  p_scope text default 'self',
  p_owner_pid bigint default null
)
returns table(
  id uuid,
  source_pcucode text,
  source_pid bigint,
  display_name text,
  house_no text,
  community text,
  volunteer_pid bigint,
  followup_type text,
  domain_code text,
  priority text,
  status text,
  summary text,
  created_at timestamptz,
  updated_at timestamptz
)
language plpgsql
stable
security definer
set search_path to ''
as $$
declare
  v_uid uuid := auth.uid();
  v_role text;
  v_community text;
  v_pid bigint;
  v_scope text := lower(btrim(coalesce(p_scope,'self')));
  v_owner bigint := p_owner_pid;
begin
  if v_uid is null then raise exception 'AUTH_REQUIRED'; end if;

  select p.role,p.community,p.volunteer_pid
    into v_role,v_community,v_pid
  from public.profiles p
  where p.user_id=v_uid and p.active=true
  limit 1;
  if not found then raise exception 'PROFILE_NOT_ACTIVE'; end if;

  if v_role='admin' then
    v_scope:='all'; v_owner:=null;
  elsif v_role='user' then
    v_scope:='self'; v_owner:=v_pid;
  elsif v_role='staff' then
    if v_scope='community' then
      v_owner:=null;
    elsif v_scope='volunteer' then
      if v_owner is null or not exists(
        select 1
        from public.profiles p
        join public.volunteers v on v.source_pid=p.volunteer_pid and v.active=true
        where p.active=true and p.role='user' and p.volunteer_pid=v_owner
          and private.community_key(p.community)=private.community_key(v_community)
      ) then
        raise exception 'VOLUNTEER_SCOPE_NOT_ALLOWED';
      end if;
    else
      v_scope:='self'; v_owner:=v_pid;
    end if;
  else
    raise exception 'ROLE_NOT_ALLOWED';
  end if;

  return query
  select
    f.id,f.source_pcucode,f.source_pid,p.display_name,h.house_no,h.community,h.volunteer_pid,
    f.followup_type,f.domain_code,f.priority,f.status,f.summary,f.created_at,f.updated_at
  from public.screening_followups f
  join public.health_persons p
    on p.source_pcucode=f.source_pcucode and p.source_pid=f.source_pid
  join public.houses h
    on h.source_pcucode=p.house_pcucode and h.hcode=p.hcode
  where h.superseded_by is null
    and f.status in ('open','in_progress')
    and (
      v_role='admin'
      or (v_scope in ('self','volunteer') and v_owner is not null and h.volunteer_pid=v_owner)
      or (v_role='staff' and v_scope='community'
          and private.community_key(h.community)=private.community_key(v_community))
    )
  order by case f.priority when 'red' then 0 when 'orange' then 1 else 2 end,f.created_at,f.id;
end;
$$;

revoke all on function private.screening_followup_scope_v2195(text,bigint) from public;

create or replace function public.screening_followup_count_v2195(
  p_scope text default 'self',
  p_owner_pid bigint default null
)
returns bigint
language sql
stable
security definer
set search_path to ''
as $$
  select count(*)::bigint
  from private.screening_followup_scope_v2195(p_scope,p_owner_pid);
$$;

create or replace function public.screening_followup_worklist_v2195(
  p_scope text default 'self',
  p_owner_pid bigint default null,
  p_limit integer default 100,
  p_offset integer default 0
)
returns table(
  id uuid,
  source_pcucode text,
  source_pid bigint,
  display_name text,
  house_no text,
  community text,
  volunteer_pid bigint,
  followup_type text,
  domain_code text,
  priority text,
  status text,
  summary text,
  created_at timestamptz,
  updated_at timestamptz
)
language plpgsql
stable
security definer
set search_path to ''
as $$
declare
  v_limit integer := greatest(1,least(coalesce(p_limit,100),200));
  v_offset integer := greatest(0,coalesce(p_offset,0));
begin
  return query
  select s.*
  from private.screening_followup_scope_v2195(p_scope,p_owner_pid) s
  limit v_limit offset v_offset;
end;
$$;

create or replace function public.report_snapshot_care_v2195(
  p_scope text default 'self',
  p_owner_pid bigint default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path to ''
as $$
declare
  v_payload jsonb;
  v_followup bigint;
begin
  v_payload:=public.report_snapshot_v2033('care',p_scope,p_owner_pid);
  if v_payload is null then return null; end if;

  v_followup:=public.screening_followup_count_v2195(p_scope,p_owner_pid);

  return v_payload || jsonb_build_object(
    'version','2.1.95',
    'followup_open',coalesce(v_followup,0),
    'followup_definition','screening_followups status open + in_progress',
    'followup_source','screening_followup_scope_v2195'
  );
end;
$$;

revoke all on function public.screening_followup_count_v2195(text,bigint) from public;
revoke all on function public.screening_followup_worklist_v2195(text,bigint,integer,integer) from public;
revoke all on function public.report_snapshot_care_v2195(text,bigint) from public;

grant execute on function public.screening_followup_count_v2195(text,bigint) to authenticated,service_role;
grant execute on function public.screening_followup_worklist_v2195(text,bigint,integer,integer) to authenticated,service_role;
grant execute on function public.report_snapshot_care_v2195(text,bigint) to authenticated,service_role;

insert into public.app_settings(key,value)
values(
  'care_followup_overview_v2195',
  jsonb_build_object(
    'enabled',true,
    'version','2.1.95',
    'count_source','screening_followups',
    'active_statuses',jsonb_build_array('open','in_progress'),
    'same_source_for_card_and_list',true,
    'list_load_mode','on_click_only',
    'user_scope','own volunteer houses only',
    'staff_scope','self / selected volunteer / own community',
    'admin_scope','all',
    'urgent_attention_preserved_as_separate_metric',true
  )
)
on conflict(key) do update set value=excluded.value;

comment on function public.screening_followup_worklist_v2195(text,bigint,integer,integer)
is 'Role/scope-aware active screening follow-up list. Card count and list share the same private scoped source.';
