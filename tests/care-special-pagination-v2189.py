"""Isolated synthetic PostgreSQL fixture on localhost:55438; creates and removes its own test DB. Never targets Supabase."""
import json,pathlib,uuid
import psycopg2
from psycopg2 import sql
ROOT=pathlib.Path(__file__).resolve().parents[1]
admin=psycopg2.connect(host='127.0.0.1',port=55438,user='restore_drill',dbname='postgres');admin.autocommit=True
db='egress_test_'+uuid.uuid4().hex[:8];conn=None
try:
 with admin.cursor() as c:c.execute(sql.SQL('create database {}').format(sql.Identifier(db)))
 conn=psycopg2.connect(host='127.0.0.1',port=55438,user='restore_drill',dbname=db);conn.autocommit=True
 with conn.cursor() as c:
  c.execute('''create schema auth;
  create function auth.uid() returns uuid language sql stable as $$select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid$$;
  create table profiles(user_id uuid primary key,role text,active boolean,volunteer_pid bigint,community text,moo text);
  create table houses(source_pcucode text,hcode text,house_no text,moo text,community text,volunteer_pid bigint,verification_status text,superseded_by uuid,primary key(source_pcucode,hcode));
  create table health_persons(source_pcucode text,source_pid bigint,display_name text,house_pcucode text,hcode text,birth_date date,active boolean,service_population_eligible boolean,is_disabled boolean,adl_group_code text,adl_assessed_on date);
  insert into profiles values
  ('00000000-0000-0000-0000-000000000001','admin',true,1,'A','1'),
  ('00000000-0000-0000-0000-000000000002','staff',true,1,'A','1'),
  ('00000000-0000-0000-0000-000000000003','user',true,1,'A','1'),
  ('00000000-0000-0000-0000-000000000004','user',false,1,'A','1'),
  ('00000000-0000-0000-0000-000000000005',null,true,1,'A','1');
  insert into houses values ('pcu','1','10','1','A',1,'verified_jhcis',null),('pcu','2','20','1','B',2,'verified_jhcis',null),('pcu','3','30','2','C',3,'verified_jhcis',null),('other','1','40','2','D',3,'verified_jhcis',null),('pcu','4','84','1','School',1,'verified_jhcis',null),('pcu','5','50','1','A',1,'pending',null),('pcu','6','60','1','A',1,'verified_jhcis','11111111-1111-1111-1111-111111111111');
  insert into health_persons select 'pcu',i,'Person '||lpad(i::text,3,'0'),'pcu',(1+(i%3))::text,'1940-01-01',true,true,true,case when i%2=0 then '1B1281' else '1B1282' end,current_date from generate_series(1,100)i;
  insert into health_persons values ('pcu',101,'Wrong PCU','other','1','1940-01-01',true,true,true,'1B1281',current_date),('pcu',102,'School','pcu','4','1940-01-01',false,false,true,'1B1281',current_date),('pcu',103,'Pending','pcu','5','1940-01-01',true,true,true,'1B1281',current_date),('pcu',104,'Old house','pcu','6','1940-01-01',true,true,true,'1B1281',current_date),('pcu',105,'Young','pcu','1','2020-01-01',true,true,true,'1B1281',current_date);
  alter table profiles enable row level security;alter table houses enable row level security;alter table health_persons enable row level security;
  create policy own on profiles for select to authenticated using(user_id=auth.uid());
  create policy allowed on houses for select to authenticated using((select role from profiles where user_id=auth.uid())='admin' or ((select active from profiles where user_id=auth.uid()) and ((select role from profiles where user_id=auth.uid())='staff' and moo=(select moo from profiles where user_id=auth.uid()) or (select role from profiles where user_id=auth.uid())='user' and volunteer_pid=(select volunteer_pid from profiles where user_id=auth.uid()))));
  create policy allowed on health_persons for select to authenticated using(active and exists(select 1 from houses h where h.source_pcucode=house_pcucode and h.hcode=health_persons.hcode));
  grant usage on schema public,auth to authenticated,anon;grant select on profiles,houses,health_persons to authenticated;''')
  c.execute((ROOT/'supabase/migrations/20261103041223_egress_scoped_special_people_v2189.sql').read_text())
  c.execute('set role authenticated')
  checked=0
  for actor in (1,2,3):
   c.execute("select set_config('request.jwt.claim.sub',%s,false)",(f'00000000-0000-0000-0000-{actor:012}',))
   for scope,owner in ([('all',None)] if actor==1 else [('self',None),('community',None),('volunteer',2)] if actor==2 else [('self',None),('all',3)]):
    for group in ('disabled','homebound','bedridden'):
     own=None if actor==1 or actor==2 and scope=='community' else owner if actor==2 and scope=='volunteer' else 1
     condition='p.is_disabled' if group=='disabled' else "p.adl_group_code=%s and p.birth_date <= ((now() at time zone 'Asia/Bangkok')::date - interval '60 years')::date"
     params=[] if group=='disabled' else ['1B1281' if group=='homebound' else '1B1282']
     query="select p.source_pid from health_persons p join houses h on h.source_pcucode=p.house_pcucode and h.hcode=p.hcode where p.active and p.service_population_eligible and h.verification_status='verified_jhcis' and h.superseded_by is null and "+condition
     if own is not None:query+=' and h.volunteer_pid=%s';params+=[own]
     query+=' order by p.display_name,p.source_pcucode,p.source_pid';c.execute(query,params);expected=[x[0] for x in c.fetchall()]
     actual=[]
     while True:
      c.execute('select source_pid from care_special_people_page_v2189(%s,%s,%s,\'\',31,%s)',(group,scope,owner,len(actual)));page=[x[0] for x in c.fetchall()];actual+=page[:30]
      if len(page)<=30:break
     assert actual==expected,(actor,scope,group,len(actual),len(expected));checked+=1
   c.execute("select count(*) from care_special_people_page_v2189('disabled','self',null,'not found',31,0)");assert c.fetchone()[0]==0
  for actor in (4,5,99):
   c.execute("select set_config('request.jwt.claim.sub',%s,false)",(f'00000000-0000-0000-0000-{actor:012}',))
   try:c.execute("select * from care_special_people_page_v2189('disabled')");raise AssertionError('AUTH NOT DENIED')
   except psycopg2.errors.InsufficientPrivilege:pass
  c.execute('reset role');c.execute('set role anon')
  try:c.execute("select * from care_special_people_page_v2189('disabled')");raise AssertionError('ANON NOT DENIED')
  except psycopg2.errors.InsufficientPrivilege:pass
  print(json.dumps({'passed':True,'role_scope_group_parity_cases':checked,'search':True,'pagination':True,'inactive_missing_null_role_denied':True,'anon_denied':True,'school_pending_superseded_excluded':True}))
finally:
 if conn:conn.close()
 with admin.cursor() as c:c.execute(sql.SQL('drop database {}').format(sql.Identifier(db)))
 admin.close()
