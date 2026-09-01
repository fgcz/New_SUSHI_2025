#!/bin/bash
# New SUSHI frontend — 082 internal (non-public) instance, :4000.
#
# Unlike 083 this builds and serves a PRODUCTION bundle rather than running
# `next dev`. Two reasons: 082 is the production node and recompiling on every
# request there is wasteful, and a dev server keeps the whole module graph in
# memory — this box has 15 GB and NO SWAP (it is the submit node, not a compute
# node), so a bounded build followed by a small server is the safer shape.
#
# NEXT_PUBLIC_API_URL IS INLINED AT BUILD TIME. Next.js substitutes NEXT_PUBLIC_*
# into the client bundle during `next build`, so pointing this instance at a
# different backend means rebuilding, not just restarting.
#
# The backend this talks to is read-only (SUSHI_READ_ONLY=1 in
# run_backend_082.sh), so every write the UI offers will be refused by the Rack
# guard with a 403 naming the policy. That is the intended posture.
set -euo pipefail
cd "$(dirname "$0")/frontend"

PORT=${PORT:-4000}
export NEXT_PUBLIC_API_URL=${NEXT_PUBLIC_API_URL:-http://fgcz-h-082.fgcz-net.unizh.ch:3010}

# Cap the build heap. Left unbounded, next build sizes its heap from total RAM,
# and on a swapless box an overshoot is an OOM kill rather than a slowdown —
# one that would land on the node that submits every production job.
export NODE_OPTIONS=${NODE_OPTIONS:---max-old-space-size=3072}

PIDF="$PWD/.next-server-082.pid"

# Stop whatever actually HOLDS THE SOCKET, not whatever a pid file remembers.
#
# `next start` runs behind an npm/npx wrapper, so the `$!` recorded below is the
# WRAPPER. Killing that merely orphans the `next-server` child that owns :PORT —
# it reparents to init and keeps serving. This node spent a morning answering
# every request from a build four hours old for exactly that reason, and the
# health check at the bottom passed each time, because the orphan cheerfully
# returns 200. Killing by listening socket cannot make that mistake.
#
# `|| true` is load-bearing, not defensive noise. When the port is FREE, grep
# matches nothing and exits 1; under the `set -euo pipefail` at the top of this
# file that failure propagates out of the command substitution and kills the
# script. It did: the first version stopped the old server, then died before
# building, taking :4000 down with no message — the caller's pipe to `tail` had
# swallowed the status. "No listener" is the normal answer here, not an error.
listeners_on_port() {
  ss -ltnp "sport = :$PORT" 2>/dev/null |
    grep -oE 'pid=[0-9]+' | cut -d= -f2 | sort -u || true
}

for sig in TERM TERM KILL; do
  OLD=$(listeners_on_port)
  [ -n "$OLD" ] || break
  echo "stopping :$PORT held by pid(s) $(echo "$OLD" | tr '\n' ' ')(SIG$sig) ..."
  # shellcheck disable=SC2086
  kill -"$sig" $OLD 2>/dev/null || true
  for _ in $(seq 1 10); do [ -n "$(listeners_on_port)" ] || break; sleep 1; done
done
rm -f "$PIDF"

# Refuse to continue rather than build for ten minutes and then hand the user a
# 200 from someone else's process.
if [ -n "$(listeners_on_port)" ]; then
  echo "ABORT: :$PORT is still held by pid(s) $(listeners_on_port | tr '\n' ' ')"
  exit 1
fi

if [ ! -d node_modules ]; then
  echo "node_modules missing — run: npm ci --no-audit --no-fund"
  exit 1
fi

echo "building (API=$NEXT_PUBLIC_API_URL, NODE_OPTIONS=$NODE_OPTIONS) ..."
npx next build

echo "starting :$PORT ..."
nohup npx next start --port "$PORT" --hostname 0.0.0.0 \
  > /tmp/newsushi_frontend_082_${PORT}.log 2>&1 &
echo $! > "$PIDF"
echo "launched pid $(cat "$PIDF")  (log: /tmp/newsushi_frontend_082_${PORT}.log)"

for _ in $(seq 1 20); do
  code=$(curl -s -o /dev/null -w '%{http_code}' "http://127.0.0.1:$PORT/login" 2>/dev/null || true)
  if [ "$code" = "200" ]; then
    # A 200 only proves that SOMETHING answers. Name the process that answers and
    # how old it is, so a stale orphan can never again pass for a deployment.
    # Comparing the served bundle instead does NOT work: an unchanged page keeps
    # its chunk hash across builds, and the App Router puts no build id in the
    # HTML. Age is the honest signal.
    holder=$(listeners_on_port | head -1)
    age=$(ps -o etimes= -p "${holder:-0}" 2>/dev/null | tr -d ' ')
    if [ -n "$age" ] && [ "$age" -gt 300 ]; then
      echo "ABORT: :$PORT answers 200 but is held by pid $holder, alive ${age}s —"
      echo "       that predates this build, so it is NOT what was just deployed"
      exit 1
    fi
    echo "frontend up (/login=$code), served by pid ${holder:-?} (${age:-?}s old)"
    exit 0
  fi
  sleep 3
done
echo "frontend did NOT answer on :$PORT — see /tmp/newsushi_frontend_082_${PORT}.log"
exit 1
