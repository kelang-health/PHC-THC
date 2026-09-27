-- OSM-PHC Cloud v2.0.6
-- 1) DSPM preliminary abnormal -> staff/admin follow-up + admin in-app notification.
-- 2) Optional 15-34 campaign controlled by admin date window; not part of primary field target/coverage.
-- 3) Standalone preliminary mental-health 2Q for campaign use; positive result creates staff/admin follow-up.
-- Existing JHCIS sync stays read-only.

begin;

create table if not exists public.age_screening_campaigns_v206 (
  campaign_key text primary key,
  title text not null,
  enabled boolean not null default false,
  start_date date,
  end_date date,
  ncd_enabled boolean not null default false,
  mental_2q_enabled boolean not null default false,
  target_mode text not null default 'optional' check (target_mode in ('optional','primary')),
  note text not null default '',
  updated_by uuid references auth.users(id),
  updated_at timestamptz not null default now(),
  constraint age_campaign_dates_v206 check (
    (start_date is null and end_date is null)
    or (start_date is not null and end_date is not null and end_date>=start_date)
  )
);

insert into public.age_screening_campaigns_v206(
  campaign_key,title,enabled,start_date,end_date,ncd_enabled,mental_2q_enabled,target_mode,note
) values (
  'youth_15_34','เธเธฑเธ”เธเธฃเธญเธเน€เธชเธฃเธดเธกเธงเธฑเธข 15โ€“34 เธเธต',false,null,null,true,true,'optional',
  'Admin เน€เธเธดเธ”เนเธเนเน€เธเนเธเธเนเธงเธเน€เธงเธฅเธฒเนเธ”เน; เนเธกเนเธฃเธงเธก Operational Task Completion เธซเธฅเธฑเธ'
)
on conflict(campaign_key) do nothing;

alter table public.age_screening_campaigns_v206 enable row level security;

revoke all on public.age_screening_campaigns_v206 from public,anon,authenticated;

grant select on public.age_screening_campaigns_v206 to authenticated;

drop policy if exists age_campaign_select_v206 on public.age_screening_campaigns_v206;

create policy age_campaign_select_v206 on public.age_screening_campaigns_v206
for select to authenticated using (true);

create or replace function public.youth_campaign_status_v206()
returns jsonb
language plpgsql stable security definer
set search_path=''
as $$
declare
  c public.age_screening_campaigns_v206%rowtype;
  v_role text:=private.current_role();
  v_active boolean:=false;
begin
  if auth.uid() is null then raise exception 'AUTH_REQUIRED'; end if;
  select * into c from public.age_screening_campaigns_v206 where campaign_key='youth_15_34';
  if not found then raise exception 'CAMPAIGN_CONFIG_MISSING'; end if;
  v_active:=c.enabled and c.start_date is not null and c.end_date is not null and current_date between c.start_date and c.end_date;
  return jsonb_build_object(
    'campaign_key',c.campaign_key,'title',c.title,'enabled',c.enabled,
    'start_date',c.start_date,'end_date',c.end_date,'active_now',v_active,
    'visible_now',v_active and v_role in ('user','staff','admin'),
    'ncd_enabled',c.ncd_enabled,'mental_2q_enabled',c.mental_2q_enabled,
    'target_mode',c.target_mode,
    'counted_in_primary_target',false,
    'role',v_role,'note',c.note
  );
end;
$$;

revoke all on function public.youth_campaign_status_v206() from public,anon;

grant execute on function public.youth_campaign_status_v206() to authenticated;

create or replace function public.admin_set_youth_campaign_v206(
  p_enabled boolean,
  p_start_date date,
  p_end_date date,
  p_ncd_enabled boolean,
  p_mental_2q_enabled boolean,
  p_note text default ''
) returns jsonb
language plpgsql security definer
set search_path=''
as $$
begin
  if auth.uid() is null or private.current_role()<>'admin' then raise exception 'ADMIN_REQUIRED'; end if;
  if coalesce(p_enabled,false) then
    if p_start_date is null or p_end_date is null then raise exception 'CAMPAIGN_DATES_REQUIRED'; end if;
    if p_end_date<p_start_date then raise exception 'CAMPAIGN_DATE_RANGE_INVALID'; end if;
    if not coalesce(p_ncd_enabled,false) and not coalesce(p_mental_2q_enabled,false) then raise exception 'CAMPAIGN_MODULE_REQUIRED'; end if;
  end if;

  update public.age_screening_campaigns_v206
  set enabled=coalesce(p_enabled,false),
      start_date=p_start_date,
      end_date=p_end_date,
      ncd_enabled=coalesce(p_ncd_enabled,false),
      mental_2q_enabled=coalesce(p_mental_2q_enabled,false),
      target_mode='optional',
      note=left(btrim(coalesce(p_note,'')),500),
      updated_by=auth.uid(),updated_at=now()
  where campaign_key='youth_15_34';

  insert into public.health_audit_log(operator_id,action,entity,entity_id,severity,details)
  values(auth.uid(),'UPDATE','screening_campaign','youth_15_34','config',jsonb_build_object(
    'enabled',coalesce(p_enabled,false),'start_date',p_start_date,'end_date',p_end_date,
    'ncd_enabled',coalesce(p_ncd_enabled,false),'mental_2q_enabled',coalesce(p_mental_2q_enabled,false),
    'target_mode','optional'));

  return public.youth_campaign_status_v206();
end;
$$;

revoke all on function public.admin_set_youth_campaign_v206(boolean,date,date,boolean,boolean,text) from public,anon;

grant execute on function public.admin_set_youth_campaign_v206(boolean,date,date,boolean,boolean,text) to authenticated;

create table if not exists public.mental_health_2q_screenings_v206 (
  id uuid primary key default extensions.gen_random_uuid(),
  session_id uuid not null unique references public.screening_sessions(id) on delete cascade,
  source_pcucode text not null,
  source_pid bigint not null,
  screened_on date not null,
  q1 boolean not null,
  q2 boolean not null,
  positive boolean not null,
  result_label text not null,
  screened_by uuid not null references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  foreign key(source_pcucode,source_pid) references public.health_persons(source_pcucode,source_pid)
);

create index if not exists mental2q_person_v206_idx on public.mental_health_2q_screenings_v206(source_pcucode,source_pid,screened_on desc);

alter table public.mental_health_2q_screenings_v206 enable row level security;

revoke all on public.mental_health_2q_screenings_v206 from public,anon,authenticated;

grant select on public.mental_health_2q_screenings_v206 to authenticated;

drop policy if exists mental2q_select_v206 on public.mental_health_2q_screenings_v206;

create policy mental2q_select_v206 on public.mental_health_2q_screenings_v206
for select to authenticated using(private.health_can_access_person(source_pcucode,source_pid));

create or replace function private.youth_campaign_active_on_v206(p_day date)
returns boolean
language sql stable security definer
set search_path=''
as $$
  select coalesce(c.enabled,false)
    and c.start_date is not null and c.end_date is not null
    and p_day between c.start_date and c.end_date
  from public.age_screening_campaigns_v206 c
  where c.campaign_key='youth_15_34'
$$;

revoke all on function private.youth_campaign_active_on_v206(date) from public,anon,authenticated;

create or replace function public.save_mental_health_2q_v206(
  p_session_id uuid,p_q1 boolean,p_q2 boolean
) returns jsonb
language plpgsql security definer
set search_path=''
as $$
declare
  s public.screening_sessions%rowtype;
  c public.age_screening_campaigns_v206%rowtype;
  v_positive boolean;
  v_id uuid;
begin
  if auth.uid() is null or private.current_role() not in ('user','staff','admin') then raise exception 'AUTH_REQUIRED'; end if;
  select * into s from public.screening_sessions where id=p_session_id for update;
  if not found or not private.health_can_access_person(s.source_pcucode,s.source_pid) then raise exception 'SESSION_OUT_OF_SCOPE'; end if;
  if s.route<>'youth_15_34' or s.age_years<15 or s.age_years>34 then raise exception 'MENTAL_2Q_NOT_APPLICABLE'; end if;
  select * into c from public.age_screening_campaigns_v206 where campaign_key='youth_15_34';
  if not found or not c.mental_2q_enabled or not private.youth_campaign_active_on_v206(s.screening_date) then raise exception 'MENTAL_2Q_CAMPAIGN_CLOSED'; end if;
  if p_q1 is null or p_q2 is null then raise exception 'MENTAL_2Q_BOTH_REQUIRED'; end if;

  v_positive:=p_q1 or p_q2;
  insert into public.mental_health_2q_screenings_v206(
    session_id,source_pcucode,source_pid,screened_on,q1,q2,positive,result_label,screened_by
  ) values (
    s.id,s.source_pcucode,s.source_pid,s.screening_date,p_q1,p_q2,v_positive,
    case when v_positive then 'เธเธเธชเธฑเธเธเธฒเธ“เธ—เธตเนเธเธงเธฃเธเธฃเธฐเน€เธกเธดเธเธ•เนเธญเนเธ”เธขเน€เธเนเธฒเธซเธเนเธฒเธ—เธตเน' else 'เนเธกเนเธเธเธชเธฑเธเธเธฒเธ“เธเธฒเธ 2Q เน€เธเธทเนเธญเธเธ•เนเธ' end,auth.uid()
  )
  on conflict(session_id) do update set
    q1=excluded.q1,q2=excluded.q2,positive=excluded.positive,result_label=excluded.result_label,
    screened_by=auth.uid(),updated_at=now()
  returning id into v_id;

  if v_positive then
    insert into public.screening_followups(session_id,source_pcucode,source_pid,followup_type,domain_code,priority,summary,created_by)
    values(s.id,s.source_pcucode,s.source_pid,'mental_health','2q','orange','เธเธฅ 2Q เน€เธเธทเนเธญเธเธ•เนเธเธเธงเธฃเนเธซเนเน€เธเนเธฒเธซเธเนเธฒเธ—เธตเนเธเธฃเธฐเน€เธกเธดเธเธ•เนเธญ',auth.uid())
    on conflict(session_id,followup_type,domain_code) do update set status='open',summary=excluded.summary,completed_at=null;
  else
    update public.screening_followups
    set status='done',completed_at=coalesce(completed_at,now()),updated_at=now()
    where session_id=s.id and followup_type='mental_health' and domain_code='2q' and status in ('open','in_progress');
  end if;

  insert into public.health_audit_log(operator_id,action,entity,entity_id,source_pcucode,source_pid,severity,details)
  values(auth.uid(),'UPSERT','mental_health_2q',v_id::text,s.source_pcucode,s.source_pid,
    case when v_positive then 'orange' else 'normal' end,
    jsonb_build_object('screened_on',s.screening_date,'positive',v_positive,'campaign_key','youth_15_34'));

  return jsonb_build_object(
    'ok',true,'id',v_id,'positive',v_positive,
    'result_label',case when v_positive then 'เธเธเธชเธฑเธเธเธฒเธ“เธ—เธตเนเธเธงเธฃเธเธฃเธฐเน€เธกเธดเธเธ•เนเธญเนเธ”เธขเน€เธเนเธฒเธซเธเนเธฒเธ—เธตเน' else 'เนเธกเนเธเธเธชเธฑเธเธเธฒเธ“เธเธฒเธ 2Q เน€เธเธทเนเธญเธเธ•เนเธ' end,
    'followup_created',v_positive
  );
end;
$$;

revoke all on function public.save_mental_health_2q_v206(uuid,boolean,boolean) from public,anon;

grant execute on function public.save_mental_health_2q_v206(uuid,boolean,boolean) to authenticated;

-- Generic in-app admin notification for newly opened DSPM / mental-health follow-up.
-- No person identifier is copied to the external message channel; these remain in-app only.
create or replace function private.notify_screening_followup_admin_v206()
returns trigger
language plpgsql security definer
set search_path=''
as $$
declare v_should boolean:=false;v_title text;v_body text;
begin
  if new.followup_type not in ('child_development','mental_health') then return new; end if;
  if tg_op='INSERT' and new.status='open' then v_should:=true; end if;
  if tg_op='UPDATE' and new.status='open' and old.status is distinct from new.status then v_should:=true; end if;
  if not v_should then return new; end if;

  if new.followup_type='child_development' then
    v_title:='OSM-PHC: เธกเธตเธเธฅเธเธฑเธ”เธเธฃเธญเธเธเธฑเธ’เธเธฒเธเธฒเธฃเน€เธ”เนเธเนเธซเนเธ•เธดเธ”เธ•เธฒเธก';
    v_body:='เธกเธตเธเธฅเธเธฑเธ”เธเธฃเธญเธเธเธฑเธ’เธเธฒเธเธฒเธฃเน€เธ”เนเธเน€เธเธทเนเธญเธเธ•เนเธเธ—เธตเนเธเธงเธฃเนเธซเนเน€เธเนเธฒเธซเธเนเธฒเธ—เธตเนเธเธฃเธฐเน€เธกเธดเธเธ•เนเธญ เธเธฃเธธเธ“เธฒเน€เธเธดเธ”เธเธฒเธเธ•เธดเธ”เธ•เธฒเธกเนเธเธฃเธฐเธเธ';
  else
    v_title:='OSM-PHC: เธกเธตเธเธฅเธเธฑเธ”เธเธฃเธญเธเธชเธธเธเธ เธฒเธเธเธดเธ•เนเธซเนเธ•เธดเธ”เธ•เธฒเธก';
    v_body:='เธกเธตเธเธฅเธเธฑเธ”เธเธฃเธญเธเธชเธธเธเธ เธฒเธเธเธดเธ•เน€เธเธทเนเธญเธเธ•เนเธเธ—เธตเนเธเธงเธฃเนเธซเนเน€เธเนเธฒเธซเธเนเธฒเธ—เธตเนเธเธฃเธฐเน€เธกเธดเธเธ•เนเธญ เธเธฃเธธเธ“เธฒเน€เธเธดเธ”เธเธฒเธเธ•เธดเธ”เธ•เธฒเธกเนเธเธฃเธฐเธเธ';
  end if;
  perform private.emit_admin_notification_v190(
    'screening.followup','warning',v_title,v_body,'?panel=work',
    jsonb_build_object('followup_type',new.followup_type,'priority',new.priority),false
  );
  return new;
end;
$$;

revoke all on function private.notify_screening_followup_admin_v206() from public,anon,authenticated;

drop trigger if exists trg_notify_screening_followup_admin_v206 on public.screening_followups;

create trigger trg_notify_screening_followup_admin_v206
after insert or update of status on public.screening_followups
for each row execute function private.notify_screening_followup_admin_v206();

-- Reporting projection for Local/Cloud drill-down. Campaign is intentionally not added to field_work_items_v200.
create or replace view public.field_export_mental2q_v206
with (security_invoker=true)
as
select m.id,m.screened_on,m.source_pcucode,m.source_pid,p.display_name,
       h.hcode,h.house_no,h.moo,h.community,h.volunteer_pid,
       m.q1,m.q2,m.positive,m.result_label,m.created_at,m.updated_at
from public.mental_health_2q_screenings_v206 m
join public.health_persons p on p.source_pcucode=m.source_pcucode and p.source_pid=m.source_pid
join public.houses h on h.source_pcucode=p.house_pcucode and h.hcode=p.hcode;

grant select on public.field_export_mental2q_v206 to authenticated;

insert into public.app_settings(key,value)
values('youth_campaign_v206',jsonb_build_object(
  'version','2.0.6','age_range','15-34','default_enabled',false,
  'ncd_min_age',18,'mental_2q',true,'roles',jsonb_build_array('user','staff'),
  'primary_target',false,'field_work_coverage_effect',false,
  'positive_followup_owner','staff/admin','jhcis_write_back',false
))
on conflict(key) do update set value=excluded.value,updated_at=now();

commit;
