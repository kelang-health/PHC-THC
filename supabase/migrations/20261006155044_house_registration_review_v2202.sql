-- Explicit audit cohort only; never infer membership from an invalid number.
create table private.house_id11_review_v2202 (
 house_id uuid primary key references public.houses(id),
 audit_source text not null,
 audited_at timestamptz not null default now(),
 corrected_id11 text,
 corrected_by uuid,
 corrected_at timestamptz
);
alter table private.house_id11_review_v2202 enable row level security;
revoke all on private.house_id11_review_v2202 from public,anon,authenticated;

create function public.house_registration_review_cards_v2202()
returns jsonb language plpgsql security definer set search_path='' as $$
declare p public.profiles; result jsonb;
begin
 select * into p from public.profiles where user_id=auth.uid() and active;
 if p.user_id is null then raise exception 'AUTH_REQUIRED'; end if;
 select coalesce(jsonb_agg(jsonb_build_object(
 'id',h.id,'hcode',h.hcode,'house_no',h.house_no,'moo',h.moo,'community',h.community,
 'house_id_11',h.house_id_11,'updated_at',h.updated_at,
 'needs_id11',r.house_id is not null and coalesce(h.house_id_11,'') !~ '^[0-9]{11}$',
 'unassigned_village',coalesce(btrim(h.community),'')='' and h.volunteer_pid is null,
 'can_edit',p.role='admin',
 'pending_main',r.corrected_id11 is not null
 ) order by h.moo,h.house_no),'[]'::jsonb) into result
 from public.houses h left join private.house_id11_review_v2202 r on r.house_id=h.id
 where h.superseded_by is null and h.verification_status='verified_jhcis'
 and ((r.house_id is not null and coalesce(h.house_id_11,'') !~ '^[0-9]{11}$')
 or (coalesce(btrim(h.community),'')='' and h.volunteer_pid is null))
 and (p.role='admin'
 or (p.role='staff' and (
 private.community_key(p.community)=private.community_key(h.community)
 or (coalesce(btrim(h.community),'')='' and h.volunteer_pid is null and exists(
 select 1 from public.communities c where c.active and private.community_key(c.name)=private.community_key(p.community)
 and btrim(c.moo)=btrim(h.moo)))))
 or (p.role='user' and h.volunteer_pid=p.volunteer_pid));
 return result;
end $$;
revoke all on function public.house_registration_review_cards_v2202() from public,anon;
grant execute on function public.house_registration_review_cards_v2202() to authenticated;

create function public.correct_audited_house_id11_v2202(p_house_id uuid,p_id11 text,p_expected_updated_at timestamptz)
returns jsonb language plpgsql security definer set search_path='' as $$
declare p public.profiles; h public.houses; v text:=btrim(p_id11);
begin
 select * into p from public.profiles where user_id=auth.uid() and active and role='admin';
 if p.user_id is null then raise exception 'ADMIN_REQUIRED'; end if;
 if v is null or v !~ '^[0-9]{11}$' then raise exception 'HOUSE_ID11_INVALID'; end if;
 select * into h from public.houses where id=p_house_id and superseded_by is null and verification_status='verified_jhcis' for update;
 if h.id is null or not exists(select 1 from private.house_id11_review_v2202 where house_id=h.id) then raise exception 'NOT_IN_AUDIT_COHORT'; end if;
 if h.updated_at is distinct from p_expected_updated_at then raise exception 'HOUSE_CHANGED_RELOAD'; end if;
 perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtext('house11:'||v));
 if exists(select 1 from public.houses where id<>h.id and superseded_by is null and house_id_11=v) then raise exception 'HOUSE_ID11_DUPLICATE'; end if;
 update private.house_id11_review_v2202 set corrected_id11=v,corrected_by=p.user_id,corrected_at=now() where house_id=h.id;
 update public.houses set house_id_11=v,updated_at=now() where id=h.id;
 insert into public.house_registration_audit(house_id,user_id,role,volunteer_pid,action,before_data,after_data)
 values(h.id,p.user_id,p.role,p.volunteer_pid,'update',jsonb_build_object('house_id_11',h.house_id_11),jsonb_build_object('house_id_11',v,'source','id11_audit_v2202','pending_main',true));
 return jsonb_build_object('ok',true,'house_id',h.id,'house_id_11',v);
end $$;
revoke all on function public.correct_audited_house_id11_v2202(uuid,text,timestamptz) from public,anon;
grant execute on function public.correct_audited_house_id11_v2202(uuid,text,timestamptz) to authenticated;

-- An incomplete import must not erase a verified Cloud correction.
-- A complete Main number remains authoritative and resolves the pending correction.
create function private.preserve_house_id11_correction_v2202()
returns trigger language plpgsql security definer set search_path='' as $$
declare v text;
begin
 select corrected_id11 into v from private.house_id11_review_v2202 where house_id=new.id;
 if v is not null then
  if coalesce(new.house_id_11,'') !~ '^[0-9]{11}$' then new.house_id_11:=v;
  elsif old.house_id_11=v and new.house_id_11 is distinct from old.house_id_11 then
   update private.house_id11_review_v2202 set corrected_id11=null where house_id=new.id;
  end if;
 end if;
 return new;
end $$;
revoke all on function private.preserve_house_id11_correction_v2202() from public,anon,authenticated;
create trigger preserve_house_id11_correction_v2202 before update of house_id_11 on public.houses
for each row execute function private.preserve_house_id11_correction_v2202();
