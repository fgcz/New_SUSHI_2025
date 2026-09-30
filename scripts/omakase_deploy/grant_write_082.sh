#!/usr/bin/env bash
# 2026-09-30. Let OMAKASE submit jobs on fgcz-h-082 (production): job submission ONLY,
# into project 35611 ONLY. Run it ON 082 as masaomi, AFTER deploy_panel_082.sh:
#   bash /srv/sushi/masa_test_new_sushi_20260527/scripts/omakase_deploy/grant_write_082.sh
#
# What it changes, and nothing else:
#   1. a NEW write credential `omakase-082-write`, scope 35611 (rake api_token:env_token
#      WRITE=1 - no database access). Its raw bearer goes to
#      ~/.omakase/production/backend_write_token (mode 600) and is never printed.
#   2. run_backend_082.sh: a backup first, then one marked block before its `exec` line:
#      SUSHI_WRITE_POLICY=submit_only + SUSHI_ENV_TOKEN_WRITE_{SHA256,SCOPE,NAME}.
#      SUSHI_READ_ONLY=1 stays in the file; SUSHI_WRITE_POLICY takes precedence over it,
#      so deleting the block is the whole revoke.
#   3. restarts screen masa-newsushi-082 (the backend). Browser sessions that are already
#      signed in keep working (the secret is pinned); a sign-in that is half-way through
#      at that moment has to be started again.
#   4. checks, all inert: the gate check (verify_gates.rb) in the write posture, then HTTP
#      probes with both keys (listed in step 4 below), then `omakase submits`.
#
# While it is in force: POST /api/v1/jobs is the only write the backend accepts, from the
# write credential (project 35611) and from signed-in FGCZ employees in Omics-Studio (their
# own projects) - the user's decision of 2026-09-30. No dataset import, no B-Fabric link, no
# /internal, no DELETE/PUT/PATCH. The all-projects READ key (omakase-082) still cannot write.
#
# Undo: bash /srv/sushi/masa_test_new_sushi_20260527/scripts/omakase_deploy/revoke_write_082.sh
# Stops at the first surprise (exit 2). Prints no key and no digest.
set -euo pipefail
umask 077

R=/srv/sushi/masa_test_new_sushi_20260527
L=$R/run_backend_082.sh
SCOPE=35611
NAME=omakase-082-write
CHECK_DATASET=113260          # p35611 ventricles_100k on the production DB (o35755's data)
OUT_OF_SCOPE_PROJECT=3071     # any project that is not 35611
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
case "$(tail -n 1 "$L")" in
  "exec bundle exec rails server "*) ;;
  *) die "the last line of $L is not the bare 'exec bundle exec rails server …' this script expects" ;;
esac
grep -q "^$BEGIN_MARK" "$L" && die "$L already carries a write grant; run revoke_write_082.sh first"
grep -Eq '^[[:space:]]*(export[[:space:]]+)?(SUSHI_WRITE_POLICY|SUSHI_ENV_TOKEN_WRITE_[A-Z0-9_]+)=' "$L" \
  && die "$L already sets SUSHI_WRITE_POLICY or SUSHI_ENV_TOKEN_WRITE_*; look at it by hand"
grep -Eq '^[[:space:]]*export[[:space:]]+SUSHI_READ_ONLY=1' "$L" \
  || die "$L does not export SUSHI_READ_ONLY=1, so the revoke would not fall back to read_only"
[ -e "$WFILE" ] && die "$WFILE already exists; run revoke_write_082.sh first"
[ -f "$RFILE" ] || die "$RFILE (the read key) is missing"
[ "$(stat -c %a "$RFILE")" = 600 ] || die "$RFILE must be mode 600"
listening 3010 || die "the backend is not listening on :3010 now; start from a healthy node"
head=$(git -C "$R" rev-parse --short=7 HEAD)
echo "New SUSHI HEAD $head"
( cd "$R/scripts" && "$PY" -c 'import omakase_core.profile as P; assert P.get("production").write_token_env' ) \
  || die "the engine here does not know the write credential yet: run deploy_panel_082.sh first"
echo "engine knows the write credential; launcher is in the expected shape"

say "1. a new write credential '$NAME', scope $SCOPE"
out=$( ( . <(sed '/^exec bundle exec rails server/,$d' "$L") >/dev/null 2>&1
         cd "$R/backend" && bundle exec rake api_token:env_token WRITE=1 NAME="$NAME" SCOPE="$SCOPE" ) 2>&1 ) \
  || die "rake api_token:env_token failed (output withheld: it may carry the key)"
raw=$(awk 'f{print; exit} /^RAW TOKEN/{f=1}' <<<"$out")
digest_line=$(grep '^export SUSHI_ENV_TOKEN_WRITE_SHA256=' <<<"$out" || true)
scope_line=$(grep '^export SUSHI_ENV_TOKEN_WRITE_SCOPE=' <<<"$out" || true)
name_line=$(grep '^export SUSHI_ENV_TOKEN_WRITE_NAME=' <<<"$out" || true)
unset out
[ -n "$raw" ] && [ -n "$digest_line" ] || die "could not read the rake output"
[ "$scope_line" = "export SUSHI_ENV_TOKEN_WRITE_SCOPE=$SCOPE" ] || die "unexpected scope line"
[ "$name_line" = "export SUSHI_ENV_TOKEN_WRITE_NAME=$NAME" ] || die "unexpected name line"
want_digest=$(printf '%s' "$raw" | sha256sum | cut -d' ' -f1)
[ "$digest_line" = "export SUSHI_ENV_TOKEN_WRITE_SHA256=$want_digest" ] \
  || die "the digest the rake task printed is not the SHA-256 of its key"
unset want_digest
mkdir -p "$PHOME"
printf '%s\n' "$raw" > "$WFILE"
chmod 600 "$WFILE"
unset raw
echo "write key -> $WFILE (mode $(stat -c %a "$WFILE")); not shown"

say "2. $L: backup, then the grant block before exec"
BAK="$L.bak-before-write-grant-$(date +%Y%m%d-%H%M%S)"
cp -p "$L" "$BAK"
chmod 700 "$BAK"
tmp=$(mktemp "$R/.run_backend_082.XXXXXX")
{
  sed '$d' "$L"
  printf '%s\n' "$BEGIN_MARK $(date '+%F %T'): job submission only, scope $SCOPE, name $NAME" \
    "export SUSHI_WRITE_POLICY=submit_only" "$digest_line" "$scope_line" "$name_line" "$END_MARK"
  tail -n 1 "$L"
} > "$tmp"
unset digest_line
chmod 700 "$tmp"
mv "$tmp" "$L"
echo "backup: $BAK"
echo "variables now set in the launcher (names only):"
grep -o -E '^[[:space:]]*export[[:space:]]+(SUSHI_WRITE_POLICY|SUSHI_READ_ONLY|SUSHI_ENV_TOKEN_WRITE_[A-Z0-9_]+)=' "$L" \
  | sed 's/^[[:space:]]*export[[:space:]]*/  /'

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
[ "$code" = 200 ] || die "the backend did not answer /up with 200 in 120 s (got $code). Look: screen -r $SCREEN, $SLOG. To go back: bash /srv/sushi/masa_test_new_sushi_20260527/scripts/omakase_deploy/revoke_write_082.sh"
echo "/up -> 200"

say "4a. gate check on the real boot path (write posture)"
bash "$R/scripts/082_gate_check/run.sh" \
  || die "the gate check failed (see above). To go back: bash /srv/sushi/masa_test_new_sushi_20260527/scripts/omakase_deploy/revoke_write_082.sh"

say "4b. HTTP probes - inert by construction (empty bodies, a nonexistent id, GETs)"
"$PY" - "$BASE" "$RFILE" "$WFILE" "$CHECK_DATASET" "$OUT_OF_SCOPE_PROJECT" <<'PYEOF' \
  || die "an HTTP probe did not match (see above). To go back: bash /srv/sushi/masa_test_new_sushi_20260527/scripts/omakase_deploy/revoke_write_082.sh"
import json
import sys
import urllib.error
import urllib.request

base, rfile, wfile, ds, other = sys.argv[1:6]
keys = {"read": open(rfile).read().strip(), "write": open(wfile).read().strip()}
bad = []


def call(who, method, path, body=None):
    req = urllib.request.Request(base + path, method=method,
                                 data=None if body is None else json.dumps(body).encode())
    req.add_header("Authorization", "Bearer " + keys[who])
    if body is not None:
        req.add_header("Content-Type", "application/json")
    try:
        with urllib.request.urlopen(req, timeout=60) as r:
            raw = r.read()
            code = r.status
    except urllib.error.HTTPError as e:
        raw, code = e.read(), e.code
    try:
        err = (json.loads(raw or b"{}") or {}).get("error", "")
    except (ValueError, AttributeError):
        err = "(not json)"
    return code, err


def probe(label, who, method, path, body, want_code, want_err=None):
    code, err = call(who, method, path, body)
    ok = code == want_code and (want_err is None or err == want_err)
    print(f"  [{'PASS' if ok else 'FAIL'}] {who:5} {method:6} {path:40} -> {code} {err!r}"
          + ("" if ok else f"   (expected {want_code} {want_err!r})") + f"  - {label}")
    if not ok:
        bad.append(label)


print("the READ key (omakase-082, all projects) still cannot write:")
probe("read key cannot submit", "read", "POST", "/api/v1/jobs", {}, 403,
      "action not permitted for this token")
probe("read key cannot even dry-run a write", "read", "POST", "/v1/datasets/validate",
      {"project_number": 35611}, 403, "action not permitted for this token")
print("the policy is submit_only, not additive (gate 1 names itself):")
probe("no dataset import", "write", "POST", "/v1/datasets/register", {}, 403, "submit_only")
probe("no B-Fabric link", "write", "PUT", "/v1/datasets/999999999/bfabric-id", {}, 403,
      "submit_only")
probe("no delete", "write", "DELETE", "/v1/datasets/999999999", None, 403, "submit_only")
print("the WRITE key (omakase-082-write) reaches its project, and only its project:")
probe("write key reads the input dataset", "write", "GET", f"/api/v1/datasets/{ds}", None, 200)
probe("write key is refused outside 35611", "write", "GET",
      f"/api/v1/projects/{other}/datasets", None, 403, "Project not accessible")
probe("write key passes both gates to the job route (empty body: 400, nothing created)",
      "write", "POST", "/api/v1/jobs", {}, 400)
probe("write key is not a machine token", "write", "GET", "/internal/legacy/jobs", None, 403,
      "internal bridge requires a machine token")
sys.exit(1 if bad else 0)
PYEOF

say "4c. the engine's own answer"
( cd "$R/scripts" && "$PY" -m omakase_core.omakase --profile production submits ) \
  || die "omakase submits failed"

echo
echo "DONE. The production panel's Run now submits, into project $SCOPE only."
echo "The panel caches this answer for 30 s; reload the page after that."
echo "Undo at any time: bash /srv/sushi/masa_test_new_sushi_20260527/scripts/omakase_deploy/revoke_write_082.sh"
