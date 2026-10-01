#!/usr/bin/env python3
"""Start an isolated development PostgreSQL; never touch application databases.
Requires PostgreSQL 16 tools on PATH, or the extracted Ubuntu tools under
.buildlog/station7/runtime/pg. Does not install system packages or expose ports.
"""
from pathlib import Path
import json, os, secrets, shutil, subprocess, shlex
repo=Path(__file__).resolve().parents[3]
runtime=repo/'.buildlog/station7/runtime'; runtime.mkdir(parents=True,exist_ok=True)
bindir=runtime/'pg/usr/lib/postgresql/16/bin'
if not (bindir/'postgres').exists():
    found=shutil.which('pg_ctl')
    if not found: raise SystemExit('Install PostgreSQL tools or extract them to .buildlog/station7/runtime/pg first.')
    bindir=Path(found).parent
secretfile=runtime/'development-secrets.json'
if secretfile.exists(): config=json.loads(secretfile.read_text())
else:
    config={'admin':secrets.token_hex(24),'app':secrets.token_hex(24)}
    secretfile.write_text(json.dumps(config));secretfile.chmod(0o600)
admin=os.environ.get('USER','ahmed'); port='55432'
env={**os.environ,'PGHOST':'127.0.0.1','PGPORT':port,'PGUSER':admin,'PGPASSWORD':config['admin'],'PGDATABASE':'postgres','LD_LIBRARY_PATH':str(runtime/'pg/usr/lib/x86_64-linux-gnu')}
def run(args,**kw):return subprocess.run([str(bindir/args[0]),*args[1:]],env=env,check=True,**kw)
data=runtime/'data'
if not (data/'PG_VERSION').exists():
    pw=runtime/'init-password';pw.write_text(config['admin']);pw.chmod(0o600)
    try: run(['initdb','-D',str(data),'--encoding=UTF8','--no-locale','--auth-host=scram-sha-256','--auth-local=trust',f'--pwfile={pw}'],stdout=subprocess.DEVNULL)
    finally: pw.unlink()
status=subprocess.run([str(bindir/'pg_ctl'),'-D',str(data),'status'],env=env,stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
if status.returncode:run(['pg_ctl','-D',str(data),'-l',str(runtime/'postgres.log'),'-o',f'-h 127.0.0.1 -p {port} -k {shlex.quote(str(runtime))}','start'],stdout=subprocess.DEVNULL)
for db in ['tapbix_online_dev','tapbix_online_test']:
    exists=run(['psql','-tAc',f"SELECT 1 FROM pg_database WHERE datname='{db}'"],capture_output=True,text=True).stdout.strip()
    if not exists:run(['createdb',db])
    exists=run(['psql','-d',db,'-tAc',"SELECT to_regclass('tapbix_online.organizations')"],capture_output=True,text=True).stdout.strip()
    if not exists:run(['psql','-d',db,'-v','ON_ERROR_STOP=1','-q','-f',str(repo/'server/online/sql/001_initial.sql')],stdout=subprocess.DEVNULL)
run(['psql','-v','ON_ERROR_STOP=1','-q'],input=f"ALTER ROLE tapbix_online_app PASSWORD '{config['app']}';",text=True,stdout=subprocess.DEVNULL)
urls={
 'TAPBIX_DEVELOPMENT_ADMIN_URL':f"postgresql://{admin}:{config['admin']}@127.0.0.1:{port}/tapbix_online_dev?sslmode=disable",
 'TAPBIX_DATABASE_URL':f"postgresql://tapbix_online_app:{config['app']}@127.0.0.1:{port}/tapbix_online_dev?sslmode=disable",
 'TAPBIX_TEST_DATABASE_URL':f"postgresql://tapbix_online_app:{config['app']}@127.0.0.1:{port}/tapbix_online_test?sslmode=disable",
 'TAPBIX_TEST_ADMIN_URL':f"postgresql://{admin}:{config['admin']}@127.0.0.1:{port}/tapbix_online_test?sslmode=disable"}
p=runtime/'environment.json';p.write_text(json.dumps(urls));p.chmod(0o600)
print('Isolated PostgreSQL ready at 127.0.0.1:55432. Private configuration: .buildlog/station7/runtime/environment.json')
