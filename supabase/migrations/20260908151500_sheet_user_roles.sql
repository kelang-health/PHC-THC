-- v1.7: align Cloud roles with the original Sheet/index model.
-- Roles: admin / staff / user.

alter table public.profiles drop constraint if exists profiles_role_check;

update public.profiles
set role = case role
  when 'coordinator' then 'staff'
  when 'viewer' then 'staff'
  when 'volunteer' then 'user'
  else role
end;

alter table public.profiles
  add constraint profiles_role_check check (role in ('admin','staff','user'));

-- Staff and admin have whole-area read scope. User is tied to own PID/houses.
drop policy if exists communities_select on public.communities;

create policy communities_select on public.communities for select to authenticated
using (
  private.current_role() in ('admin','staff')
  or exists (
    select 1 from public.volunteers v
    where v.source_pid = private.current_volunteer_pid()
      and v.community = communities.name
  )
);

drop policy if exists volunteers_select on public.volunteers;

create policy volunteers_select on public.volunteers for select to authenticated
using (
  private.current_role() in ('admin','staff')
  or (
    private.current_role() = 'user'
    and source_pid = private.current_volunteer_pid()
  )
);

drop policy if exists houses_select on public.houses;

create policy houses_select on public.houses for select to authenticated
using (
  private.current_role() in ('admin','staff')
  or (
    private.current_role() = 'user'
    and volunteer_pid = private.current_volunteer_pid()
  )
);

-- Operational replica remains server-synced. Normal users do not directly delete rows.
-- Add/update field work continues through the OSM-PHC application where role and
-- house assignment are validated and audited before the next Cloud sync.

insert into public.app_settings(key,value)
values ('account_policy', jsonb_build_object(
  'roles', jsonb_build_array('admin','staff','user'),
  'user_username', 'phone_from_original_sheet',
  'user_linkage', 'source_pcucode + source_pid',
  'user_first_password_change_required', false,
  'plain_password_stored', false
))
on conflict (key) do update set value = excluded.value, updated_at = now();
