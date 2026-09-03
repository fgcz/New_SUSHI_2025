#!/usr/bin/env bash
# End-to-end proof of the HEADLESS B-Fabric login, with no browser UI (step T2.6).
#
# One device approval buys a real authenticated session, and this then drives every
# login-required route with it.
#
# WHY THIS MATTERS MORE THAN IT LOOKS. This codebase's most expensive lesson is that a
# green test suite cannot see a login-required path: nine defects surfaced in one afternoon
# the first time a human logged in to 082, and several of them were AUTHORIZATION-shaped —
# dataset reads authorized by ownership so 98% of production answered 404, submission
# unauthorized for JWT sessions, a moved running-job log directory. Every one of those is
# reachable from here, under a real authenticated session, WITHOUT a browser. That is the
# single strongest argument for shipping the headless path first.
#
# EVERY WRITE PROBE IS INERT BY CONSTRUCTION, exactly as scripts/082_gate_check/probe_http.sh
# is: POST /api/v1/jobs carries an empty body (nothing to submit), POST /v1/datasets/register
# carries an empty body, and the DELETE targets an id that does not exist. A gate that were
# wrongly open still could not create anything.
#
# Usage:
#   bash scripts/bfabric_oauth_check/probe.sh [test|prod] [sushi_base_url]
#
# Defaults to the test B-Fabric instance and the 083 backend.

set -uo pipefail
# `-e` is deliberately off: several probes EXPECT a non-2xx answer.

INSTANCE="${1:-test}"
SUSHI="${2:-http://fgcz-h-083.fgcz-net.unizh.ch:3010}"
SUSHI="${SUSHI%/}"

case "$INSTANCE" in
  test) BFBASE="https://fgcz-bfabric-test.uzh.ch/bfabric" ;;
  prod) BFBASE="https://fgcz-bfabric.uzh.ch/bfabric" ;;
  http*) BFBASE="${INSTANCE%/}" ;;
  *) echo "usage: $0 [test|prod|<bfabric-base-url>] [sushi_base_url]" >&2; exit 2 ;;
esac

CLIENT_ID="${BFABRIC_OAUTH_CLIENT_ID:-CLI}"
SCOPE="${BFABRIC_OAUTH_SCOPE:-openid profile email api:read api:write}"

pass=0; fail=0; skip=0
hr() { printf '%s\n' "------------------------------------------------------------------"; }
ok()   { pass=$((pass+1)); printf '  [PASS] %s\n' "$1"; }
bad()  { fail=$((fail+1)); printf '  [FAIL] %s\n' "$1"; }
note() { skip=$((skip+1)); printf '  [SKIP] %s\n' "$1"; }

command -v curl >/dev/null 2>&1 || { echo "curl is required" >&2; exit 2; }
command -v python3 >/dev/null 2>&1 || { echo "python3 is required" >&2; exit 2; }

jq_get() { python3 -c 'import json,sys
try: d=json.load(sys.stdin)
except Exception: sys.exit(0)
k=sys.argv[1]
v=d
for part in k.split("."):
    if isinstance(v,list):
        try: v=v[int(part)]
        except Exception: sys.exit(0)
    elif isinstance(v,dict): v=v.get(part)
    else: sys.exit(0)
    if v is None: sys.exit(0)
print(v if not isinstance(v,(dict,list)) else json.dumps(v))' "$1"; }

# Prints just the status code; never prints a response body containing a token.
status() { curl -sS -o /dev/null -w '%{http_code}' "$@"; }

echo "B-Fabric : $BFBASE"
echo "New SUSHI: $SUSHI"
hr

# ---------------------------------------------------------------- 0. is the node ready?
LOGIN_OPTS="$(curl -fsS "$SUSHI/auth/login_options" 2>/dev/null)"
if [ -z "$LOGIN_OPTS" ]; then
  echo "cannot reach $SUSHI/auth/login_options — is the backend running?" >&2
  exit 1
fi
ADVERTISED="$(printf '%s' "$LOGIN_OPTS" | jq_get bfabric_oidc)"
echo "node advertises bfabric_oidc: ${ADVERTISED:-false}"
if [ "$ADVERTISED" != "True" ] && [ "$ADVERTISED" != "true" ]; then
  echo
  echo "The node does NOT advertise B-Fabric OIDC. Set these in its launcher and RESTART it"
  echo "(config is frozen at boot, so a deploy without a restart changes nothing):"
  echo "    export BFABRIC_OIDC_ENABLED=1"
  echo "    export BFABRIC_OIDC_BASE_URL=$BFBASE"
  echo "    export BFABRIC_OIDC_AUDIENCE=API"
  echo "    export BFABRIC_OIDC_ALLOWED_CLIENT_IDS=$CLIENT_ID"
  exit 1
fi
hr

# ---------------------------------------------------------------- 1. device login
DEVICE_URL="$(curl -fsS "$BFBASE/.well-known/openid-configuration" | jq_get device_authorization_endpoint)"
TOKEN_URL="$(curl -fsS "$BFBASE/.well-known/openid-configuration" | jq_get token_endpoint)"
[ -n "$DEVICE_URL" ] || { echo "no device_authorization_endpoint at $BFBASE" >&2; exit 1; }

DEVICE_JSON="$(curl -fsS -X POST "$DEVICE_URL" \
  -H 'Content-Type: application/x-www-form-urlencoded' \
  --data-urlencode "client_id=$CLIENT_ID" --data-urlencode "scope=$SCOPE")" || {
  echo "device_authorization failed" >&2; exit 1; }

DC_DEVICE_CODE="$(printf '%s' "$DEVICE_JSON" | jq_get device_code)"
DC_USER_CODE="$(printf '%s' "$DEVICE_JSON" | jq_get user_code)"
DC_URI="$(printf '%s' "$DEVICE_JSON" | jq_get verification_uri_complete)"
[ -n "$DC_URI" ] || DC_URI="$(printf '%s' "$DEVICE_JSON" | jq_get verification_uri)"
DC_INTERVAL="$(printf '%s' "$DEVICE_JSON" | jq_get interval)"; DC_INTERVAL="${DC_INTERVAL:-5}"
DC_EXPIRES="$(printf '%s' "$DEVICE_JSON" | jq_get expires_in)"; DC_EXPIRES="${DC_EXPIRES:-900}"

echo "ACTION REQUIRED — approve in any browser:"
echo
echo "    $DC_URI"
echo "    user code: $DC_USER_CODE"
echo
DEADLINE=$(( $(date +%s) + DC_EXPIRES ))
BF_TOKEN=""
while [ "$(date +%s)" -lt "$DEADLINE" ]; do
  sleep "$DC_INTERVAL"
  RESP="$(curl -sS -X POST "$TOKEN_URL" -H 'Content-Type: application/x-www-form-urlencoded' \
    --data-urlencode 'grant_type=urn:ietf:params:oauth:grant-type:device_code' \
    --data-urlencode "device_code=$DC_DEVICE_CODE" --data-urlencode "client_id=$CLIENT_ID")"
  ERR="$(printf '%s' "$RESP" | jq_get error)"
  case "$ERR" in
    authorization_pending) printf '.' ;;
    slow_down) DC_INTERVAL=$(( DC_INTERVAL + 5 )); printf '+' ;;
    "") BF_TOKEN="$(printf '%s' "$RESP" | jq_get access_token)"; break ;;
    *) printf '\n'; echo "token endpoint error: $ERR" >&2; exit 1 ;;
  esac
done
printf '\n'
[ -n "$BF_TOKEN" ] || { echo "timed out waiting for approval" >&2; exit 1; }
echo "approved — a B-Fabric token is held in memory only."
hr

# ---------------------------------------------------------------- 2. the exchange
echo "=== the exchange: GET /api/v1/auth/bfabric/session ==="
EX="$(curl -sS -H "Authorization: Bearer $BF_TOKEN" "$SUSHI/api/v1/auth/bfabric/session")"
JWT="$(printf '%s' "$EX" | jq_get access_token)"
LOGIN="$(printf '%s' "$EX" | jq_get user.login)"
SCOPES="$(printf '%s' "$EX" | jq_get granted_scopes)"

if [ -n "$JWT" ]; then
  ok "exchanged a B-Fabric token for a SUSHI session (login=$LOGIN)"
  echo "         granted scopes: $SCOPES"
else
  bad "the exchange did not return a session"
  echo "         response: $(printf '%s' "$EX" | head -c 400)"
  exit 1
fi

AUTH=(-H "Authorization: Bearer $JWT")

# The B-Fabric token must be worthless anywhere else. This is the design's central claim —
# the ticket is torn at the door — and it is the one thing that would make confining the
# bearer to a single route pointless if it failed.
CODE="$(status -H "Authorization: Bearer $BF_TOKEN" "$SUSHI/api/v1/projects")"
[ "$CODE" = "401" ] && ok "the B-Fabric token is refused on an ordinary route ($CODE)" \
                     || bad "a B-Fabric token was accepted outside the exchange route ($CODE)"
hr

# ---------------------------------------------------------------- 3. read paths
echo "=== login-required READ paths, under a real B-Fabric session ==="

CODE="$(status "${AUTH[@]}" "$SUSHI/api/v1/auth/me")"
[ "$CODE" = "200" ] && ok "GET /api/v1/auth/me ($CODE)" || bad "GET /api/v1/auth/me ($CODE)"

PROJECTS="$(curl -sS "${AUTH[@]}" "$SUSHI/api/v1/projects")"
PCOUNT="$(printf '%s' "$PROJECTS" | python3 -c 'import json,sys
try: d=json.load(sys.stdin)
except Exception: print(0); raise SystemExit
d = d.get("projects", d) if isinstance(d, dict) else d
print(len(d) if isinstance(d, list) else 0)')"
if [ "${PCOUNT:-0}" -gt 0 ]; then
  ok "GET /api/v1/projects returned $PCOUNT projects (LDAP membership resolved)"
else
  bad "GET /api/v1/projects returned nothing — an authenticated session with zero projects"
  echo "         This is the 'login succeeds, UI is empty' failure. Check LDAP, not OIDC."
fi

PNUM="$(printf '%s' "$PROJECTS" | python3 -c 'import json,sys
try: d=json.load(sys.stdin)
except Exception: raise SystemExit
d = d.get("projects", d) if isinstance(d, dict) else d
if isinstance(d, list) and d:
    p = d[0]
    print(p.get("number") if isinstance(p, dict) else p)')"

DSID=""
if [ -n "$PNUM" ]; then
  CODE="$(status "${AUTH[@]}" "$SUSHI/api/v1/projects/$PNUM/datasets")"
  [ "$CODE" = "200" ] && ok "GET /api/v1/projects/$PNUM/datasets ($CODE)" \
                      || bad "GET /api/v1/projects/$PNUM/datasets ($CODE)"
  DSID="$(curl -sS "${AUTH[@]}" "$SUSHI/api/v1/projects/$PNUM/datasets" | python3 -c 'import json,sys
try: d=json.load(sys.stdin)
except Exception: raise SystemExit
d = d.get("datasets", d) if isinstance(d, dict) else d
if isinstance(d, list) and d and isinstance(d[0], dict): print(d[0].get("id",""))')"
else
  note "no project number available, so the dataset probes cannot run"
fi

if [ -n "$DSID" ]; then
  # THE 98% CASE. Dataset reads were once authorized by OWNERSHIP rather than project
  # membership, so almost every production dataset answered 404 to the person who could
  # legitimately see it. This probe reads a dataset chosen by PROJECT, not by owner.
  CODE="$(status "${AUTH[@]}" "$SUSHI/api/v1/datasets/$DSID")"
  [ "$CODE" = "200" ] && ok "GET /api/v1/datasets/$DSID — a dataset in my project, whoever owns it ($CODE)" \
                      || bad "GET /api/v1/datasets/$DSID ($CODE) — the ownership-vs-membership defect class"
  for sub in samples paths parameters runnable_apps; do
    CODE="$(status "${AUTH[@]}" "$SUSHI/api/v1/datasets/$DSID/$sub")"
    [ "$CODE" = "200" ] && ok "GET /api/v1/datasets/$DSID/$sub ($CODE)" \
                        || bad "GET /api/v1/datasets/$DSID/$sub ($CODE)"
  done
else
  note "no dataset id discovered, so the dataset probes cannot run"
fi

CODE="$(status "${AUTH[@]}" "$SUSHI/api/v1/files")"
[ "$CODE" = "200" ] && ok "GET /api/v1/files — the gStore browser ($CODE)" \
                    || bad "GET /api/v1/files ($CODE)"

JOBID=""
if [ -n "$PNUM" ]; then
  CODE="$(status "${AUTH[@]}" "$SUSHI/api/v1/projects/$PNUM/jobs")"
  [ "$CODE" = "200" ] && ok "GET /api/v1/projects/$PNUM/jobs ($CODE)" \
                      || bad "GET /api/v1/projects/$PNUM/jobs ($CODE)"
  JOBID="$(curl -sS "${AUTH[@]}" "$SUSHI/api/v1/projects/$PNUM/jobs" | python3 -c 'import json,sys
try: d=json.load(sys.stdin)
except Exception: raise SystemExit
d = d.get("jobs", d) if isinstance(d, dict) else d
if isinstance(d, list) and d and isinstance(d[0], dict): print(d[0].get("id",""))')"
fi

if [ -n "$JOBID" ]; then
  # The running-job log directory moved once and nothing noticed, because a finished job's
  # logs live somewhere else. Both are probed.
  for sub in script logs; do
    CODE="$(status "${AUTH[@]}" "$SUSHI/api/v1/jobs/$JOBID/$sub")"
    case "$CODE" in
      200|404) ok "GET /api/v1/jobs/$JOBID/$sub ($CODE — 404 is legitimate for an old job)" ;;
      *)       bad "GET /api/v1/jobs/$JOBID/$sub ($CODE)" ;;
    esac
  done
else
  note "no job id discovered, so the job script/log probes cannot run"
fi
hr

# ---------------------------------------------------------------- 4. the write gates
echo "=== write gates — every probe below is inert (empty bodies, a nonexistent id) ==="
JOBS_CODE="$(status -X POST "${AUTH[@]}" -H 'Content-Type: application/json' -d '{}' "$SUSHI/api/v1/jobs")"
REG_CODE="$(status -X POST "${AUTH[@]}" -H 'Content-Type: application/json' -d '{}' "$SUSHI/v1/datasets/register")"
DEL_CODE="$(status -X DELETE "${AUTH[@]}" "$SUSHI/v1/datasets/999999999")"

echo "  POST /api/v1/jobs           -> $JOBS_CODE"
echo "  POST /v1/datasets/register  -> $REG_CODE"
echo "  DELETE /v1/datasets/999...  -> $DEL_CODE"

case "$JOBS_CODE" in
  403) ok "job submission is refused — by the Rack policy or by the api:write scope gate" ;;
  401) ok "job submission is refused (401)" ;;
  2*)  bad "JOB SUBMISSION WAS ACCEPTED. Stop and check the node's write policy." ;;
  *)   ok "job submission answered $JOBS_CODE (not a success)" ;;
esac
case "$REG_CODE" in
  2*) bad "dataset import was ACCEPTED ($REG_CODE)" ;;
  *)  ok "dataset import is refused ($REG_CODE)" ;;
esac
case "$DEL_CODE" in
  2*) bad "dataset delete was ACCEPTED ($DEL_CODE)" ;;
  *)  ok "dataset delete is refused ($DEL_CODE)" ;;
esac
hr

printf '%d passed, %d failed, %d skipped\n' "$pass" "$fail" "$skip"
echo "No token was written to disk; both tokens are gone when this process exits."
[ "$fail" -eq 0 ] || exit 1
