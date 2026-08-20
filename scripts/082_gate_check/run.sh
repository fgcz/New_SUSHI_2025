#!/bin/bash
# Run verify_gates.rb with EXACTLY the environment the node's server boots with.
#
# It sources the launch script up to its final `exec` rather than duplicating the
# variables, so this check cannot drift from what the server actually uses — which is the
# whole point, since what is being verified is the environment, not the logic (the logic is
# pinned by request specs on 083).
#
# Usage:
#   bash scripts/082_gate_check/run.sh                      # defaults to run_backend_082.sh
#   bash scripts/082_gate_check/run.sh /path/to/launch.sh
#
# Read-only. Starts no server and leaves no orphan process.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# REPO_DIR lets this run from outside the checkout (e.g. shipped to /tmp on a node whose
# checkout does not carry it yet).
REPO="${REPO_DIR:-$(dirname "$(dirname "$HERE")")}"
SRC="${1:-$REPO/run_backend_082.sh}"

if [ ! -r "$SRC" ]; then
  echo "launch script not readable: $SRC" >&2
  exit 2
fi
if ! grep -q '^exec bundle exec rails server' "$SRC"; then
  cat >&2 <<'WHY'
Refusing to run: this launch script does not end in a bare `exec bundle exec rails server`.

That marker is not cosmetic. This check works by SOURCING everything above it, so it only
works on a launcher that is pure environment followed by exec — which is 082's shape.
run_backend_083.sh, for instance, stops the previous instance first (`kill "$OLD"`), so
sourcing it would kill a running server. Refusing is the safe answer; do not relax this
into a "match either launcher form" regex.

To check a node with a different launcher, set the same variables by hand and run:
  bundle exec rails runner scripts/082_gate_check/verify_gates.rb
WHY
  exit 2
fi

# Everything before the exec line is the environment; the exec line and anything after it
# would launch the server, so it is cut.
# shellcheck disable=SC1090
. <(sed '/^exec bundle exec rails server/,$d' "$SRC")

echo "env: RAILS_ENV=${RAILS_ENV:-unset} SUSHI_READ_ONLY=${SUSHI_READ_ONLY:-unset} SUSHI_WRITE_POLICY=${SUSHI_WRITE_POLICY:-unset} SUSHI_REQUIRE_AUTH=${SUSHI_REQUIRE_AUTH:-unset}"
echo "     LEGACY_DATABASE=${LEGACY_DATABASE:-unset} LEGACY_APPS_DIR=${LEGACY_APPS_DIR:-unset}"
echo "     SUSHI_ENV_TOKEN_WRITE_* variables set: $(env | grep -c '^SUSHI_ENV_TOKEN_WRITE_' || true)"
echo "     revision: $(git -C "$REPO" rev-parse --abbrev-ref HEAD 2>/dev/null || echo '?') $(git -C "$REPO" rev-parse --short HEAD 2>/dev/null || echo '?')"
echo

exec bundle exec rails runner "$HERE/verify_gates.rb"
