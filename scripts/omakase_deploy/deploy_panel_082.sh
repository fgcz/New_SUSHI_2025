#!/usr/bin/env bash
# 2026-09-29, updated 2026-09-30. Put the OMAKASE production panel on fgcz-h-082. Run it ON 082 as masaomi:
#   ssh -o BatchMode=yes fgcz-h-082 'bash /srv/sushi/masa_test_new_sushi_20260527/scripts/omakase_deploy/deploy_panel_082.sh'
# 082's checkout must carry this directory first: see the bootstrap in README.md.
#
# What it changes on 082, and nothing else:
#   1. nothing in the New SUSHI checkout: the bootstrap in README.md fast-forwards it (that
#      is how this script arrives on 082). Checked here: HEAD carries at least fc86682, and
#      bb5b784..HEAD touches only scripts/ and docs/, so the backend is NOT restarted and the
#      sign-in trap (config/initializers do not reload) cannot fire.
#   2. /srv/sushi/kairos_agent_server_dev: pulled (or cloned) from the bundle in ~/omakase_082_deploy/.
#   3. its .env (mode 600): port 8771, production profile, chat off, a NEW access key.
#   4. screen omakase-panel-prod runs the panel.
# Prints no key. The URL with the key goes to ~/omakase_prod_url_082.txt (mode 600).
# It grants NO write authority: Run on this panel submits only after grant_write_082.sh.
# Taking a key from the first page stays OFF here (checked in step 3).
# Stops at the first surprise (exit 2). Safe to run again: what is done is kept.
#
# Undo: screen -S omakase-panel-prod -X quit
#       The New SUSHI fast-forward needs no undo: the backend reads nothing that changed.
set -euo pipefail
umask 077

R=/srv/sushi/masa_test_new_sushi_20260527
ENGINE_FROM=bb5b784   # the backend on 082 booted with this code (scripts/docs aside); nothing it reads may change
ENGINE_MIN=fc86682    # 2026-09-30: production submits only with a separate write credential; omakase_cli
PANEL=/srv/sushi/kairos_agent_server_dev
# The panel repo has no remote and is not published, so its bundle stays OUT of git, in the
# NFS home (the same path on 082 and 083). Rebuilt on 083 with:
#   git -C /srv/sushi/kairos_agent_server_dev bundle create ~/omakase_082_deploy/kairos_agent_server.bundle main
BUNDLE=${OMAKASE_PANEL_BUNDLE:-$HOME/omakase_082_deploy/kairos_agent_server.bundle}
PANEL_TO=d28301d   # 2026-09-30: named keys, drop-downs, 'Run submits' chip + PRODUCTION confirm (was 6b10d47)
PORT=8771
SCREEN=omakase-panel-prod
PHOME=$HOME/.omakase/production
SLOG=$PHOME/panel_082.screenlog
URLFILE=$HOME/omakase_prod_url_082.txt
BASE=http://fgcz-h-082.fgcz-net.unizh.ch:$PORT
ENVF=$PANEL/.env

say() { printf '\n== %s\n' "$*"; }
die() { printf 'STOP: %s\n' "$*" >&2; exit 2; }
# Output first, grep second: `screen -ls` exits non-zero even when sessions exist, and
# under pipefail `screen -ls | grep -q` would then read as "not running".
has_screen() { local out; out=$(screen -ls 2>/dev/null || true); grep -q "\.$1[[:space:]]" <<<"$out"; }
listening() { local out; out=$(ss -ltn "sport = :$1" 2>/dev/null || true); grep -q LISTEN <<<"$out"; }

[ "$(hostname -s)" = fgcz-h-082 ] || die "run this on fgcz-h-082, not $(hostname -s)"
PY=$(command -v python3) || die "no python3 on PATH"

say "0. starting point"
cur=$(git -C "$R" rev-parse --short=7 HEAD)
echo "New SUSHI HEAD $cur"
git -C "$R" merge-base --is-ancestor "$ENGINE_MIN" HEAD \
  || die "New SUSHI HEAD $cur does not carry $ENGINE_MIN yet: run the bootstrap in README.md first"
echo "python3 = $PY"
"$PY" - <<'PYEOF' || die "a module the panel needs is missing (see above)"
import importlib
missing = []
for m in ("fastapi", "uvicorn", "pydantic", "yaml", "bfabric"):
    try:
        importlib.import_module(m)
    except Exception as exc:  # noqa: BLE001
        missing.append(f"{m} ({type(exc).__name__})")
try:
    importlib.import_module("markdown")
except Exception:  # noqa: BLE001
    print("note: python-markdown is missing, so only the page's 'docs' link will fail")
if missing:
    print("missing:", ", ".join(missing))
    raise SystemExit(1)
print("modules ok")
PYEOF
if listening "$PORT"; then
  has_screen "$SCREEN" || die "port $PORT is taken by something other than screen $SCREEN"
  echo "screen $SCREEN is already serving :$PORT; it will be restarted in step 4"
fi
[ -f "$PHOME/backend_token" ] || die "$PHOME/backend_token is missing"
[ "$(stat -c %a "$PHOME/backend_token")" = 600 ] || die "$PHOME/backend_token must be mode 600"

say "1. New SUSHI: $ENGINE_FROM..HEAD must touch only scripts/ and docs/"
git -C "$R" merge-base --is-ancestor "$ENGINE_FROM" HEAD \
  || die "HEAD $cur does not descend from $ENGINE_FROM, the code the backend booted with"
outside=$(git -C "$R" diff --name-only "$ENGINE_FROM" HEAD | grep -Ev '^(scripts|docs)/' || true)
[ -z "$outside" ] || die "$ENGINE_FROM..HEAD touches files outside scripts/ and docs/ (the backend would need a restart): $outside"
[ -z "$(git -C "$R" status --porcelain --untracked-files=no -- scripts docs)" ] \
  || die "scripts/ or docs/ has local edits on this node"
echo "New SUSHI HEAD $cur; the backend is not restarted (nothing it reads changed)"
( cd "$R/scripts" && "$PY" -m omakase_core.omakase --profile production recipes --json >/dev/null ) \
  || die "the engine refuses the production profile on this node"
echo "engine: the production profile runs on this node"

say "2. panel code: $PANEL at $PANEL_TO"
[ -f "$BUNDLE" ] || die "no bundle at $BUNDLE"
git -C "$R" bundle verify -q "$BUNDLE" >/dev/null 2>&1 || die "the bundle does not verify"
if [ -d "$PANEL/.git" ]; then
  git -C "$PANEL" pull -q --ff-only "$BUNDLE" main
else
  [ -w "$(dirname "$PANEL")" ] || die "$(dirname "$PANEL") is not writable for $USER"
  git clone -q -b main "$BUNDLE" "$PANEL"
fi
got=$(git -C "$PANEL" rev-parse --short=7 HEAD)
[ "$got" = "$PANEL_TO" ] || die "panel HEAD is $got, expected $PANEL_TO"
[ -z "$(git -C "$PANEL" status --porcelain --untracked-files=no)" ] \
  || die "the panel checkout has local edits"
echo "panel HEAD $got"

say "3. $ENVF (mode 600)"
if [ -f "$ENVF" ]; then
  echo "exists: kept, access key unchanged"
else
  key=$("$PY" -c 'import secrets; print(secrets.token_urlsafe(32))')
  printf '%s\n' "# fgcz-h-082 production panel, written by deploy_panel_082.sh on $(date +%F)" \
    "KAIROS_AGENT_HOST=0.0.0.0" "KAIROS_AGENT_PORT=$PORT" "KAIROS_AGENT_TOKEN=$key" \
    "KAIROS_CHAT=off" "OMAKASE_PROFILE=production" > "$ENVF"
  unset key
  echo "written, with a new access key"
fi
chmod 600 "$ENVF"
grep -q '^KAIROS_CHAT=off$' "$ENVF" || die "$ENVF must say KAIROS_CHAT=off"
grep -q '^OMAKASE_PROFILE=production$' "$ENVF" || die "$ENVF must say OMAKASE_PROFILE=production"
grep -q "^KAIROS_AGENT_PORT=$PORT\$" "$ENVF" || die "$ENVF must say KAIROS_AGENT_PORT=$PORT"
grep -q '^KAIROS_AGENT_TOKEN=..*' "$ENVF" || die "$ENVF has no access key"
si=$(cd "$PANEL" && "$PY" -m kairos_agent.keys self-issue status 2>&1 || true)
echo "$si"
grep -q 'OFF' <<<"$si" || die "taking a key from the first page must be OFF on 082 (python3 -m kairos_agent.keys self-issue off)"

say "4. start the panel in screen $SCREEN"
if has_screen "$SCREEN"; then screen -S "$SCREEN" -X quit; sleep 2; fi
listening "$PORT" && die "port $PORT is still taken after stopping screen $SCREEN"
touch "$SLOG"
chmod 600 "$SLOG"      # access logs can carry ?key=
screen -dmS "$SCREEN" -L -Logfile "$SLOG" bash "$PANEL/run.sh"
code=000
for _ in $(seq 1 30); do
  code=$(curl -s -o /dev/null -w '%{http_code}' "$BASE/api/health" || true)
  [ "$code" = 401 ] && break
  sleep 1
done
[ "$code" = 401 ] || die "no 401 without a key (got $code); look with: screen -r $SCREEN"
echo "no key -> 401"

say "5. HTTP checks (the key is read from .env and never printed)"
"$PY" - "$ENVF" "$BASE" <<'PYEOF' || die "an HTTP check failed (see above)"
import json
import sys
import urllib.error
import urllib.request

envf, base = sys.argv[1], sys.argv[2]
key = next(line.split("=", 1)[1].strip() for line in open(envf)
           if line.startswith("KAIROS_AGENT_TOKEN="))
bad = []


def call(method, path, body=None):
    req = urllib.request.Request(base + path, method=method,
                                 data=None if body is None else json.dumps(body).encode())
    req.add_header("Authorization", "Bearer " + key)
    req.add_header("Content-Type", "application/json")
    try:
        with urllib.request.urlopen(req, timeout=120) as r:
            return r.status, json.loads(r.read() or b"{}")
    except urllib.error.HTTPError as e:
        return e.code, {}


def want(name, got, exp):
    print(("ok   " if got == exp else "BAD  ") + f"{name}: {got}"
          + ("" if got == exp else f" (expected {exp})"))
    if got != exp:
        bad.append(name)


c, h = call("GET", "/api/health")
want("health", c, 200)
want("chat", h.get("chat"), "off")
c, s = call("GET", "/api/omakase/status")
want("status", c, 200)
want("host", s.get("host"), "fgcz-h-082")
want("profile", s.get("profile"), "production")
want("B-Fabric", s.get("bfabric_env"), "PRODUCTION")
print(f"     candidates {s.get('counts')}, orders with a record {s.get('ingestable_orders')}, "
      f"watcher handled {(s.get('watcher') or {}).get('handled')}")
sub = s.get("submits") or {}
want("submits is answered by the engine", isinstance(sub.get("can_submit"), bool), True)
print(f"     Run {'SUBMITS' if sub.get('can_submit') else 'does not submit'}: {sub.get('why')}")
c, r = call("GET", "/api/omakase/recipes")
want("recipes (runs the engine on this node)", c, 200)
print(f"     {len(r.get('recipes', []))} recipes")
c, _ = call("POST", "/api/chat", {"message": "ping"})
want("chat route", c, 404)
sys.exit(1 if bad else 0)
PYEOF

say "6. the URL with the key"
key=$(grep '^KAIROS_AGENT_TOKEN=' "$ENVF" | cut -d= -f2-)
printf '%s\n' "$BASE/?key=$key" > "$URLFILE"
unset key
chmod 600 "$URLFILE"
echo "written to $URLFILE (mode 600); open it in a browser inside the FGCZ network"
echo
echo "DONE. Stop with: screen -S $SCREEN -X quit"
