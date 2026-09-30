#!/usr/bin/env bash
# 2026-09-30. Take OMAKASE's write authority on fgcz-h-082 away again: back to read_only.
# Run it ON 082 as masaomi:
#   bash /srv/sushi/masa_test_new_sushi_20260527/scripts/omakase_deploy/revoke_write_082.sh
#
# What it changes:
#   1. run_backend_082.sh: a backup, then the block grant_write_082.sh added is removed.
#      SUSHI_READ_ONLY=1 (never removed) is then in force again.
#   2. ~/.omakase/production/backend_write_token is deleted (without the digest in the
#      launcher it opens nothing anyway), so the engine stops submitting at once.
#   3. restarts screen masa-newsushi-082 (signed-in browser sessions survive).
#   4. checks: the gate check in the read_only posture, inert HTTP probes, `omakase submits`.
#
# Refuses while an OMAKASE chain is running: its jobs are with the cluster already and
# cannot be recalled, but the runner would lose the key it polls them with. Let it finish
# (or stop it on purpose) first. Jobs already submitted, their datasets and their gStore
# files stay: authority is reversible, effects are not.
set -euo pipefail
umask 077

R=/srv/sushi/masa_test_new_sushi_20260527
L=$R/run_backend_082.sh
PHOME=$HOME/.omakase/production
WFILE=$PHOME/backend_write_token
RFILE=$PHOME/backend_token
SCREEN=masa-newsushi-082
SLOG=/tmp/omics_studio_backend_082.screenlog
BASE=http://fgcz-h-082.fgcz-net.unizh.ch:3010
BEGIN_MARK="# >>> OMAKASE write grant (grant_write_082.sh)"
END_MARK="# <<< OMAKASE write grant"

say() { printf '\n== %s\n' "$*"; }
die() { printf 'STOP: %s\n' "$*" >&2; exit 2; }
has_screen() { local out; out=$(screen -ls 2>/dev/null || true); grep -q "\.$1[[:space:]]" <<<"$out"; }
listening() { local out; out=$(ss -ltn "sport = :$1" 2>/dev/null || true); grep -q LISTEN <<<"$out"; }

[ "$(hostname -s)" = fgcz-h-082 ] || die "run this on fgcz-h-082, not $(hostname -s)"
PY=$(command -v python3) || die "no python3 on PATH"

say "0. starting point"
[ -f "$L" ] || die "no launcher at $L"
n_begin=$(grep -c "^$BEGIN_MARK" "$L" || true)
n_end=$(grep -c "^$END_MARK" "$L" || true)
if [ "$n_begin" = 0 ] && [ "$n_end" = 0 ]; then
  echo "no grant block in $L"
else
  [ "$n_begin" = 1 ] && [ "$n_end" = 1 ] || die "$L has $n_begin begin / $n_end end markers; fix it by hand"
fi
procs=$(ps -u "$USER" -o pid=,args= | grep 'omakase_core.omakase' | grep ' run ' | grep -v grep || true)
[ -z "$procs" ] || die "an OMAKASE chain is running (below); let it finish first:
$procs"
echo "no OMAKASE chain is running"

say "1. $L: backup, then remove the grant block"
if [ "$n_begin" = 1 ]; then
  BAK="$L.bak-before-write-revoke-$(date +%Y%m%d-%H%M%S)"
  cp -p "$L" "$BAK"
  chmod 700 "$BAK"
  tmp=$(mktemp "$R/.run_backend_082.XXXXXX")
  awk -v b="$BEGIN_MARK" -v e="$END_MARK" '
    index($0, b) == 1 { skip = 1; next }
    skip && index($0, e) == 1 { skip = 0; next }
    !skip { print }' "$L" > "$tmp"
  chmod 700 "$tmp"
  mv "$tmp" "$L"
  echo "backup: $BAK"
fi
grep -Eq '^[[:space:]]*(export[[:space:]]+)?(SUSHI_WRITE_POLICY|SUSHI_ENV_TOKEN_WRITE_[A-Z0-9_]+)=' "$L" \
  && die "$L still sets SUSHI_WRITE_POLICY or SUSHI_ENV_TOKEN_WRITE_*; look at it by hand"
grep -Eq '^[[:space:]]*export[[:space:]]+SUSHI_READ_ONLY=1' "$L" || die "$L does not export SUSHI_READ_ONLY=1"
case "$(tail -n 1 "$L")" in
  "exec bundle exec rails server "*) ;;
  *) die "the last line of $L is no longer the exec line; restore $BAK by hand" ;;
esac
echo "launcher: read_only again (SUSHI_READ_ONLY=1, no write variables)"

say "2. delete the write key"
if [ -e "$WFILE" ]; then rm -f "$WFILE"; echo "deleted $WFILE"; else echo "no $WFILE"; fi

say "3. restart the backend (screen $SCREEN)"
if has_screen "$SCREEN"; then screen -S "$SCREEN" -X quit; fi
for _ in $(seq 1 30); do listening 3010 || break; sleep 1; done
listening 3010 && die "port 3010 is still taken after stopping screen $SCREEN"
touch "$SLOG"; chmod 600 "$SLOG"
screen -dmS "$SCREEN" -L -Logfile "$SLOG" bash "$L"
code=000
for _ in $(seq 1 120); do
  code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 5 "$BASE/up" || true)
  [ "$code" = 200 ] && break
  sleep 1
done
[ "$code" = 200 ] || die "the backend did not answer /up with 200 in 120 s (got $code); look: screen -r $SCREEN, $SLOG"
echo "/up -> 200"

say "4a. gate check (read_only posture)"
bash "$R/scripts/082_gate_check/run.sh" || die "the gate check failed (see above)"

say "4b. HTTP probes with the read key - inert"
"$PY" - "$BASE" "$RFILE" <<'PYEOF' || die "an HTTP probe did not match (see above)"
import json
import sys
import urllib.error
import urllib.request

base, rfile = sys.argv[1:3]
key = open(rfile).read().strip()
bad = []


def probe(label, method, path, body, want_code, want_err):
    req = urllib.request.Request(base + path, method=method,
                                 data=None if body is None else json.dumps(body).encode())
    req.add_header("Authorization", "Bearer " + key)
    if body is not None:
        req.add_header("Content-Type", "application/json")
    try:
        with urllib.request.urlopen(req, timeout=60) as r:
            raw, code = r.read(), r.status
    except urllib.error.HTTPError as e:
        raw, code = e.read(), e.code
    try:
        err = (json.loads(raw or b"{}") or {}).get("error", "")
    except (ValueError, AttributeError):
        err = "(not json)"
    ok = code == want_code and err == want_err
    print(f"  [{'PASS' if ok else 'FAIL'}] {method:6} {path:32} -> {code} {err!r}  - {label}")
    if not ok:
        bad.append(label)


probe("job submission refused at gate 1", "POST", "/api/v1/jobs", {}, 403, "read_only")
probe("delete refused at gate 1", "DELETE", "/v1/datasets/999999999", None, 403, "read_only")
probe("read key cannot write (gate 2)", "POST", "/v1/datasets/validate",
      {"project_number": 35611}, 403, "action not permitted for this token")
sys.exit(1 if bad else 0)
PYEOF

say "4c. the engine's own answer"
( cd "$R/scripts" && "$PY" -m omakase_core.omakase --profile production submits ) \
  || die "omakase submits failed"

echo
echo "DONE. 082 is read_only again; the production panel's Run no longer submits."
