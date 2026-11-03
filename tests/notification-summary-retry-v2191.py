"""Synthetic loopback PostgreSQL test. HTTP is stubbed; never sends messages."""
import json, os, pathlib, shutil, socket, subprocess, tempfile
import psycopg2

ROOT = pathlib.Path(__file__).resolve().parents[1]
BIN = pathlib.Path('D:/AppServ/private/osm-phc/phase5c2-postgres/runtime/pgsql/bin')
BASE = pathlib.Path('D:/AppServ/private/supabase-free-backups').resolve()
cluster = pathlib.Path(tempfile.mkdtemp(prefix='notification-test-v2191-', dir=BASE)).resolve()
assert cluster.parent == BASE
with socket.socket() as sock:
    sock.bind(('127.0.0.1', 0)); port = sock.getsockname()[1]
env = {**os.environ, 'PATH': str(BIN)+os.pathsep+os.environ.get('PATH','')}
def run(args):
    return subprocess.run([str(x) for x in args], env=env, stdin=subprocess.DEVNULL,
        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=60,
        creationflags=subprocess.CREATE_NO_WINDOW)
conn = None
try:
    assert run([BIN/'initdb.exe','-D',cluster,'-U','test_admin','--auth-local=trust',
        '--auth-host=trust','--encoding=UTF8','--locale=C']).returncode == 0
    assert run([BIN/'pg_ctl.exe','start','-D',cluster,'-l',cluster/'server.log',
        '-o',f'-h 127.0.0.1 -p {port} -c max_connections=10 -c shared_buffers=32MB','-w']).returncode == 0
    conn = psycopg2.connect(host='127.0.0.1',port=port,user='test_admin',dbname='postgres')
    conn.autocommit = True
    with conn.cursor() as c:
        c.execute('''create role anon; create role authenticated; create role service_role;
        create schema private; create schema extensions; create schema cron;
        create table private.telegram_summary_deliveries_20261016(summary_date date,period text,status text,primary key(summary_date,period));
        create table private.notification_outbox_v190(id bigint primary key,channel text,status text,created_at timestamptz,attempt_count int,last_error text);
        insert into private.notification_outbox_v190 values
        (1,'telegram','sending',now()-interval '2 days',1,''),
        (2,'telegram','sending',now()-interval '1 minute',1,''),
        (3,'telegram','sent',now()-interval '2 days',1,''),
        (4,'line','sending',now()-interval '2 days',1,''),
        (5,'telegram','queued',now()-interval '2 days',0,'');
        create table cron.job(jobid bigint,jobname text,schedule text);
        insert into cron.job values(4,'osm-phc-daily-admin-summary-v2066','0 11 * * *'),
        (12,'osm-phc-morning-admin-summary-v2135','0 5 * * *'),(99,'unrelated','* * * * *');
        create function cron.alter_job(p_jobid bigint,schedule text) returns void language sql as
        $$update cron.job set schedule=$2 where jobid=$1$$;
        create table public.http_fixture(status int,calls int,resets int,complete bool);
        insert into public.http_fixture values(200,0,0,true);
        create type extensions.http_response as (status int);
        create function extensions.http_set_curlopt(text,text) returns bool language sql as $$select true$$;
        create function extensions.http_reset_curlopt() returns bool language plpgsql as $$begin
          update public.http_fixture set resets=resets+1; return true; end$$;
        create function extensions.http_post(text,text,text) returns extensions.http_response language plpgsql as $$
        declare v int;begin
          update public.http_fixture set calls=calls+1 returning status into v;
          if v=200 and (select complete from public.http_fixture) then
            insert into private.telegram_summary_deliveries_20261016
              values((current_setting('test.summary_clock')::timestamptz at time zone 'Asia/Bangkok')::date,($2::jsonb->>'period'),'sent')
              on conflict(summary_date,period) do update set status='sent';
          end if;
          return row(v)::extensions.http_response;
        end$$;''')
        migration = (ROOT/'supabase/migrations/20261103070226_notification_summary_retry_v2191.sql').read_text()
        c.execute(migration)
        c.execute("select id,status,attempt_count from private.notification_outbox_v190 order by id")
        assert c.fetchall() == [(1,'failed',5),(2,'sending',1),(3,'sent',1),(4,'sending',1),(5,'queued',0)]
        c.execute("select prior_state->>'status',prior_state->>'attempt_count' from private.notification_delivery_review_v2191")
        assert c.fetchall() == [('sending','1')]
        c.execute(migration)  # repeat does not rewrite the original audit state
        c.execute('select count(*) from private.notification_delivery_review_v2191'); assert c.fetchone()[0] == 1
        c.execute('select schedule from cron.job order by jobid')
        assert c.fetchall() == [('0,5,10,15,20 11 * * *',),('0,5,10,15,20 5 * * *',),('* * * * *',)]
        cases = 0
        for period, time, expected in [('noon','04:59',False),('noon','05:00',True),
            ('noon','05:20',True),('noon','05:21',False),('evening','11:00',True),
            ('evening','11:20',True),('evening','11:21',False),('evening','05:00',False),
            ('invalid','05:00',False),(None,'05:00',False)]:
            c.execute('select private.summary_delivery_due_v2191(%s,%s::timestamptz)',(period,'2026-11-03 '+time+'Z'))
            assert c.fetchone()[0] is expected; cases += 1
        # Inject the clock only in this synthetic fixture, retaining the real
        # due function and all production wrapper logic for retry tests.
        c.execute("select pg_get_functiondef('private.summary_delivery_due_v2191(text,timestamptz)'::regprocedure)")
        c.execute(c.fetchone()[0].replace('private.summary_delivery_due_v2191(', 'private.real_due_fixture('))
        c.execute('''create or replace function private.summary_delivery_due_v2191(p_period text,p_at timestamptz default now())
          returns bool language sql stable security definer set search_path='' as $$
          select private.real_due_fixture(p_period,current_setting('test.summary_clock')::timestamptz)$$;
          select set_config('test.summary_clock','2026-11-03 05:00Z',false);''')
        c.execute('update public.http_fixture set status=502')
        try:
            c.execute("select private.invoke_daily_admin_summary_v2136('noon',false)")
            raise AssertionError('502 must fail')
        except psycopg2.errors.RaiseException as e:
            assert 'SUMMARY_HTTP_502' in str(e)
        c.execute('update public.http_fixture set status=200')
        c.execute("select private.invoke_daily_admin_summary_v2136('noon',false)"); assert c.fetchone()[0] == 200
        for _ in range(4):
            c.execute("select private.invoke_daily_admin_summary_v2136('noon',false)"); assert c.fetchone()[0] == 204
        c.execute('select calls,resets from public.http_fixture'); assert c.fetchone() == (1,1)
        for period, test in [('wrong',False),(None,False),('evening',True)]:
            try:
                c.execute('select private.invoke_daily_admin_summary_v2136(%s,%s)',(period,test))
                raise AssertionError('invalid/test invocation must fail')
            except psycopg2.errors.RaiseException: pass
        c.execute("select has_function_privilege('anon','private.invoke_daily_admin_summary_v2136(text,boolean)','execute'),has_function_privilege('authenticated','private.summary_delivery_due_v2191(text,timestamptz)','execute'),has_table_privilege('anon','private.notification_delivery_review_v2191','select')")
        assert c.fetchone() == (False,False,False)
        c.execute("select relrowsecurity from pg_class where oid='private.notification_delivery_review_v2191'::regclass"); assert c.fetchone()[0]
        print(json.dumps({'passed':True,'window_cases':cases,'failure_then_retry':True,
            'sent_skips_http':True,'stale_quarantine_preserves_state':True,'migration_idempotent':True,
            'permissions_denied':True,'http_stubbed_no_messages_sent':True}),flush=True)
finally:
    if conn: conn.close()
    if (cluster/'postmaster.pid').exists():
        assert run([BIN/'pg_ctl.exe','stop','-D',cluster,'-m','fast','-w']).returncode == 0
    assert cluster.parent == BASE and cluster.name.startswith('notification-test-v2191-')
    shutil.rmtree(cluster)
