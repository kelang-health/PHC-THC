-- Cloud v2.0.134 / v2174
-- Keep field-created house history visible after JHCIS verification and normalize stale pending labels.
begin;

create or replace function private.normalize_field_house_verified_state_v2174()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
  if new.entry_source = 'field' and new.verification_status = 'verified_jhcis' then
    new.record_status := 'ยืนยัน JHCIS แล้ว';

    -- Clear only the old request-workflow review reason. Coordinate/data-quality
    -- review reasons remain untouched and continue to require review.
    if coalesce(btrim(new.review_reason), '') = 'บ้านเพิ่มจาก Cloud รอเจ้าหน้าที่ตรวจ/บันทึก JHCIS' then
      new.review_required := false;
      new.review_reason := '';
    end if;
  end if;

  return new;
end;
$$;

drop trigger if exists trg_normalize_field_house_verified_state_v2174 on public.houses;
create trigger trg_normalize_field_house_verified_state_v2174
before insert or update of verification_status on public.houses
for each row
execute function private.normalize_field_house_verified_state_v2174();

-- Repair rows already verified by JHCIS before this migration.
update public.houses
set record_status = 'ยืนยัน JHCIS แล้ว',
    review_required = case
      when coalesce(btrim(review_reason), '') = 'บ้านเพิ่มจาก Cloud รอเจ้าหน้าที่ตรวจ/บันทึก JHCIS' then false
      else review_required
    end,
    review_reason = case
      when coalesce(btrim(review_reason), '') = 'บ้านเพิ่มจาก Cloud รอเจ้าหน้าที่ตรวจ/บันทึก JHCIS' then ''
      else review_reason
    end,
    updated_at = now()
where entry_source = 'field'
  and superseded_by is null
  and verification_status = 'verified_jhcis';

-- This RPC remains admin-only, but now returns verified field-house history too.
create or replace function public.admin_cancellable_field_houses_v2163()
returns table(
  id uuid,
  house_no text,
  house_id_11 text,
  moo text,
  community text,
  verification_status text,
  created_at timestamptz,
  open_member_requests bigint,
  requester_name text,
  requester_community text,
  requester_role text,
  requester_volunteer_pid bigint
)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if auth.uid() is null or private.current_role() <> 'admin' then
    raise exception 'ADMIN_REQUIRED';
  end if;

  return query
    select
      h.id,
      h.house_no,
      h.house_id_11,
      h.moo,
      h.community,
      h.verification_status,
      coalesce(h.field_created_at, h.updated_at),
      (
        select count(*)
        from public.household_member_requests r
        where r.house_id = h.id
          and (r.status <> 'rejected' or r.linked_person_id is not null)
      ),
      coalesce(nullif(btrim(p.display_name), ''), 'ไม่ระบุ')::text,
      coalesce(nullif(btrim(p.community), ''), nullif(btrim(h.community), ''), 'ไม่ระบุ')::text,
      coalesce(nullif(btrim(p.role), ''), 'ไม่ระบุ')::text,
      coalesce(p.volunteer_pid, h.created_by_volunteer_pid)
    from public.houses h
    left join public.profiles p on p.user_id = h.created_by_user_id
    where h.entry_source = 'field'
      and h.superseded_by is null
      and h.verification_status in (
        'pending_jhcis_create',
        'pending_jhcis_update',
        'review_required',
        'verified_jhcis'
      )
    order by
      case when h.verification_status = 'verified_jhcis' then 1 else 0 end,
      coalesce(h.field_created_at, h.updated_at) desc
    limit 100;
end;
$$;

revoke all on function public.admin_cancellable_field_houses_v2163() from public, anon, authenticated;
grant execute on function public.admin_cancellable_field_houses_v2163() to authenticated;

insert into public.app_settings(key, value)
values(
  'field_house_history_v2174',
  jsonb_build_object(
    'version', '2.0.134',
    'verified_history_visible', true,
    'pending_cancel_policy', 'pending_jhcis_create_without_linked_members_only',
    'verified_cancel_allowed', false,
    'verified_record_status', 'ยืนยัน JHCIS แล้ว',
    'coordinate_review_preserved', true,
    'physical_delete', false,
    'jhcis_write_back', false
  )
)
on conflict(key) do update
set value = excluded.value,
    updated_at = now();

notify pgrst, 'reload schema';
commit;
