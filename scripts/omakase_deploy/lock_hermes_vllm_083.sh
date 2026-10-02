#!/usr/bin/env bash
# 2026-10-02. Restart the hermes gateway on fgcz-h-083 so it can ONLY use the FGCZ vLLM, and
# prove it. Run it ON 083 as masaomi:
#   bash /srv/sushi/masa_test_new_sushi_20260527/scripts/omakase_deploy/lock_hermes_vllm_083.sh
#
# Why: hermes' api_server honours a per-request `provider`, and with the real HOME it finds
# Claude Code's OAuth file, so a request naming `anthropic` reached the hosted API. The
# launcher (kairos_agent_server_dev/run_hermes_gateway.sh) now starts hermes with a
# credential-free HOME; config.yaml gives the MCP servers the real HOME back.
#
#   1. restart the WHOLE screen session hermes-gateway (its respawn loop keeps the old
#      environment, so killing only the gateway process would not pick up the new HOME)
#   2. check the new gateway's HOME (by name; the value is a path, compared, not printed)
#   3. a normal turn  -> must be answered by the vLLM model named in config.yaml
#   4. a turn naming provider=anthropic -> must fail, or be answered by the vLLM model
#   5. the omakase and kairos-chain MCP servers registered again
# Prints no key. Stops at the first surprise (exit 2).
#
# Undo: cp -p hermes_home/config.yaml.bak-20261002 hermes_home/config.yaml;
#       git -C /srv/sushi/kairos_agent_server_dev checkout run_hermes_gateway.sh; rerun step 1.
set -euo pipefail
A=/srv/sushi/kairos_agent_server_dev
HLOG=$A/hermes_home/logs/agent.log
LOCKED_HOME=$A/hermes_home/vllm_only_home
die() { printf 'STOP: %s\n' "$*" >&2; exit 2; }
say() { printf '\n== %s\n' "$*"; }
has_screen() { local out; out=$(screen -ls 2>/dev/null || true); grep -q "\.$1[[:space:]]" <<<"$out"; }
pid_on() { local out; out=$(ss -ltnpH "sport = :$1" 2>/dev/null || true); grep -o 'pid=[0-9]*' <<<"$out" | head -1 | cut -d= -f2 || true; }

[ "$(hostname -s)" = fgcz-h-083 ] || die "run this on fgcz-h-083, not $(hostname -s)"
grep -q 'export HOME="$HERMES_HOME/vllm_only_home"' "$A/run_hermes_gateway.sh" \
  || die "run_hermes_gateway.sh does not carry the vLLM-only HOME yet"
[ -d "$LOCKED_HOME" ] || die "$LOCKED_HOME does not exist"
[ -z "$(ls -A "$LOCKED_HOME/.claude" 2>/dev/null)" ] || die "$LOCKED_HOME/.claude is not empty"

say "1. restart screen hermes-gateway"
old=$(pid_on 8642)
mark=$(wc -l < "$HLOG")
if has_screen hermes-gateway; then screen -S hermes-gateway -X quit; fi
for _ in $(seq 1 30); do sleep 2; [ -z "$(pid_on 8642)" ] && break; done
[ -z "$(pid_on 8642)" ] || die "port 8642 is still taken after the screen quit (pid $(pid_on 8642))"
screen -dmS hermes-gateway -L -Logfile /tmp/hermes_gateway_8642.screenlog bash "$A/run_hermes_gateway.sh"
new=""
for _ in $(seq 1 60); do sleep 2; new=$(pid_on 8642); [ -n "$new" ] && break; done
[ -n "$new" ] || die "hermes did not come back on 8642 within 120 s; look: screen -r hermes-gateway"
echo "hermes gateway: pid ${old:-none} -> $new"

say "2. the gateway's HOME"
home_now=$(tr '\0' '\n' < "/proc/$new/environ" | grep '^HOME=' | head -1 | cut -d= -f2-)
[ "$home_now" = "$LOCKED_HOME" ] && echo "HOME is the credential-free directory" \
  || die "the gateway's HOME is not $LOCKED_HOME"

say "5. MCP servers (waiting up to 90 s)"
for _ in $(seq 1 45); do
  tail -n +"$((mark + 1))" "$HLOG" | grep -q "MCP server 'omakase'.*registered" && break
  sleep 2
done
tail -n +"$((mark + 1))" "$HLOG" | grep -E "MCP server '(omakase|kairos-chain)' \(stdio\)" \
  | sed -E 's/(registered [0-9]+ tool\(s\)).*/\1/' | cut -c1-160 || true
tail -n +"$((mark + 1))" "$HLOG" | grep -q "MCP server 'omakase'.*registered" \
  || die "omakase MCP server did not register; read $HLOG"

say "3 + 4. which model answers"
cd "$A"
python3 - <<'EOF'
import sys, yaml, httpx
sys.path.insert(0, ".")
from kairos_agent import config as C
key = C._hermes_api_key()
if not key:
    sys.exit("STOP: no hermes API key found")
want = yaml.safe_load(open("hermes_home/config.yaml"))["model"]["default"]
H = {"Authorization": f"Bearer {key}"}
BASE = "http://127.0.0.1:8642"

def turn(extra):
    body = {"model": "hermes-agent", "messages": [{"role": "user", "content": "Reply with exactly: OK"}]}
    body.update(extra)
    r = httpx.post(BASE + "/v1/chat/completions", headers=H, json=body, timeout=280)
    try:
        reply = (r.json().get("choices") or [{}])[0].get("message", {}).get("content") or ""
    except Exception:
        reply = r.text
    sid = r.headers.get("x-hermes-session-id")
    model = None
    if sid:
        s = httpx.get(f"{BASE}/api/sessions/{sid}", headers=H, timeout=30)
        if s.status_code == 200:
            model = (s.json().get("session") or {}).get("model")
    return r.status_code, model, reply.strip()

code, model, reply = turn({})
print(f"normal turn: HTTP {code}, answered by {model}")
if code != 200 or model != want:
    sys.exit(f"STOP: a normal turn must be answered by {want}")
code, model, reply = turn({"provider": "anthropic", "model": "claude-sonnet-4-5"})
print(f"provider=anthropic: HTTP {code}, session model {model}, reply {reply[:100]!r}")
# The session may record the REQUESTED model even when no call succeeded, so the test is
# whether a hosted model actually produced the answer.
if code == 200 and model not in (None, want) and reply == "OK":
    sys.exit("STOP: a hosted model answered - the lock does NOT hold")
print(f"OK: only {want} answers")
EOF
echo
echo "done: hermes is vLLM-only. The panel (:8770) talks to it over HTTP and needs no restart."
