-- Allow corrections of a user's own pending field house even before an
-- authoritative volunteer_pid is assigned. Verified houses keep old rules.
create or replace function private.guard_house_client_update_v1854()
returns trigger language plpgsql security definer set search_path = ''
as $$
declare
 v_role text;
 v_profile public.profiles%rowtype;
begin
 if auth.uid() is null then return new; end if;
 select * into v_profile from public.profiles
   where user_id=auth.uid() and active=true limit 1;
 if not found then raise exception 'PROFILE_NOT_ACTIVE' using errcode='42501'; end if;
 v_role:=v_profile.role;
 if v_role='admin' then return new; end if;
 if v_role='staff' and
   private.community_key(old.community)=private.community_key(v_profile.community)
 then return new; end if;
 if v_role='user' and old.entry_source='field'
   and old.superseded_by is null and old.jhcis_verified_at is null
   and old.verification_status in
    ('pending_jhcis_create','pending_jhcis_update','review_required')
   and old.created_by_user_id=auth.uid()
   and v_profile.volunteer_pid is not null
   and old.created_by_volunteer_pid=v_profile.volunteer_pid
   and new.created_by_user_id is not distinct from old.created_by_user_id
   and new.created_by_volunteer_pid is not distinct from old.created_by_volunteer_pid
   and new.volunteer_pid is not distinct from old.volunteer_pid
   and new.entry_source is not distinct from old.entry_source
 then return new; end if;
 if v_role='user' and old.volunteer_pid=private.current_volunteer_pid()
 then return new; end if;
 raise exception 'HOUSE_READ_ONLY_SCOPE' using errcode='42501';
end $$;