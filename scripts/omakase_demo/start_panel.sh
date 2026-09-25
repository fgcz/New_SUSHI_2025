#!/usr/bin/env bash
# Start (or stop) YOUR OWN OMAKASE web panel on fgcz-h-083, under your own account.
#
# The panel runs the same engine as the terminal commands, on the test profile, with
# your record (~/.omakase/test/) and your backend key (~/.omakase/test/backend_token).
# It needs no .env: everything is passed here. Your panel access key is generated once
# into ~/.omakase/panel_key (mode 600) and never appears on a command line; the full URL
# with the key is written to ~/.omakase/panel_url.txt (mode 600).
#
# Usage (on fgcz-h-083):
#   bash /srv/sushi/masa_test_new_sushi_20260527/scripts/omakase_demo/start_panel.sh <port>
#   bash /srv/sushi/masa_test_new_sushi_20260527/scripts/omakase_demo/start_panel.sh stop
# Pick a free port between 8780 and 8799 (8770 and 8771 are taken).
set -euo pipefail

die() { printf 'STOP: %s\n' "$*" >&2; exit 2; }

HERE=$(cd "$(dirname "$0")" && pwd)
AGENT_DIR=${KAIROS_AGENT_DIR:-/srv/sushi/kairos_agent_server_dev}
PY=${OMAKASE_PYTHON:-/usr/local/ngseq/miniforge3/envs/gi_py3.12.8/bin/python3}
RUBY_BIN=/usr/local/ngseq/packages/Dev/Ruby/3.3.7/bin
PANEL_HOST=${PANEL_HOST:-0.0.0.0}
SESSION="omakase-panel-$USER"

[ "$(hostname -s)" = fgcz-h-083 ] || die "run this on fgcz-h-083 (the test instance)"

if [ "${1:-}" = stop ]; then
  screen -S "$SESSION" -X quit && echo "stopped screen $SESSION"
  exit 0
fi

PORT="${1:-}"
[[ "$PORT" =~ ^[0-9]+$ ]] && [ "$PORT" -ge 8780 ] && [ "$PORT" -le 8799 ] \
  || die "give a port between 8780 and 8799: start_panel.sh <port> | stop"
if ss -ltn | awk '{print $4}' | grep -q ":$PORT\$"; then die "port $PORT is in use; pick another"; fi
if screen -ls 2>/dev/null | grep -q "\.$SESSION[[:space:]]"; then
  die "you already run a panel (screen $SESSION); stop it first"
fi
[ -d "$AGENT_DIR/kairos_agent" ] || die "no panel code at $AGENT_DIR"
[ -s "$HOME/.omakase/test/backend_token" ] \
  || die "no ~/.omakase/test/backend_token yet: get a key from the 083 operator (README step 0)"
[ "$(stat -c %a "$HOME/.omakase/test/backend_token")" = 600 ] \
  || die "~/.omakase/test/backend_token must be mode 600"

umask 077
# The panel lists the orders it finds on disk; put the demo order where it looks.
mkdir -p "$HOME/.omakase/test/fixtures"
if [ ! -e "$HOME/.omakase/test/fixtures/order_35755_chain_fixture.json" ]; then
  cp "$HERE/order_35755_chain_fixture.json" "$HOME/.omakase/test/fixtures/"
fi

KEYF="$HOME/.omakase/panel_key"
if [ ! -s "$KEYF" ]; then
  "$PY" -c 'import secrets; print(secrets.token_urlsafe(32), end="")' > "$KEYF"
fi
URLF="$HOME/.omakase/panel_url.txt"
printf 'http://fgcz-h-083.fgcz-net.unizh.ch:%s/?key=%s\n' "$PORT" "$(cat "$KEYF")" > "$URLF"
LOG="$HOME/.omakase/panel_$PORT.screenlog"

# The key is read from its file INSIDE the screen's shell, so the value is never part of
# any process's command line.
screen -dmS "$SESSION" -L -Logfile "$LOG" bash -c "
  cd '$AGENT_DIR' || exit 1
  export KAIROS_AGENT_TOKEN=\"\$(cat '$KEYF')\"
  export KAIROS_AGENT_HOST='$PANEL_HOST' KAIROS_AGENT_PORT='$PORT' OMAKASE_PROFILE=test
  export PATH='$RUBY_BIN':\"\$PATH\" PYTHONDONTWRITEBYTECODE=1
  exec '$PY' -m kairos_agent.server
"

for _ in $(seq 1 30); do
  ss -ltn | awk '{print $4}' | grep -q ":$PORT\$" && break
  sleep 1
done
ss -ltn | awk '{print $4}' | grep -q ":$PORT\$" || die "the panel did not start; see $LOG"
echo "panel running: screen $SESSION, port $PORT, log $LOG"
echo "open the URL in ~/.omakase/panel_url.txt (run: cat ~/.omakase/panel_url.txt)"
echo "stop it with: bash $HERE/start_panel.sh stop"
