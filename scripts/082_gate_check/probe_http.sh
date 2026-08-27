#!/bin/bash
# Prove the negative space over HTTP: which gate refuses each write, by name.
#
# The companion to verify_gates.rb. That one inspects the objects on the boot path; this
# one drives the real request pipeline, which is the only way to see WHICH of the three
# gates actually fires first and what it tells the caller. During a cutover, "403" on its
# own is the least useful thing a log can say.
#
# Used by:
#   * Phase 3 step 13  — confirm the expected gate denies, before any authority exists
#   * Phase 4 step 15  — "re-prove the negative space FIRST, before submitting anything"
#
# The expected posture is an ARGUMENT, not something derived from the server. Stating the
# expectation and then checking it is the point; a probe that asks the server what to
# expect cannot fail.
#
# Every probe is inert by construction, so a gate that were wrongly OPEN still could not
# create anything: /v1/datasets/validate performs no write by design, POST /api/v1/jobs is
# sent with an empty body (nothing to submit), and the DELETE targets an id that does not
# exist.
#
# Usage:
#   SUSHI_PROBE_TOKEN=<bearer> bash probe_http.sh <base_url> <read_only|submit_only|additive>
#
# Always run it with the READ credential, in either posture. At Phase 4 that is exactly
# step 15's "a second (read-only) credential still cannot write": the write credential
# existing in the environment must not widen what this bearer can do.
#
# The token is read from the environment and never printed.
set -uo pipefail

BASE="${1:-}"
POSTURE="${2:-}"
TOKEN="${SUSHI_PROBE_TOKEN:-}"

if [ -z "$BASE" ] || [ -z "$POSTURE" ]; then
  echo "usage: SUSHI_PROBE_TOKEN=<bearer> bash probe_http.sh <base_url> <read_only|submit_only|additive>" >&2
  exit 2
fi
case "$POSTURE" in
  read_only|submit_only|additive) ;;
  *) echo "posture must be read_only, submit_only or additive (got '$POSTURE')" >&2; exit 2 ;;
esac
if [ -z "$TOKEN" ]; then
  echo "SUSHI_PROBE_TOKEN is not set" >&2
  exit 2
fi

pass=0
fail=0

# probe <label> <method> <path> <body|-> <expected_http> <expected_error_field>
probe () {
  local label="$1" method="$2" path="$3" body="$4" want_code="$5" want_err="$6"
  local args=(-s --max-time 30 -X "$method" -H "Authorization: Bearer $TOKEN" -w $'\n%{http_code}')
  if [ "$body" != "-" ]; then
    args+=(-H "Content-Type: application/json" -d "$body")
  fi
  local out code payload err
  out=$(curl "${args[@]}" "$BASE$path")
  code=$(printf '%s' "$out" | tail -1)
  payload=$(printf '%s' "$out" | sed '$d')
  err=$(printf '%s' "$payload" | python3 -c 'import json,sys
try: print(json.load(sys.stdin).get("error",""))
except Exception: print("(unparseable)")' 2>/dev/null)

  if [ "$code" = "$want_code" ] && [ "$err" = "$want_err" ]; then
    printf '  [PASS] %-34s -> %s %s\n' "$method $path" "$code" "\"$err\""
    pass=$((pass+1))
  else
    printf '  [FAIL] %-34s -> %s %s   (expected %s "%s")\n' \
      "$method $path" "$code" "\"$err\"" "$want_code" "$want_err"
    printf '         body: %s\n' "$(printf '%s' "$payload" | head -c 300)"
    fail=$((fail+1))
  fi
}

echo "base: $BASE"
echo "asserting the '$POSTURE' posture"
echo

echo "=== gate 1 — the Rack write policy, by name ==="
if [ "$POSTURE" = "read_only" ]; then
  # Under read_only nothing mutating survives the Rack layer, so it answers first and the
  # token gate is never reached for these two.
  probe "job submit"      POST   /api/v1/jobs            '{}' 403 read_only
  probe "dataset delete"  DELETE /v1/datasets/999999999  '-'  403 read_only
else
  # Under additive AND submit_only, POST /api/v1/jobs is allow-listed and passes gate 1, so
  # whatever answers now is downstream of it. DELETE is still refused, and names the policy.
  probe "dataset delete"  DELETE /v1/datasets/999999999  '-'  403 "$POSTURE"

  if [ "$POSTURE" = "submit_only" ]; then
    # The one route that SEPARATES the two write postures, so it is what proves on the real
    # node that the narrowing took effect rather than that some gate merely refused:
    # additive allow-lists this import and would hand it to the token gate, while
    # submit_only refuses it AT gate 1 and names itself doing so. Inert either way — an
    # empty body has nothing to register.
    probe "dataset import"  POST   /v1/datasets/register  '{}' 403 submit_only
    # Same argument for the set-once B-Fabric link, which additive allow-lists by pattern.
    probe "bfabric-id link" PUT    /v1/datasets/999999999/bfabric-id '{}' 403 submit_only
  fi
fi

echo
echo "=== gate 2 — the token's write capability, by name ==="
# /v1/datasets/validate is on the Rack layer's dry-run allowlist, so it PASSES gate 1 in
# every posture. A denial here therefore comes from the token gate and nowhere else --
# which is what makes the two gates observably independent rather than merely believed to be.
probe "dry-run validate" POST /v1/datasets/validate '{"project_number":35611}' \
      403 "action not permitted for this token"

echo
echo "=== project scope — unrelated to the write gates, and still enforced ==="
probe "out-of-scope read" GET /api/v1/projects/3071/datasets '-' 403 "Project not accessible"
probe "internal bridge"   GET /internal/legacy/jobs          '-' 403 "internal bridge requires a machine token"

echo
echo "------------------------------------------------------------------------------"
if [ "$fail" -eq 0 ]; then
  echo "ALL $pass PROBES MATCHED THE EXPECTED GATE"
  exit 0
fi
echo "$fail of $((pass+fail)) PROBES DID NOT MATCH"
exit 1
