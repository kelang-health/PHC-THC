-- Cloud v2.0.30 Stability/RLS Architecture
-- Read precomputed screening targets through one explicit-scope SECURITY DEFINER RPC.
-- This avoids re-evaluating nested health/house RLS for every row while preserving role scope.
begin;

create index if not exists houses_volunteer_scope_v2030_idx
  on public.houses(volunteer_pid,source_pcucode,hcode);

create index if not exists houses_community_scope_v2030_idx
  on public.houses(community,source_pcucode,hcode);

create or replace function public.my_screening_targets_v2030(
  p_scope text default 'self',
  p_stage text default null,
  p_search text default null,
  p_community text default null,
  p_limit integer default 300
)
returns setof public.health_screening_target_worklist_v2026
language plpgsql
stable
security definer
set search_path=''
as $$
declare
  v_uid uuid:=auth.uid();
  v_role text;
  v_community text;
  v_pid bigint;
  v_scope text:=lower(btrim(coalesce(p_scope,'self')));
  v_stage text:=nullif(btrim(coalesce(p_stage,'')),'');
  v_search text:=left(nullif(btrim(coalesce(p_search,'')),''),60);
  v_filter_community text:=nullif(btrim(coalesce(p_community,'')),'');
  v_limit integer:=greatest(1,least(coalesce(p_limit,300),300));
begin
  if v_uid is null then raise exception 'AUTH_REQUIRED'; end if;

  select p.role,p.community,p.volunteer_pid
    into v_role,v_community,v_pid
  from public.profiles p
  where p.user_id=v_uid and p.active=true
  limit 1;
  if not found then raise exception 'PROFILE_NOT_ACTIVE'; end if;

  if v_role='admin' then
    v_scope:='all';
  elsif v_role='user' then
    v_scope:='self';
  elsif v_role='staff' then
    if v_scope not in ('self','community') then v_scope:='self'; end if;
  else
    raise exception 'ROLE_NOT_ALLOWED';
  end if;

  return query
  select w.*
  from public.health_screening_target_worklist_v2026 w
  where
    (
      v_role='admin'
      or (v_scope='self' and v_pid is not null and w.volunteer_pid=v_pid)
      or (
        v_role='staff' and v_scope='community'
        and private.community_key(w.community)=private.community_key(v_community)
      )
    )
    and (
      v_filter_community is null
      or private.community_key(w.community)=private.community_key(v_filter_community)
    )
    and (v_stage is null or w.life_stage=v_stage)
    and (v_search is null or w.display_name ilike ('%'||v_search||'%'))
  order by w.community,w.hcode,w.display_name
  limit v_limit;
end;
$$;

revoke all on function public.my_screening_targets_v2030(text,text,text,text,integer) from public,anon;

grant execute on function public.my_screening_targets_v2030(text,text,text,text,integer) to authenticated;

comment on function public.my_screening_targets_v2030(text,text,text,text,integer) is
  'Fast role-scoped field target worklist. Role/community/volunteer scope is resolved once per request; underlying nested RLS is not evaluated per result row.';

insert into public.app_settings(key,value)
values('screening_target_runtime_v2030',jsonb_build_object(
  'version','2.0.30',
  'strategy','precomputed_target_view_via_explicit_scope_security_definer_rpc',
  'max_rows',300,
  'user_scope','own_volunteer_pid',
  'staff_scopes',jsonb_build_array('self','community'),
  'admin_scope','all',
  'nested_rls_per_row',false,
  'jhcis_write_back',false
))
on conflict(key) do update set value=excluded.value,updated_at=now();

notify pgrst,'reload schema';

commit;
