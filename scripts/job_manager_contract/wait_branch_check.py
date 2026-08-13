#!/usr/bin/env python3
"""
Deterministic check of the deployed job_manager's WAIT branch, with NO database write and
NO cluster job. We import the real module and call the real _resolve_dependency, only
substituting what get_parent_jobs returns — the same thing a different DB state would do.

Log dir is redirected to a temp dir so importing the module cannot append to the shared
/misc/fgcz01/sushi/job_logs/ files.

Point it at a job_manager checkout with JOB_MANAGER_DIR (default: /srv/sushi/masa_job_manager).
"""
import os
import sys
import tempfile

tmp = tempfile.mkdtemp(prefix='task9_jm_probe_')
os.environ.setdefault('FAIL_RETRY_COUNTER', '2')
os.environ.setdefault('DAEMON_ITERATION_TIMER', '20')
os.environ['JOB_MANAGER_LOG_DIR'] = tmp + '/'
os.environ.setdefault('JOB_LOG_TEMPORARY_DIR', tmp + '/')
os.environ.setdefault('METHODS_LOG_TEMPORARY_DIR', tmp + '/')
os.environ.setdefault('SUSHI_HOST', 'http://127.0.0.1:1')
os.environ.setdefault('COPY_CMD', '/bin/true')

JOB_MANAGER_DIR = os.environ.get('JOB_MANAGER_DIR', '/srv/sushi/masa_job_manager')
if not os.path.isdir(JOB_MANAGER_DIR):
    sys.exit(f'job_manager checkout not found: {JOB_MANAGER_DIR} (set JOB_MANAGER_DIR)')
sys.path.insert(0, JOB_MANAGER_DIR)
sys.path.insert(0, os.path.join(JOB_MANAGER_DIR, 'src'))

import importlib
import types

# The daemon runs in its own conda env; mysql-connector is not in this interpreter.
# Stub it so the module imports. We never open a connection — the cursor we pass is None
# and get_parent_jobs is substituted, so no query is ever issued.
if 'mysql' not in sys.modules:
    _mysql = types.ModuleType('mysql')
    _conn = types.ModuleType('mysql.connector')

    def _refuse(*a, **k):
        raise AssertionError('this probe must never open a DB connection')

    _conn.connect = _refuse
    _conn.Error = Exception
    _mysql.connector = _conn
    sys.modules['mysql'] = _mysql
    sys.modules['mysql.connector'] = _conn

# Same for the other third-party imports the daemon does at module scope but that
# _resolve_dependency does not touch. Anything actually invoked would raise loudly.
for _name in ('daemon', 'daemon.pidfile', 'requests', 'dotenv'):
    if _name.split('.')[0] in sys.modules:
        continue
    try:
        importlib.import_module(_name)
    except ImportError:
        _m = types.ModuleType(_name)
        _m.__getattr__ = lambda attr, _n=_name: (_ for _ in ()).throw(
            AssertionError(f'probe must not use {_n}.{attr}'))
        sys.modules[_name] = _m
        if _name == 'dotenv':
            _m.load_dotenv = lambda *a, **k: None

scheduler = importlib.import_module('src.scheduler')

print('module        :', scheduler.__file__)
print('log redirected:', tmp)
print('_ACTIVE_STATUSES =', sorted(scheduler._ACTIVE_STATUSES))
print()

CHILD = {'id': 999001, 'input_dataset_id': 804, 'status': 'CREATED',
         'script_path': '/tmp/does_not_matter.sh'}

CASES = [
    ('all parents COMPLETED (today\'s normal chained submit, parents already done)',
     [{'submit_job_id': 319613, 'status': 'COMPLETED'},
      {'submit_job_id': 319616, 'status': 'COMPLETED'}],
     ''),
    ('parents RUNNING with SLURM ids (what actually happened at 15:07 today)',
     [{'submit_job_id': 319613, 'status': 'RUNNING'},
      {'submit_job_id': 319616, 'status': 'RUNNING'}],
     '--dependency=afterany:319613:319616'),
    ('parents still CREATED, no SLURM id yet -> the never-fired WAIT branch',
     [{'submit_job_id': None, 'status': 'CREATED'},
      {'submit_job_id': None, 'status': 'CREATED'}],
     'WAIT'),
    ('MIXED: one parent submitted, one still CREATED -> WAIT (all-or-nothing)',
     [{'submit_job_id': 319613, 'status': 'RUNNING'},
      {'submit_job_id': None, 'status': 'CREATED'}],
     'WAIT'),
    ('legacy methods row parked beside submitted siblings -> WAIT (the realistic trigger)',
     [{'submit_job_id': 319613, 'status': 'COMPLETED'},
      {'submit_job_id': None, 'status': 'WAITING_FOR_METHODS'}],
     'WAIT'),
    ('parent wedged in SCRIPT_NOT_FOUND_TRY_1 -> WAIT (active via the startswith check)',
     [{'submit_job_id': None, 'status': 'SCRIPT_NOT_FOUND_TRY_1'}],
     'WAIT'),
    ('parent FAILED -> no active parents -> NO dependency, child released (afterany hazard)',
     [{'submit_job_id': 319613, 'status': 'FAILED'}],
     ''),
    ('dataset with no producing jobs at all (a root/B-Fabric dataset)',
     [],
     ''),
]

orig = scheduler.get_parent_jobs
ok = True
for label, parents, expected in CASES:
    scheduler.get_parent_jobs = lambda cursor, ds, _p=parents: list(_p)
    got = scheduler._resolve_dependency(None, CHILD)
    verdict = 'PASS' if got == expected else 'MISMATCH'
    if got != expected:
        ok = False
    print(f'{verdict:9} {label}')
    print(f'          expected={expected!r}  got={got!r}')
scheduler.get_parent_jobs = orig

print()
print('ALL AS DOCUMENTED' if ok else 'SOME CASES DIFFER FROM THE DOCUMENTED CONTRACT')
sys.exit(0 if ok else 1)
