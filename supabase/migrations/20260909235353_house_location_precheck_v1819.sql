create or replace function public.check_house_location(
  p_latitude double precision,
  p_longitude double precision,
  p_community text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public, private, extensions
as $$
declare
  v_uid uuid := auth.uid();
  v_profile public.profiles%rowtype;
  v_community public.communities%rowtype;
  v_name text;
  v_point extensions.geometry;
  v_in_tambon boolean := false;
  v_in_community boolean := false;
begin
  if v_uid is null then raise exception 'AUTH_REQUIRED'; end if;
  select * into v_profile from public.profiles where user_id=v_uid and active=true;
  if not found then raise exception 'PROFILE_NOT_ACTIVE'; end if;
  if p_latitude is null or p_longitude is null or p_latitude < 5 or p_latitude > 21 or p_longitude < 97 or p_longitude > 106 then
    raise exception 'INVALID_COORDINATES';
  end if;

  v_name := case when v_profile.role='admin' then btrim(coalesce(p_community,'')) else btrim(coalesce(v_profile.community,'')) end;
  if v_name='' then raise exception 'COMMUNITY_REQUIRED'; end if;
  select * into v_community from public.communities where active=true and btrim(name)=v_name limit 1;
  if not found then raise exception 'COMMUNITY_NOT_FOUND'; end if;

  v_point := extensions.st_setsrid(extensions.st_makepoint(p_longitude,p_latitude),4326);
  select exists(select 1 from public.tambon_boundaries t where t.tambon_code='520105' and t.geom is not null and extensions.st_covers(extensions.st_makevalid(t.geom),v_point)) into v_in_tambon;
  v_in_community := coalesce(extensions.st_covers(extensions.st_makevalid(v_community.geom),v_point),false);

  return jsonb_build_object('allowed',v_in_tambon and v_in_community,'inside_tambon',v_in_tambon,'inside_community',v_in_community,'community',v_community.name,'moo',v_community.moo);
end;
$$;
revoke all on function public.check_house_location(double precision,double precision,text) from public,anon;
grant execute on function public.check_house_location(double precision,double precision,text) to authenticated;
