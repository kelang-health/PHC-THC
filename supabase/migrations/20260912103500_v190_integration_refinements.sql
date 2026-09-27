-- OSM-PHC Cloud v1.9.0 integration refinements
-- Admin duplicate matching and LINE broadcast scopes.
begin;

create or replace function public.my_line_status_v190()
returns jsonb language plpgsql stable security definer set search_path=''
as $$
declare v_connected boolean; v_linked_at timestamptz; v_next public.appointments%rowtype;
begin
  if auth.uid() is null then raise exception 'AUTH_REQUIRED'; end if;
  select exists(select 1 from public.user_line_links where app_user_id=auth.uid() and active=true),
         (select linked_at from public.user_line_links where app_user_id=auth.uid() and active=true limit 1)
    into v_connected,v_linked_at;
  select * into v_next from public.appointments where app_user_id=auth.uid() and status='scheduled' and appointment_at>=now() order by appointment_at limit 1;
  return jsonb_build_object('connected',coalesce(v_connected,false),'linked_at',v_linked_at,
    'next_appointment',case when v_next.id is null then null else jsonb_build_object('id',v_next.id,'title',v_next.title,'appointment_at',v_next.appointment_at,'location',v_next.location_text) end);
end;
$$;

revoke all on function public.my_line_status_v190() from public,anon;

grant execute on function public.my_line_status_v190() to authenticated;

create or replace function public.admin_member_request_match_v190(p_request_id uuid)
returns table(source_pcucode text,source_pid bigint,display_name text,birth_date date,house_no text,community text,match_type text,same_house boolean)
language plpgsql stable security definer set search_path=''
as $$
declare r public.household_member_requests%rowtype; h public.houses%rowtype;
begin
  if auth.uid() is null or private.current_role()<>'admin' then raise exception 'ADMIN_REQUIRED'; end if;
  select * into r from public.household_member_requests where id=p_request_id;
  if not found then raise exception 'REQUEST_NOT_FOUND'; end if;
  select * into h from public.houses where id=r.house_id;
  return query
  select p.source_pcucode,p.source_pid,p.display_name,p.birth_date,hh.house_no,hh.community,
    case when p.citizen_id_hash=r.citizen_id_hash then 'citizen_id_hash' else 'name_birth_date' end::text,
    (p.house_pcucode=h.source_pcucode and p.hcode=h.hcode)
  from public.health_persons p
  join public.houses hh on hh.source_pcucode=p.house_pcucode and hh.hcode=p.hcode
  where p.active=true and (p.citizen_id_hash=r.citizen_id_hash or (lower(btrim(p.display_name))=lower(btrim(r.full_name)) and p.birth_date=r.birth_date))
  order by (p.citizen_id_hash=r.citizen_id_hash) desc,(p.house_pcucode=h.source_pcucode and p.hcode=h.hcode) desc
  limit 20;
end;
$$;

revoke all on function public.admin_member_request_match_v190(uuid) from public,anon;

grant execute on function public.admin_member_request_match_v190(uuid) to authenticated;

create table if not exists public.line_message_groups (
  id uuid primary key default extensions.gen_random_uuid(),
  name text not null unique,
  active boolean not null default true,
  created_by uuid not null references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.line_message_group_members (
  group_id uuid not null references public.line_message_groups(id) on delete cascade,
  app_user_id uuid not null references auth.users(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key(group_id,app_user_id)
);

alter table public.line_message_groups enable row level security;

alter table public.line_message_group_members enable row level security;

revoke all on public.line_message_groups,public.line_message_group_members from public,anon,authenticated;

grant select on public.line_message_groups,public.line_message_group_members to authenticated;

drop policy if exists line_groups_admin_select_v190 on public.line_message_groups;

create policy line_groups_admin_select_v190 on public.line_message_groups for select to authenticated using(private.current_role()='admin');

drop policy if exists line_group_members_admin_select_v190 on public.line_message_group_members;

create policy line_group_members_admin_select_v190 on public.line_message_group_members for select to authenticated using(private.current_role()='admin');

create or replace function public.admin_save_line_group_v190(p_group_id uuid,p_name text,p_user_ids uuid[])
returns uuid language plpgsql security definer set search_path=''
as $$
declare v_id uuid:=p_group_id;
begin
  if auth.uid() is null or private.current_role()<>'admin' then raise exception 'ADMIN_REQUIRED'; end if;
  if nullif(btrim(p_name),'') is null then raise exception 'GROUP_NAME_REQUIRED'; end if;
  if v_id is null then
    insert into public.line_message_groups(name,created_by) values(left(btrim(p_name),120),auth.uid()) returning id into v_id;
  else
    update public.line_message_groups set name=left(btrim(p_name),120),active=true,updated_at=now() where id=v_id;
    if not found then raise exception 'GROUP_NOT_FOUND'; end if;
  end if;
  delete from public.line_message_group_members where group_id=v_id;
  insert into public.line_message_group_members(group_id,app_user_id)
  select v_id,u from unnest(coalesce(p_user_ids,'{}'::uuid[])) u
  join public.profiles p on p.user_id=u and p.active=true
  on conflict do nothing;
  return v_id;
end;
$$;

revoke all on function public.admin_save_line_group_v190(uuid,text,uuid[]) from public,anon;

grant execute on function public.admin_save_line_group_v190(uuid,text,uuid[]) to authenticated;

create or replace function public.admin_queue_line_broadcast_v190(
  p_scope_type text,p_scope_value text,p_body text,p_action_path text default '',p_message_type text default 'notice'
) returns jsonb language plpgsql security definer set search_path=''
as $$
declare v_scope text:=lower(btrim(coalesce(p_scope_type,''))); v_count integer:=0;
begin
  if auth.uid() is null or private.current_role()<>'admin' then raise exception 'ADMIN_REQUIRED'; end if;
  if v_scope not in ('all','community','role','group','urgent') then raise exception 'INVALID_BROADCAST_SCOPE'; end if;
  if not private.safe_notification_text_v190(p_body) then raise exception 'UNSAFE_MESSAGE_CONTENT'; end if;
  with recipients as (
    select distinct p.user_id
    from public.profiles p
    join public.user_line_links l on l.app_user_id=p.user_id and l.active=true
    where p.active=true and (
      v_scope='all'
      or (v_scope='community' and private.community_key(p.community)=private.community_key(p_scope_value))
      or (v_scope='role' and p.role=lower(btrim(p_scope_value)))
      or (v_scope='group' and exists(select 1 from public.line_message_group_members gm where gm.group_id::text=p_scope_value and gm.app_user_id=p.user_id))
      or (v_scope='urgent' and exists(
        select 1 from public.screening_followups f
        join public.health_persons hp on hp.source_pcucode=f.source_pcucode and hp.source_pid=f.source_pid
        join public.houses h on h.source_pcucode=hp.house_pcucode and h.hcode=hp.hcode
        where f.status in ('open','in_progress') and (h.volunteer_pid=p.volunteer_pid or (p.role='staff' and private.community_key(p.community)=private.community_key(h.community)))
      ))
    )
  ), ins as (
    insert into public.line_messages(recipient_user_id,message_type,body,action_path,created_by)
    select r.user_id,case when p_message_type in ('notice','appointment','urgent_task','system') then p_message_type else 'notice' end,left(p_body,500),left(coalesce(p_action_path,''),300),auth.uid()
    from recipients r returning id
  ) select count(*) into v_count from ins;
  return jsonb_build_object('ok',true,'queued',v_count,'scope_type',v_scope);
end;
$$;

revoke all on function public.admin_queue_line_broadcast_v190(text,text,text,text,text) from public,anon;

grant execute on function public.admin_queue_line_broadcast_v190(text,text,text,text,text) to authenticated;

insert into public.app_settings(key,value)
values('line_broadcast_v190',jsonb_build_object('scopes',jsonb_build_array('all','community','role','group','urgent'),'free_text_health_write',false))
on conflict(key) do update set value=excluded.value,updated_at=now();

commit;
