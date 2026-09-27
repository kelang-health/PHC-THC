-- Cloud v2.0.30d: JSON RPC over denormalized target cache.
begin;

create or replace function public.my_screening_targets_json_v2030(
  p_scope text default 'self',
  p_stage text default null,
  p_search text default null,
  p_community text default null,
  p_limit integer default 300
)
returns jsonb
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
  v_result jsonb;
begin
  if v_uid is null then raise exception 'AUTH_REQUIRED'; end if;
  select pr.role,pr.community,pr.volunteer_pid into v_role,v_community,v_pid
  from public.profiles pr where pr.user_id=v_uid and pr.active=true limit 1;
  if not found then raise exception 'PROFILE_NOT_ACTIVE'; end if;

  if v_role='admin' then v_scope:='all';
  elsif v_role='user' then v_scope:='self';
  elsif v_role='staff' then
    if v_scope not in ('self','community') then v_scope:='self'; end if;
  else raise exception 'ROLE_NOT_ALLOWED';
  end if;

  select coalesce(jsonb_agg(to_jsonb(x)),'[]'::jsonb) into v_result
  from (
    select c.*
    from public.health_screening_target_cache_v2030 c
    where (
        v_role='admin'
        or (v_scope='self' and v_pid is not null and c.volunteer_pid=v_pid)
        or (v_role='staff' and v_scope='community'
            and private.community_key(c.community)=private.community_key(v_community))
      )
      and (v_filter_community is null or private.community_key(c.community)=private.community_key(v_filter_community))
      and (v_stage is null or c.life_stage=v_stage)
      and (v_search is null or c.display_name ilike ('%'||v_search||'%'))
    order by c.community,c.hcode,c.display_name
    limit v_limit
  ) x;
  return v_result;
end;
$$;

revoke all on function public.my_screening_targets_json_v2030(text,text,text,text,integer) from public,anon;

grant execute on function public.my_screening_targets_json_v2030(text,text,text,text,integer) to authenticated;

notify pgrst,'reload schema';

commit;
