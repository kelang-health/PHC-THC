create or replace function public.spatial_community_boundaries()
returns table(
  community text,
  moo text,
  geometry_geojson jsonb,
  is_assigned boolean
)
language plpgsql
security definer
set search_path = public, private, extensions
as $$
declare
  v_uid uuid := auth.uid();
  v_profile public.profiles%rowtype;
  v_own_moo text;
begin
  if v_uid is null then raise exception 'AUTH_REQUIRED'; end if;
  select * into v_profile from public.profiles where user_id=v_uid and active=true;
  if not found then raise exception 'PROFILE_NOT_ACTIVE'; end if;

  if v_profile.role in ('staff','user') then
    select c.moo into v_own_moo
    from public.communities c
    where c.active=true and btrim(c.name)=btrim(coalesce(v_profile.community,''))
    limit 1;
  end if;

  return query
  select c.name::text,c.moo::text,c.geometry_geojson,
         (btrim(c.name)=btrim(coalesce(v_profile.community,'')))::boolean
  from public.communities c
  where c.active=true
    and c.geometry_geojson is not null
    and (
      v_profile.role='admin'
      or (v_profile.role='staff' and c.moo=v_own_moo)
      or (v_profile.role='user' and btrim(c.name)=btrim(coalesce(v_profile.community,'')))
    )
  order by c.moo,c.name;
end;
$$;

revoke all on function public.spatial_community_boundaries() from public, anon;
grant execute on function public.spatial_community_boundaries() to authenticated, service_role;
