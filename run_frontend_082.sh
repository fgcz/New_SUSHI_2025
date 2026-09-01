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
if [ -f "$PIDF" ]; then
  OLD=$(cat "$PIDF")
  if kill -0 "$OLD" 2>/dev/null; then
    echo "stopping old :$PORT pid $OLD ..."
    kill "$OLD" || true
    for _ in $(seq 1 15); do kill -0 "$OLD" 2>/dev/null || break; sleep 1; done
  fi
  rm -f "$PIDF"
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
  if [ "$code" = "200" ]; then echo "frontend up (/login=$code)"; exit 0; fi
  sleep 3
done
echo "frontend did NOT answer on :$PORT — see /tmp/newsushi_frontend_082_${PORT}.log"
exit 1
