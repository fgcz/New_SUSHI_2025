#!/usr/bin/env bash
# 2026-09-29. Restart the New SUSHI backend on fgcz-h-083 (:3010) WITH authentication.
# Run it ON 083 as masaomi:
#   bash /srv/sushi/masa_test_new_sushi_20260527/scripts/omakase_deploy/restart_backend_083.sh
#
# What changes, and why:
#   SUSHI_REQUIRE_AUTH=1   a request without a valid key is 401. Until now 083 ran auth-free
#                          (since 2026-09-24): no key, a wrong key or a revoked key was served
#                          as `anonymous`, and could submit to any project.
#   ENABLE_LDAP=1          LDAP password login for Omics-Studio (:4000) stays available.
#   BFABRICPY_CONFIG_ENV=TEST
#                          the process inherited PRODUCTION from a shell. Nothing in the backend
#                          reads it today (checked 2026-09-29), but a test node must not point
#                          at production B-Fabric even by accident.
#   LEGACY_APPS_ALLOWLIST  the default 17 apps + ScSeuratCombine (Paul's sc_10x_3prime_gex).
#   LEGACY_APPS_DIR        unchanged: the 082 production app snapshot of 2026-08-18.
# The pinned secret_key_base is reused, so every issued key (chain, demo keys) stays valid.
# The backend is down for the ~30-60 s of the restart. Stops at the first surprise (exit 2).
set -euo pipefail

R=/srv/sushi/masa_test_new_sushi_20260527
B=http://127.0.0.1:3010
DEFAULT_APPS=FastqScreen,DESeq2,EdgeR,CountQC,Fastqc10x,FastqScreen10x,RnaBamStats,Mpileup,STAR,FeatureCounts,CellRangerMulti,Kallisto,Bowtie2,BWA,ScSeurat,DnaBamStats,CellRanger

die() { printf 'STOP: %s\n' "$*" >&2; exit 2; }
say() { printf '\n== %s\n' "$*"; }
pid_on() { local out; out=$(ss -ltnpH "sport = :$1" 2>/dev/null || true); grep -o 'pid=[0-9]*' <<<"$out" | head -1 | cut -d= -f2 || true; }

[ "$(hostname -s)" = fgcz-h-083 ] || die "run this on fgcz-h-083, not $(hostname -s)"

say "0. nothing may be mid-chain"
busy=$(pgrep -u "$USER" -af 'omakase_core\.omakase .*run --candidate' || true)
[ -z "$busy" ] || die "an OMAKASE chain is running; a restart would fail its next submit: $busy"
jm=$(pgrep -u trxcopy -f start_sushi_jobmanager.py | wc -l || true)
echo "job managers running: $jm (expected 1)"
echo "backend before: pid $(pid_on 3010)"

say "1. restart"
export SUSHI_REQUIRE_AUTH=1 ENABLE_LDAP=1 BFABRICPY_CONFIG_ENV=TEST
export LEGACY_APPS_DIR=/srv/sushi/prod_apps_082_snapshot_20260818/lib
export LEGACY_APPS_ALLOWLIST="$DEFAULT_APPS,ScSeuratCombine"
bash "$R/run_backend_083.sh" 2>&1 | grep -vE '^(=== NEXT|Old tokens|project 35611|  cd backend|  set -a|  RAILS_ENV|    bundle|    \||  # )' || true
new=$(pid_on 3010)
[ -n "$new" ] || die "nothing listens on 3010; read /tmp/newsushi_3010.log"
echo "backend after: pid $new"

say "2. checks (no key is printed)"
python3 - "$new" <<'PYEOF' || die "a check failed (see above)"
import json, sys, urllib.error, urllib.request
pid = sys.argv[1]
B = "http://127.0.0.1:3010"
key = json.load(open("/srv/sushi/masa_test_new_sushi_20260527/.mcp.json"))["mcpServers"]["sushi-chain"]["env"]["NEWSUSHI_TOKEN_083"]
bad = []

def get(path, bearer=None):
    req = urllib.request.Request(B + path)
    if bearer:
        req.add_header("Authorization", "Bearer " + bearer)
    try:
        with urllib.request.urlopen(req, timeout=60) as r:
            return r.status, json.loads(r.read() or b"{}")
    except urllib.error.HTTPError as e:
        return e.code, {}

def want(name, got, exp):
    print(("ok   " if got == exp else "BAD  ") + f"{name}: {got}" + ("" if got == exp else f" (expected {exp})"))
    if got != exp:
        bad.append(name)

want("no key -> projects", get("/api/v1/projects")[0], 401)
want("a wrong key -> projects", get("/api/v1/projects", "not-a-key")[0], 401)
c, body = get("/api/v1/projects", key)
want("chain key -> projects", c, 200)
want("app ScSeuratCombine is served", get("/api/v1/application_configs/ScSeuratCombine", key)[0], 200)
want("app CellRanger is still served", get("/api/v1/application_configs/CellRanger", key)[0], 200)
# The new process's environment, compared by NAME and expected value; nothing is printed.
env = dict(kv.split("=", 1) for kv in open(f"/proc/{pid}/environ", "rb").read().decode(errors="replace").split("\0") if "=" in kv)
for k, v in (("SUSHI_REQUIRE_AUTH", "1"), ("ENABLE_LDAP", "1"), ("BFABRICPY_CONFIG_ENV", "TEST")):
    want(f"env {k} is {v}", env.get(k) == v, True)
sys.exit(1 if bad else 0)
PYEOF
code=$(curl -s -o /dev/null -w '%{http_code}' http://127.0.0.1:4000/login || true)
echo "Omics-Studio :4000 /login -> $code (sign in once in a browser to be sure)"

echo
echo "DONE. 083 now requires a key. The OMAKASE engine and the sushi-chain MCP use the chain key;"
echo "the team key comes next (issue_team_key_083.sh)."
