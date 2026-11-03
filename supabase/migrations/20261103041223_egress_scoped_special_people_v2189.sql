-- Read-only pagination: caller RLS on both houses and persons remains enforced.
create or replace function public.care_special_people_page_v2189(
  p_group text, p_scope text default 'self', p_owner_pid bigint default null,
  p_search text default '', p_limit integer default 31, p_offset integer default 0
)
returns table (
  source_pcucode text, source_pid bigint, display_name text,
  house_no text, moo text, community text, age_years integer, adl_assessed_on date
)
language plpgsql stable security invoker set search_path = ''
as $function$
declare
  v_actor public.profiles%rowtype;
  v_owner bigint;
  v_today date := (pg_catalog.now() at time zone 'Asia/Bangkok')::date;
begin
  select * into v_actor from public.profiles where user_id = auth.uid() and active;
  if not found or v_actor.role is null or v_actor.role not in ('admin','staff','user') then
    raise exception 'AUTH_REQUIRED' using errcode = '42501';
  end if;
  if p_group is null or p_group not in ('disabled','homebound','bedridden') then
    raise exception 'SPECIAL_GROUP_INVALID' using errcode = '22023';
  end if;
  if p_scope is null or p_scope not in ('all','self','volunteer','community') then
    raise exception 'SCOPE_INVALID' using errcode = '22023';
  end if;
  -- Same scope as the existing special-person list, with caller RLS still active.
  if v_actor.role = 'user' then v_owner := v_actor.volunteer_pid;
  elsif v_actor.role = 'staff' and p_scope = 'self' then v_owner := v_actor.volunteer_pid;
  elsif v_actor.role = 'staff' and p_scope = 'volunteer' then v_owner := p_owner_pid;
  elsif v_actor.role = 'staff' and p_scope <> 'community' then
    raise exception 'SCOPE_DENIED' using errcode = '42501';
  end if;
  if (v_actor.role = 'user' or (v_actor.role = 'staff' and p_scope in ('self','volunteer')))
    and v_owner is null then return; end if;
  return query
  select p.source_pcucode,p.source_pid,p.display_name,h.house_no,h.moo,h.community,
    case when p.birth_date<=v_today then pg_catalog.date_part('year',pg_catalog.age(v_today,p.birth_date))::integer end,p.adl_assessed_on
  from public.health_persons p
  join public.houses h on h.source_pcucode=p.house_pcucode and h.hcode=p.hcode
  where p.active and p.service_population_eligible
    and h.verification_status='verified_jhcis' and h.superseded_by is null
    and (v_actor.role='admin' or v_owner is null or h.volunteer_pid=v_owner)
    and case p_group when 'disabled' then p.is_disabled
      when 'homebound' then p.adl_group_code='1B1281' and p.birth_date <= (v_today - interval '60 years')::date
      when 'bedridden' then p.adl_group_code='1B1282' and p.birth_date <= (v_today - interval '60 years')::date end
    and (coalesce(btrim(p_search),'')='' or pg_catalog.strpos(
      pg_catalog.lower(pg_catalog.concat_ws(' ',p.display_name,h.house_no,h.community)),
      pg_catalog.lower(btrim(p_search)))>0)
  order by p.display_name,p.source_pcucode,p.source_pid
  limit greatest(1,least(coalesce(p_limit,31),51)) offset greatest(0,coalesce(p_offset,0));
end;
$function$;
revoke all on function public.care_special_people_page_v2189(text,text,bigint,text,integer,integer) from public,anon;
grant execute on function public.care_special_people_page_v2189(text,text,bigint,text,integer,integer) to authenticated;
comment on function public.care_special_people_page_v2189(text,text,bigint,text,integer,integer)
is 'Read-only special-person display page. SECURITY INVOKER preserves caller RLS; no population/target changes.';
