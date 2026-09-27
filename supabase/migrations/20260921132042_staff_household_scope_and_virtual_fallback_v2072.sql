
create or replace function public.staff_household_cards_v2072(p_community text default null)
returns table(
 id uuid, hcode text, house_no text, moo text, community text,
 latitude double precision, longitude double precision,
 coordinate_status text, record_status text,
 review_required boolean, review_reason text,
 volunteer_pid bigint, volunteer_name text,
 assignment_state text, assignment_label text, can_manage boolean
)
language plpgsql stable security definer set search_path=''
as $body$
declare
 v_uid uuid:=auth.uid();
 v_profile public.profiles%rowtype;
 v_own public.communities%rowtype;
 v_target public.communities%rowtype;
 v_requested text;
 v_is_own boolean;
begin
 if v_uid is null then raise exception 'AUTH_REQUIRED'; end if;
 select * into v_profile from public.profiles p where p.user_id=v_uid and p.active=true;
 if not found then raise exception 'PROFILE_NOT_ACTIVE'; end if;
 if v_profile.role<>'staff' then raise exception 'STAFF_REQUIRED'; end if;

 select * into v_own from public.communities c
 where c.active=true and private.community_key(c.name)=private.community_key(v_profile.community)
 order by c.id limit 1;
 if not found then raise exception 'STAFF_COMMUNITY_NOT_FOUND'; end if;

 v_requested:=nullif(btrim(coalesce(p_community,'')),'');
 if v_requested is null then
   v_target:=v_own;
 else
   select * into v_target from public.communities c
   where c.active=true and private.community_key(c.name)=private.community_key(v_requested)
   order by c.id limit 1;
   if not found then raise exception 'COMMUNITY_NOT_FOUND'; end if;
 end if;
 if coalesce(nullif(btrim(v_target.moo),''),'!')<>coalesce(nullif(btrim(v_own.moo),''),'?')
   then raise exception 'COMMUNITY_OUT_OF_SCOPE'; end if;
 v_is_own:=private.community_key(v_target.name)=private.community_key(v_own.name);

 return query
 select h.id,h.hcode,h.house_no,h.moo,h.community,
        h.latitude,h.longitude,h.coordinate_status,h.record_status,
        h.review_required,h.review_reason,h.volunteer_pid,
        case when h.volunteer_pid is null then null else v.display_name end::text,
        case
          when h.volunteer_pid is null and v_is_own then 'staff_fallback'
          when h.volunteer_pid is null then 'unassigned_view'
          when h.volunteer_pid=v_profile.volunteer_pid and v_is_own then 'staff_direct'
          else 'volunteer_assigned'
        end::text,
        case
          when h.volunteer_pid is null and v_is_own then 'เนเธกเนเธกเธต เธญเธชเธก.เธเธนเธเธเนเธฒเธ ยท Staff เธ”เธนเนเธฅเธเธฑเนเธงเธเธฃเธฒเธง'
          when h.volunteer_pid is null then 'เธขเธฑเธเนเธกเนเธกเธต เธญเธชเธก.เธเธนเธเธเนเธฒเธ ยท เธ”เธนเธญเธขเนเธฒเธเน€เธ”เธตเธขเธง'
          when h.volunteer_pid=v_profile.volunteer_pid and v_is_own then 'เธเนเธฒเธเธ—เธตเน Staff เธฃเธฑเธเธเธดเธ”เธเธญเธเนเธ”เธขเธ•เธฃเธ'
          else 'เธญเธชเธก.เธฃเธฑเธเธเธดเธ”เธเธญเธ: '||coalesce(nullif(v.display_name,''),'PID '||h.volunteer_pid::text)
        end::text,
        v_is_own
 from public.houses h
 left join public.volunteers v on v.source_pid=h.volunteer_pid and v.active=true
 where h.superseded_by is null
   and h.verification_status='verified_jhcis'
   and private.community_key(h.community)=private.community_key(v_target.name)
 order by nullif(regexp_replace(coalesce(h.house_no,''),'[^0-9].*$',''),'')::integer nulls last,
          h.house_no,h.id;
end
$body$;

revoke all on function public.staff_household_cards_v2072(text) from public,anon;
grant execute on function public.staff_household_cards_v2072(text) to authenticated;
comment on function public.staff_household_cards_v2072(text) is
'Authenticated active staff: verified current JHCIS houses in assigned community or same-moo read-only community. Null volunteer PID is virtual staff fallback only; this function never assigns or updates houses.';
