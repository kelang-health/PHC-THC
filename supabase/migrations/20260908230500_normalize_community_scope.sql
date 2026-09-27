-- Normalize community keys and keep user community visibility aligned with assigned houses.
update public.communities set name = btrim(name), moo = btrim(moo) where name <> btrim(name) or moo <> btrim(moo);

update public.volunteers set community = btrim(community), moo = btrim(moo) where community <> btrim(community) or moo <> btrim(moo);

update public.houses set community = btrim(community), moo = btrim(moo) where community <> btrim(community) or moo <> btrim(moo);

update public.profiles set community = btrim(community) where community <> btrim(community);

drop policy if exists communities_select on public.communities;

create policy communities_select on public.communities for select to authenticated
using (
  private.current_role() in ('admin','staff')
  or btrim(name) = btrim(private.current_community())
  or exists (
    select 1
    from public.houses h
    where private.current_role() = 'user'
      and h.volunteer_pid = private.current_volunteer_pid()
      and btrim(h.community) = btrim(communities.name)
  )
);
