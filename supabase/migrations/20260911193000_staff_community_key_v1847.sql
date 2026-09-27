-- v1.8.47: compare staff community scope with a whitespace-insensitive key.
-- JHCIS house/volunteer data uses "เธเธธเธกเธเธเธเนเธฒเนเธฅเธง 2" while the j-report
-- boundary registry uses "เธเธธเธกเธเธเธเนเธฒเนเธฅเธง2". Both names identify the same area.

create or replace function private.community_key(p_value text)
returns text
language sql
immutable
set search_path = ''
as $$
  select regexp_replace(lower(btrim(coalesce(p_value, ''))), '[[:space:]]+', '', 'g')
$$;

revoke all on function private.community_key(text) from public;

grant execute on function private.community_key(text) to authenticated;

create or replace function private.health_can_access_house(p_pcucode text, p_hcode text)
returns boolean
language sql
stable
security definer
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
          and private.community_key(private.current_community()) <> ''
          and private.community_key(h.community) = private.community_key(private.current_community())
        )
        or (
          private.current_role() = 'user'
          and h.volunteer_pid = private.current_volunteer_pid()
        )
      )
  )
$$;

drop policy if exists communities_select on public.communities;

create policy communities_select on public.communities for select to authenticated
using (
  private.current_role() = 'admin'
  or (
    private.current_role() = 'staff'
    and private.community_key(private.current_community()) <> ''
    and private.community_key(name) = private.community_key(private.current_community())
  )
  or (
    private.current_role() = 'user'
    and exists (
      select 1 from public.houses h
      where h.volunteer_pid = private.current_volunteer_pid()
        and private.community_key(h.community) = private.community_key(communities.name)
    )
  )
);

drop policy if exists houses_select on public.houses;

create policy houses_select on public.houses for select to authenticated
using (
  private.current_role() = 'admin'
  or (
    private.current_role() = 'staff'
    and private.community_key(private.current_community()) <> ''
    and private.community_key(community) = private.community_key(private.current_community())
  )
  or (
    private.current_role() = 'user'
    and volunteer_pid = private.current_volunteer_pid()
  )
);

drop policy if exists volunteers_select on public.volunteers;

create policy volunteers_select on public.volunteers for select to authenticated
using (
  private.current_role() = 'admin'
  or (
    private.current_role() = 'staff'
    and private.community_key(private.current_community()) <> ''
    and private.community_key(community) = private.community_key(private.current_community())
  )
  or (
    private.current_role() = 'user'
    and source_pid = private.current_volunteer_pid()
  )
);
