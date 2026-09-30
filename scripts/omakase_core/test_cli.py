#!/usr/bin/env python3
"""scripts/bin/omakase_cli is the long form, from anywhere. rc 0 = every case holds.

    python3 omakase_core/test_cli.py

No network: every case uses a temporary OMAKASE_ROOT and commands that read only local
files (help, recipes, submits, a declined run, the watcher's own refusals).
"""
from __future__ import annotations

import os
import subprocess
import sys
import tempfile
from pathlib import Path

SCRIPTS = Path(__file__).resolve().parent.parent
CLI = SCRIPTS / "bin" / "omakase_cli"
ROOT = Path(tempfile.mkdtemp(prefix="omakase_cli_test_"))
ELSEWHERE = Path(tempfile.mkdtemp(prefix="omakase_cli_cwd_"))
ENV = {k: v for k, v in os.environ.items()
       if k not in ("OMAKASE_PROFILE", "NEWSUSHI_WRITE_TOKEN_082", "OMAKASE_STORE")}
ENV["OMAKASE_ROOT"] = str(ROOT)

cases = 0


def case(name):
    global cases
    cases += 1
    print(f"  ok  {name}")


def cli(*argv, exe=CLI, cwd=ELSEWHERE):
    r = subprocess.run([str(exe), *argv], cwd=cwd, env=ENV, capture_output=True, text=True,
                       timeout=120)
    return r.returncode, r.stdout, r.stderr


def long_form(module, *argv):
    r = subprocess.run([sys.executable, "-m", module, *argv], cwd=SCRIPTS, env=ENV,
                       capture_output=True, text=True, timeout=120)
    return r.returncode, r.stdout, r.stderr


assert os.access(CLI, os.X_OK), f"{CLI} is not executable"
case("scripts/bin/omakase_cli is executable")

rc, out, err = cli("--help")
assert rc == 0 and out.startswith("omakase_cli: every command below, plus `watch`"), (rc, out)
assert "usage: omakase_cli " in out and "submits" in out and "ingest" in out, out
case("--help from another directory lists the engine's commands and names `watch`")

rc, out, err = cli("recipes")
lrc, lout, lerr = long_form("omakase_core.omakase", "recipes")
assert rc == 0 and (rc, out) == (lrc, lout), (rc, out[:200], lrc, lout[:200])
case("`omakase_cli recipes` prints exactly what `python3 -m omakase_core.omakase recipes` does")

link_dir = Path(tempfile.mkdtemp(prefix="omakase_cli_link_"))
link = link_dir / "omakase_cli"
os.symlink(CLI, link)
rc, out2, err = cli("recipes", exe=link)
assert rc == 0 and out2 == out, (rc, err)
case("through a symlink in another directory it still finds the scripts")

rc, out, err = cli("--profile", "production", "submits")
assert rc == 0 and out.startswith("DOES NOT SUBMIT: no write credential"), (rc, out, err)
case("--profile before the command reaches the engine (production, no write key)")
rc, out, err = cli("--profile=test", "submits")
assert rc == 0 and out.startswith("CAN SUBMIT: profile 'test'"), (rc, out, err)
case("--profile=VALUE works too")

rc, out, err = cli("--profile", "production", "run", "--candidate", "1")
lrc, lout, lerr = long_form("omakase_core.omakase", "--profile", "production", "run",
                            "--candidate", "1")
assert rc == 3 == lrc and "DECLINED: no write credential" in err and err == lerr, (rc, err)
case("exit codes and messages pass through unchanged (a declined run is rc 3)")

rc, out, err = cli("no-such-command")
assert rc == 2 and "invalid choice" in err, (rc, err)
case("an unknown command is refused by the engine's own parser (rc 2)")

rc, out, err = cli("watch", "--help")
assert rc == 0 and out.startswith("usage: omakase_cli watch"), (rc, out[:120])
assert "--order" in out, out
case("`omakase_cli watch` is the order watcher (python3 -m omakase_order_watch.watch)")

rc, out, err = cli("--store", str(ROOT / "x.sqlite3"), "watch", "--help")
assert rc == 2 and "--store belongs to the engine" in err, (rc, err)
case("--store with watch is refused: the watcher has no store (rc 2)")

# Refused before any network, and only if the watcher really got profile production.
rc, out, err = cli("--profile", "production", "watch", "--env", "TEST", "--status")
lrc, lout, lerr = long_form("omakase_order_watch.watch", "--profile", "production",
                            "--env", "TEST", "--status")
assert rc == 2 == lrc and "contradicts profile 'production'" in err and err == lerr, (rc, err)
case("--profile before `watch` is handed to the watcher, which answers as the long form does")
rc, out, err = cli("watch", "--order", "1", "--seed")
assert rc == 2 and "does not combine with --seed" in err, (rc, err)
case("the watcher's own refusals come through (rc 2)")

print(f"{cases} cases, all pass")
