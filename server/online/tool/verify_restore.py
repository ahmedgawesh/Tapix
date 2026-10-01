#!/usr/bin/env python3
"""Verify a PostgreSQL backup in a NEW throwaway database, never over existing data."""
from pathlib import Path
from urllib.parse import urlparse,unquote
import json,os,subprocess,uuid
repo=Path(__file__).resolve().parents[3];runtime=repo/'.buildlog/station7/runtime'
config=json.loads((runtime/'environment.json').read_text());u=urlparse(config['TAPBIX_TEST_ADMIN_URL'])
if u.hostname!='127.0.0.1' or u.path!='/tapbix_online_test':raise SystemExit('Refusing non-test source.')
bin=runtime/'pg/usr/lib/postgresql/16/bin'
env={**os.environ,'PGHOST':u.hostname,'PGPORT':str(u.port),'PGUSER':unquote(u.username),'PGPASSWORD':unquote(u.password),'LD_LIBRARY_PATH':str(runtime/'pg/usr/lib/x86_64-linux-gnu')}
def run(args,**kw):return subprocess.run([str(bin/args[0]),*args[1:]],env=env,check=True,**kw)
restore='tapbix_restore_'+uuid.uuid4().hex[:12];dump=runtime/(restore+'.dump')
run(['pg_dump','-Fc','-d','tapbix_online_test','-f',str(dump)]);dump.chmod(0o600)
run(['createdb',restore])
try:
 run(['pg_restore','--exit-on-error','-d',restore,str(dump)])
 sql="SELECT count(*),md5(string_agg(event_hash,',' ORDER BY organization_id,event_id)) FROM tapbix_online.events; SELECT count(*) FROM tapbix_online.deliveries; SELECT count(*) FROM pg_class c JOIN pg_namespace n ON c.relnamespace=n.oid WHERE n.nspname='tapbix_online' AND relrowsecurity AND relforcerowsecurity;"
 original=run(['psql','-d','tapbix_online_test','-tAc',sql],capture_output=True,text=True).stdout
 restored=run(['psql','-d',restore,'-tAc',sql],capture_output=True,text=True).stdout
 if original.strip().splitlines()[-1].strip()!='6':raise SystemExit('Forced RLS policy count is incorrect.')
 if original!=restored:raise SystemExit('Restore verification failed. Retain snapshot for investigation.')
 print('Backup and isolated restore passed: event fingerprints, delivery count and six forced-RLS tables match.')
finally:
 run(['dropdb',restore])
