-- OSM-PHC v2.0.50 corrective finalizer: exact JHCIS authoritative house set
begin;

create or replace function public.service_finalize_jhcis_house_verification_v2050(
  p_source_pcucode text,
  p_hcodes jsonb
) returns jsonb
language plpgsql security definer
set search_path=public,private,extensions
as $$
declare
  v_pcucode text:=btrim(coalesce(p_source_pcucode,''));
  v_demoted integer:=0;
  v_superseded integer:=0;
  v_canonical integer:=0;
begin
  if coalesce(auth.role(),'')<>'service_role' then raise exception 'SERVICE_ROLE_REQUIRED'; end if;
  if v_pcucode='' then raise exception 'SOURCE_PCUCODE_REQUIRED'; end if;
  if p_hcodes is null or jsonb_typeof(p_hcodes)<>'array' then raise exception 'HCODES_ARRAY_REQUIRED'; end if;

  select count(distinct value) into v_canonical
  from jsonb_array_elements_text(p_hcodes)
  where btrim(value)<>'';

  -- Rows not present in jhcisdb.house are never allowed to remain operationally verified.
  update public.houses h
  set verification_status=case
        when h.entry_source='field' then 'pending_jhcis_create'
        else 'review_required'
      end,
      jhcis_verified_at=null,
      jhcis_verified_hcode=null,
      verification_note=case
        when h.entry_source='field' then 'เน€เธเธดเนเธกเธเธฒเธ Cloud ยท เธขเธฑเธเนเธกเนเธเธเนเธ jhcisdb.house ยท เธฃเธญ Admin เธ•เธฃเธงเธ/เธเธฑเธเธ—เธถเธ JHCIS'
        else 'เนเธกเนเธญเธขเธนเนเนเธเธเธธเธ” canonical jhcisdb.house เธฅเนเธฒเธชเธธเธ” ยท เน€เธเนเธเธเนเธญเธกเธนเธฅเนเธงเนเน€เธเธทเนเธญ Admin เธ•เธฃเธงเธเธชเธญเธ'
      end,
      updated_at=now()
  where h.source_pcucode=v_pcucode
    and h.superseded_by is null
    and h.verification_status='verified_jhcis'
    and not exists (
      select 1 from jsonb_array_elements_text(p_hcodes) x(value)
      where btrim(x.value)=btrim(h.hcode)
    );
  get diagnostics v_demoted=row_count;

  update public.houses
  set verification_status='superseded',
      verification_note='เนเธ—เธเธ—เธตเนเธ”เนเธงเธข JHCIS canonical',
      updated_at=now()
  where source_pcucode=v_pcucode
    and superseded_by is not null
    and verification_status<>'superseded';
  get diagnostics v_superseded=row_count;

  return jsonb_build_object(
    'source_pcucode',v_pcucode,
    'canonical_hcodes',v_canonical,
    'demoted_not_in_jhcis',v_demoted,
    'superseded_normalized',v_superseded,
    'source_of_truth','jhcisdb.house',
    'jhcis_write_back',false
  );
end;
$$;

revoke all on function public.service_finalize_jhcis_house_verification_v2050(text,jsonb) from public,anon,authenticated;

grant execute on function public.service_finalize_jhcis_house_verification_v2050(text,jsonb) to service_role;

insert into public.app_settings(key,value)
values('jhcis_authoritative_finalize_v2050',jsonb_build_object(
  'version','2.0.50',
  'source_of_truth','jhcisdb.house',
  'finalize_policy','only hcodes present in latest full JHCIS canonical set may remain verified_jhcis',
  'field_not_in_jhcis','pending_jhcis_create',
  'legacy_not_in_jhcis','review_required',
  'physical_delete',false,
  'jhcis_write_back',false
)) on conflict(key) do update set value=excluded.value,updated_at=now();

notify pgrst,'reload schema';

commit;
