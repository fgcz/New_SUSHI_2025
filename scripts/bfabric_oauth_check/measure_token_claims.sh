#!/usr/bin/env bash
# Measure what a REAL B-Fabric access token actually contains (steps M1 / M2).
#
# WHY THIS EXISTS. New SUSHI refuses to enable B-Fabric OIDC until BFABRIC_OIDC_AUDIENCE is
# set, because without an expected `aud` a token minted for ANY other B-Fabric relying
# party would verify here on signature alone. That value is a MEASUREMENT, not a guess.
# This script takes it.
#
# WHAT IT NEEDS FROM YOU: one device approval in any browser, on any machine. That is the
# only interactive step; everything else is curl.
#
# WHAT IT DELIBERATELY DOES NOT DO:
#   * it never writes a token to disk;
#   * it never prints a raw token, only the CLAIM NAMES and the few claim VALUES the
#     verifier needs (iss, aud, scope, and whether client_id/azp exists at all);
#   * it touches no database and no SUSHI process.
#
# It uses the PUBLIC client `CLI`, which already exists on both the test and production
# instances, so it needs no client registration, no secret and no redirect_uri.
#
# Usage:
#   bash scripts/bfabric_oauth_check/measure_token_claims.sh [test|prod]
#
# Default is `test`. Run it against BOTH before enabling anything on 082 (M1 then M2):
# the two instances are configured separately and only the test one has ever been
# exercised.

set -uo pipefail
# NOTE: `-e` is deliberately NOT set. A polling loop whose non-zero exit is EXPECTED
# (authorization_pending) would abort the script under `set -e`, which is exactly the
# failure mode that silently took a service down in this repo once before.

INSTANCE="${1:-test}"
case "$INSTANCE" in
  test) BASE="https://fgcz-bfabric-test.uzh.ch/bfabric" ;;
  prod) BASE="https://fgcz-bfabric.uzh.ch/bfabric" ;;
  http*) BASE="${INSTANCE%/}" ;;
  *) echo "usage: $0 [test|prod|<base-url>]" >&2; exit 2 ;;
esac

CLIENT_ID="${BFABRIC_OAUTH_CLIENT_ID:-CLI}"
SCOPE="${BFABRIC_OAUTH_SCOPE:-openid profile email api:read api:write}"

say() { printf '%s\n' "$*"; }
hr()  { printf '%s\n' "------------------------------------------------------------------"; }

need() {
  command -v "$1" >/dev/null 2>&1 || { echo "missing required tool: $1" >&2; exit 2; }
}
need curl
need python3

say "instance : $INSTANCE"
say "base     : $BASE"
say "client_id: $CLIENT_ID  (public client; no registration, no secret)"
say "scope    : $SCOPE"
hr

# ---------------------------------------------------------------- discovery
DISCOVERY_JSON="$(curl -fsS -H 'Accept: application/json' "$BASE/.well-known/openid-configuration")" || {
  echo "could not fetch the discovery document from $BASE" >&2; exit 1; }

read -r DEVICE_URL TOKEN_URL USERINFO_URL JWKS_URL ISSUER <<EOF
$(printf '%s' "$DISCOVERY_JSON" | python3 -c '
import json,sys
d=json.load(sys.stdin)
print(d.get("device_authorization_endpoint",""),
      d.get("token_endpoint",""),
      d.get("userinfo_endpoint",""),
      d.get("jwks_uri",""),
      d.get("issuer",""))
')
EOF

say "issuer                      : $ISSUER"
say "device_authorization_endpoint: ${DEVICE_URL:-(ABSENT)}"
say "token_endpoint              : $TOKEN_URL"
say "userinfo_endpoint           : $USERINFO_URL"
say "jwks_uri                    : $JWKS_URL"
hr

if [ -z "$DEVICE_URL" ]; then
  echo "This instance does not advertise a device_authorization_endpoint." >&2
  echo "The headless path cannot be used here without asking the B-Fabric team." >&2
  exit 1
fi

# ---------------------------------------------------------------- device code
DEVICE_JSON="$(curl -fsS -X POST "$DEVICE_URL" \
  -H 'Content-Type: application/x-www-form-urlencoded' \
  --data-urlencode "client_id=$CLIENT_ID" \
  --data-urlencode "scope=$SCOPE")" || {
  echo "the device_authorization request failed — is client_id=$CLIENT_ID registered for the device_code grant on this instance?" >&2
  exit 1; }

# Written without a backslash inside an f-string expression on purpose: that is a syntax
# error on Python < 3.12, and this script should run wherever curl and python3 exist.
eval "$(printf '%s' "$DEVICE_JSON" | python3 -c '
import json, sys, shlex
d = json.load(sys.stdin)
for k in ("device_code", "user_code", "verification_uri", "verification_uri_complete",
          "interval", "expires_in"):
    value = shlex.quote(str(d.get(k, "")))
    print("DC_" + k.upper() + "=" + value)
')"

say "ACTION REQUIRED — open this in any browser and approve:"
say ""
say "    ${DC_VERIFICATION_URI_COMPLETE:-$DC_VERIFICATION_URI}"
say ""
say "    user code: $DC_USER_CODE"
say ""
say "(expires in ${DC_EXPIRES_IN}s — device codes are short-lived; if it lapses, re-run.)"
hr

INTERVAL="${DC_INTERVAL:-5}"
DEADLINE=$(( $(date +%s) + ${DC_EXPIRES_IN:-900} ))
TOKEN_JSON=""

while [ "$(date +%s)" -lt "$DEADLINE" ]; do
  sleep "$INTERVAL"
  RESP="$(curl -sS -X POST "$TOKEN_URL" \
    -H 'Content-Type: application/x-www-form-urlencoded' \
    --data-urlencode 'grant_type=urn:ietf:params:oauth:grant-type:device_code' \
    --data-urlencode "device_code=$DC_DEVICE_CODE" \
    --data-urlencode "client_id=$CLIENT_ID")"

  ERR="$(printf '%s' "$RESP" | python3 -c 'import json,sys
try: print(json.load(sys.stdin).get("error",""))
except Exception: print("unparseable")')"

  case "$ERR" in
    authorization_pending) printf '.' ;;
    slow_down)             INTERVAL=$(( INTERVAL + 5 )); printf '+' ;;
    "")                    TOKEN_JSON="$RESP"; break ;;
    *)                     printf '\n'; echo "token endpoint returned error: $ERR" >&2; exit 1 ;;
  esac
done
printf '\n'

[ -n "$TOKEN_JSON" ] || { echo "timed out waiting for approval" >&2; exit 1; }

say "approved — a token was issued. Analysing it locally now (nothing leaves this process)."

# ---------------------------------------------------------------- the measurement
#
# THE ANALYSIS PROGRAM IS WRITTEN TO A TEMP FILE, and the token JSON is piped into it.
#
# It must NOT be `python3 - ... <<'PY'`. A heredoc REPLACES stdin, so python reads the
# PROGRAM from stdin and the piped JSON is discarded; `json.load(sys.stdin)` then sees EOF
# and dies with "Expecting value: line 1 column 1". That bug wasted two real device
# approvals on 2026-09-03 — the token had already been issued and was thrown away.
#
# The token is NOT passed as an argument either: argv is visible to every user on the host
# through `ps`.
hr
ANALYSIS_PY="$(mktemp -t bfabric_oauth_analysis.XXXXXX)"
trap 'rm -f "$ANALYSIS_PY"' EXIT INT TERM

cat > "$ANALYSIS_PY" <<'PY'
import base64, json, sys, urllib.request

def b64(seg):
    return base64.urlsafe_b64decode(seg + "=" * (-len(seg) % 4))

def parts(tok):
    h, p, _ = tok.split(".")
    return json.loads(b64(h)), json.loads(b64(p))

blob = json.load(sys.stdin)
userinfo_url = sys.argv[1]
base_url = sys.argv[2]

print("token response fields :", sorted(blob.keys()))
print("token_type            :", blob.get("token_type"))
print("expires_in            :", blob.get("expires_in"))
print("refresh_token issued  :", "yes" if blob.get("refresh_token") else "no")
print("granted scope         :", blob.get("scope"))
print()

access = blob.get("access_token")
ap = {}
access_is_jwt = bool(access) and access.count(".") == 2

if not access:
    print("=== NO ACCESS TOKEN IN THE RESPONSE ===")
    print("The token endpoint returned a body with no `access_token`. Its fields are listed")
    print("above; if it names an `error`, that is what went wrong.")
elif not access_is_jwt:
    # Do NOT bail here. A device approval is expensive and the token is already spent;
    # print everything that can still be learned from it.
    print("=== ACCESS TOKEN — NOT A JWT ===")
    print("This is decisive for the design: the backend verifies the token LOCALLY against")
    print("the published JWKS, which an opaque token makes impossible. The headless path")
    print("would have to call the introspection endpoint instead, which needs a")
    print("confidential client — i.e. it would inherit the browser path's blocker.")
    print("  length              :", len(access or ""))
    print("  dot-separated parts :", (access or "").count(".") + 1)
else:
    ah, ap = parts(access)
    print("=== ACCESS TOKEN ===")
    print("header                :", ah)
    print("claim names           :", sorted(ap.keys()))
    for k in ("iss", "aud", "sub", "scope", "scp", "client_id", "azp", "at_hash"):
        if k in ap:
            print(f"  {k:<20}: {ap[k]!r}")
    print()
    print("client_id present     :", "client_id" in ap)
    print("azp present           :", "azp" in ap)
    if "client_id" not in ap and "azp" not in ap:
        print("  -> NO per-client narrowing is possible. Leave BFABRIC_OIDC_ALLOWED_CLIENT_IDS")
        print("     UNSET; any B-Fabric client's token with this audience will be accepted.")
    if "aud" not in ap:
        print("  -> NO `aud` claim at all. BFABRIC_OIDC_AUDIENCE cannot be set from this")
        print("     token, and the backend will refuse to enable. Report this: it means")
        print("     nothing distinguishes a token minted for us from one minted for")
        print("     another B-Fabric relying party.")

idt = blob.get("id_token")
if idt and idt.count(".") == 2:
    _, ip = parts(idt)
    print()
    print("=== ID TOKEN ===")
    print("claim names           :", sorted(ip.keys()))
    print("  aud                 :", repr(ip.get("aud")), "(differs from the access token's — expected)")
    print("  sub                 :", repr(ip.get("sub")))

if userinfo_url:
    req = urllib.request.Request(userinfo_url, headers={"Authorization": f"Bearer {access}"})
    try:
        with urllib.request.urlopen(req, timeout=15) as r:
            ui = json.load(r)
        print()
        print("=== /userinfo ===")
        print("claim names           :", sorted(ui.keys()))
        print("  sub                 :", repr(ui.get("sub")))
    except Exception as e:
        print()
        print("=== /userinfo === failed:", e)

print()
print("=" * 66)
aud = ap.get("aud")
aud = aud[0] if isinstance(aud, list) and aud else aud

if aud:
    print("SET THESE ON THE NODE (nothing else is needed to enable the headless path):")
    print("=" * 66)
    print("  export BFABRIC_OIDC_ENABLED=1")
    print("  export BFABRIC_OIDC_BASE_URL=" + base_url)
    print("  export BFABRIC_OIDC_AUDIENCE=" + str(aud))
    if ap.get("iss") and ap["iss"] != base_url:
        print("  export BFABRIC_OIDC_ISSUER=" + str(ap["iss"]))
        print("    (the `iss` claim differs from the base URL, so pin it explicitly)")
    scopes = (ap.get("scope") or "").split()
    if "api:write" not in scopes:
        print()
        print("  NOTE: api:write was NOT granted. A session exchanged from a token like this")
        print("        can read but not submit — the backend's write gate will refuse it.")
else:
    print("CANNOT ENABLE THE FEATURE FROM THIS MEASUREMENT.")
    print("=" * 66)
    print("No usable `aud` was found, so BFABRIC_OIDC_AUDIENCE has no value to take and the")
    print("backend will keep the feature off — deliberately. Take the claim dump above to")
    print("the B-Fabric team before changing anything on our side.")
print()
print("The raw tokens were NOT written anywhere and are gone when this process exits.")
PY

printf '%s' "$TOKEN_JSON" | python3 "$ANALYSIS_PY" "$USERINFO_URL" "$BASE"
ANALYSIS_RC=$?

hr
if [ "$ANALYSIS_RC" -ne 0 ]; then
  say "The analysis exited $ANALYSIS_RC. The token was already issued and is now gone, so"
  say "re-running means approving again — fix the analysis before you do."
fi
say "Reminder: the tokens above were held in memory only. Nothing was saved."
exit "$ANALYSIS_RC"
