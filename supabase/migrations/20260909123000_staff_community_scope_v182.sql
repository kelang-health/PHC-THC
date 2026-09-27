-- OSM-PHC v1.8.2
-- Role scope: admin = all communities, staff = own community, user = own assigned houses.
-- Applies consistently to community, volunteer, house and Health Work Center reads.
begin;

update public.profiles
set community=btrim(community)
where community is not null and community<>btrim(community);

-- Community visibility
drop policy if exists communities_select on public.communities;

create policy communities_select on public.communities
for select to authenticated
using (
  private.current_role() = 'admin'
  or (
    private.current_role() = 'staff'
    and coalesce(btrim(private.current_community()),'') <> ''
    and btrim(name) = btrim(private.current_community())
  )
  or (
    private.current_role() = 'user'
    and exists (
      select 1 from public.houses h
      where h.volunteer_pid = private.current_volunteer_pid()
        and btrim(h.community) = btrim(communities.name)
    )
  )
);

-- Volunteer visibility
drop policy if exists volunteers_select on public.volunteers;

create policy volunteers_select on public.volunteers
for select to authenticated
using (
  private.current_role() = 'admin'
  or (
    private.current_role() = 'staff'
    and coalesce(btrim(private.current_community()),'') <> ''
    and btrim(community) = btrim(private.current_community())
  )
  or (
    private.current_role() = 'user'
    and source_pid = private.current_volunteer_pid()
  )
);

-- House visibility
drop policy if exists houses_select on public.houses;

create policy houses_select on public.houses
for select to authenticated
using (
  private.current_role() = 'admin'
  or (
    private.current_role() = 'staff'
    and coalesce(btrim(private.current_community()),'') <> ''
    and btrim(community) = btrim(private.current_community())
  )
  or (
    private.current_role() = 'user'
    and volunteer_pid = private.current_volunteer_pid()
  )
);

-- Health access is derived from house scope; this controls health_persons,
-- worklist/history views and the save RPC through health_can_access_person().
create or replace function private.health_can_access_house(p_pcucode text, p_hcode text)
returns boolean
language sql stable security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.houses h
    where h.source_pcucode = p_pcucode
      and h.hcode = p_hcode
      and (
        private.current_role() = 'admin'
        or (
          private.current_role() = 'staff'
          and coalesce(btrim(private.current_community()),'') <> ''
          and btrim(h.community) = btrim(private.current_community())
        )
        or (
          private.current_role() = 'user'
          and h.volunteer_pid = private.current_volunteer_pid()
        )
      )
  );
$$;

revoke all on function private.health_can_access_house(text,text) from public,anon,authenticated;

grant execute on function private.health_can_access_house(text,text) to authenticated;

insert into public.app_settings(key,value)
values ('role_scope',jsonb_build_object(
  'version','1.8.2',
  'admin','all_communities',
  'staff','profile.community',
  'user','assigned_houses_by_volunteer_pid',
  'health_scope','derived_from_house_scope'
))
on conflict(key) do update set value=excluded.value,updated_at=now();

commit;
