#!/usr/bin/env python3
"""Select the least privileged local configuration for the requested command."""
from pathlib import Path
import json,os,subprocess,sys
repo=Path(__file__).resolve().parents[3]
config=json.loads((repo/'.buildlog/station7/runtime/environment.json').read_text())
command=sys.argv[1:] or ['run','bin/server.dart']
if command[0]=='test':
    keys=('TAPBIX_TEST_DATABASE_URL','TAPBIX_TEST_ADMIN_URL')
elif 'bin/provision_development.dart' in command:
    keys=('TAPBIX_DEVELOPMENT_ADMIN_URL',)
else:
    keys=('TAPBIX_DATABASE_URL',)
env={k:v for k,v in os.environ.items() if k not in config}
env.update({k:config[k] for k in keys})
raise SystemExit(subprocess.call(['dart',*command],cwd=repo/'server/online',env=env))
