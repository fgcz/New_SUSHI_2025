#!/usr/bin/env bash
# 2026-09-29. Restart the chat services on fgcz-h-083 so the chat can operate OMAKASE.
# Run it ON 083 as masaomi:
#   bash /srv/sushi/masa_test_new_sushi_20260527/scripts/omakase_deploy/restart_chat_083.sh
#
#   1. hermes gateway: stop the gateway process; run_hermes_gateway.sh (screen hermes-gateway)
#      starts it again within 5 s, with the new config.yaml (omakase MCP, kairos-chain without
#      the hosted-LLM tools, api_server toolsets = memory/todo/session_search + the two MCP
#      servers, auxiliary models pinned to the FGCZ vLLM). Backup: config.yaml.bak-20260929
#   2. panel :8770 (screen kairos-agent): restart, so it starts the omakase MCP server too
#   3. panel :8771 (screen kairos-agent-prod): stop. fgcz-h-082:8771 replaced it.
# Prints no key. Stops at the first surprise (exit 2).
#
# Undo hermes: cp -p hermes_home/config.yaml.bak-20260929 hermes_home/config.yaml, then step 1
set -euo pipefail

A=/srv/sushi/kairos_agent_server_dev
HLOG=$A/hermes_home/logs/agent.log

die() { printf 'STOP: %s\n' "$*" >&2; exit 2; }
say() { printf '\n== %s\n' "$*"; }
has_screen() { local out; out=$(screen -ls 2>/dev/null || true); grep -q "\.$1[[:space:]]" <<<"$out"; }
# Always rc 0: "nothing listens" is an empty answer, not a failure. (It was a failure on the
# first run, 2026-09-29 11:16, and set -e ended the script while hermes was restarting.)
pid_on() { local out; out=$(ss -ltnpH "sport = :$1" 2>/dev/null || true); grep -o 'pid=[0-9]*' <<<"$out" | head -1 | cut -d= -f2 || true; }

[ "$(hostname -s)" = fgcz-h-083 ] || die "run this on fgcz-h-083, not $(hostname -s)"

say "1. hermes gateway"
old=$(pid_on 8642)
[ -n "$old" ] || die "nothing listens on 127.0.0.1:8642"
case "$(ps -o args= -p "$old")" in *"hermes gateway run"*) ;; *) die "pid $old on 8642 is not 'hermes gateway run'";; esac
has_screen hermes-gateway || die "screen hermes-gateway is gone; nothing would start hermes again"
started=$(date -d "$(ps -o lstart= -p "$old")" +%s)
if [ "$started" -gt "$(stat -c %Y "$A/hermes_home/config.yaml")" ]; then
  # A rerun: hermes already started after the config was written, so it runs it.
  echo "hermes gateway pid $old started after config.yaml changed: not restarted again"
  mark=$(grep -n "MCP server 'omakase'" "$HLOG" | tail -1 | cut -d: -f1)
  mark=$(( ${mark:-1} - 1 ))
else
  mark=$(wc -l < "$HLOG")
  kill -TERM "$old"
  new=""
  for _ in $(seq 1 60); do
    sleep 2
    new=$(pid_on 8642)
    [ -n "$new" ] && [ "$new" != "$old" ] && break
  done
  [ -n "$new" ] && [ "$new" != "$old" ] || die "hermes did not come back on 8642 within 120 s; look: screen -r hermes-gateway"
  echo "hermes gateway: pid $old -> $new"
  for _ in $(seq 1 45); do
    tail -n +"$((mark + 1))" "$HLOG" | grep -q "MCP server 'omakase'" && break
    sleep 2
  done
fi
tail -n +"$((mark + 1))" "$HLOG" | grep -E "MCP server '(omakase|kairos-chain)' \(stdio\)" \
  | sed -E 's/(registered [0-9]+ tool\(s\)).*/\1/' | cut -c1-200 || true
tail -n +"$((mark + 1))" "$HLOG" | grep -q "MCP server 'omakase'.*registered" \
  || die "hermes has not registered the omakase MCP server; read $HLOG"

say "2. panel :8770 (screen kairos-agent)"
if has_screen kairos-agent; then screen -S kairos-agent -X quit; sleep 3; fi
[ -z "$(pid_on 8770)" ] || die "port 8770 is still taken"
screen -dmS kairos-agent -L -Logfile /tmp/kairos_agent_8770.screenlog bash "$A/run.sh"
for _ in $(seq 1 60); do sleep 2; [ -n "$(pid_on 8770)" ] && break; done
[ -n "$(pid_on 8770)" ] || die "the panel did not come up on 8770; look: screen -r kairos-agent"
python3 - "$A/.env" <<'PYEOF' || die "a panel check failed (see above)"
import json, sys, time, urllib.request
key = next(l.split("=", 1)[1].strip() for l in open(sys.argv[1]) if l.startswith("KAIROS_AGENT_TOKEN="))
def get(path):
    req = urllib.request.Request("http://127.0.0.1:8770" + path)
    req.add_header("Authorization", "Bearer " + key)
    return json.loads(urllib.request.urlopen(req, timeout=120).read())
for _ in range(45):
    try:
        h = get("/api/health"); break
    except Exception:
        time.sleep(2)
t = get("/api/tools")
ok = (h.get("chat") == "on" and h["vllm"].get("ok") and h["mcp"]["alive"]
      and h["omakase"]["chat_tools"] == {"alive": True, "tools": 16} and not set(t["denied"]) & set(t["core"]))
print(f"chat {h.get('chat')}, vllm ok {h['vllm'].get('ok')}, kairos-chain alive {h['mcp']['alive']}, "
      f"hermes ok {h['hermes'].get('ok')}, omakase tools {h['omakase']['chat_tools']}, "
      f"{len(t['denied'])} kairos-chain tools denied, {t['searchable_count']} of {t['available_count']} searchable")
sys.exit(0 if ok else 1)
PYEOF

say "3. panel :8771 (screen kairos-agent-prod)"
if has_screen kairos-agent-prod; then screen -S kairos-agent-prod -X quit; sleep 2; echo "stopped"; else echo "not running"; fi
[ -z "$(pid_on 8771)" ] || die "port 8771 is still taken on 083"

echo
echo "DONE. Chat on http://fgcz-h-083.fgcz-net.unizh.ch:8770 (same key as before)."
