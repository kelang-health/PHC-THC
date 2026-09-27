-- A Local candidate is a time-limited display result, never an entitlement.
create or replace function private.h7_my_preliminary_v2108(p_request uuid)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare v_user uuid; v_pid bigint; v_row public.h7_preliminary_requests_v2108%rowtype;
        v_status text; v_reason text;
begin
  v_user:=auth.uid();
  select volunteer_pid into v_pid from public.profiles where user_id=v_user
    and active is true and role in ('user','staff');
  if v_user is null or v_pid is null then
    raise exception 'เนเธกเนเธกเธตเธชเธดเธ—เธเธดเนเธ”เธนเธเธณเธเธญ' using errcode='42501';
  end if;
  select * into v_row from public.h7_preliminary_requests_v2108 where id=p_request;
  if not found or v_row.requested_by<>v_user or not exists (
    select 1 from public.health_persons hp
    join public.houses h on h.source_pcucode=hp.house_pcucode and h.hcode=hp.hcode
    where hp.source_pcucode=v_row.source_pcucode and hp.source_pid=v_row.source_pid
      and hp.active is true and h.superseded_by is null
      and h.verification_status='verified_jhcis' and h.volunteer_pid=v_pid
      and private.health_can_access_house(hp.house_pcucode,hp.hcode)
  ) then raise exception 'เนเธกเนเธกเธตเธชเธดเธ—เธเธดเนเธ”เธนเธเธณเธเธญ' using errcode='42501'; end if;
  v_status:=v_row.status;
  v_reason:=v_row.reason_code;
  if v_row.status='local_candidate' and
      (v_row.evaluated_at is null or v_row.evaluated_at>now()
       or v_row.evaluated_at<=now()-interval '24 hours') then
    v_status:='stale';v_reason:='local_result_stale';
  end if;
  return jsonb_build_object('request_id',v_row.id,'status',v_status,
    'reason_code',v_reason,'evaluated_at',v_row.evaluated_at,
    'seat_reserved',false);
end;
$$;
revoke all on function private.h7_my_preliminary_v2108(uuid) from public,anon,authenticated;
grant execute on function private.h7_my_preliminary_v2108(uuid) to authenticated;
