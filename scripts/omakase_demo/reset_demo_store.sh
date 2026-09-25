#!/usr/bin/env bash
# OMAKASE demo reset for the TEST profile (fgcz-h-083), 2026-09-25.
#
# Why: the engine accepts one candidate per (order, dataset, recipe, version) by design
# (a UNIQUE constraint), so a demo cannot propose the same recipe twice. This moves the
# test store aside so the next Propose starts fresh.
#
# Nothing is deleted. The store, its run logs and its outbox (the outbox is how
# notifications are de-duplicated) move to ~/.omakase/archive/demo_resets/<timestamp>/.
# Fixtures, events and the production profile are not touched.
# Refuses while a chain is running. The panel needs no restart: reload the page.
#
# Usage:  bash /srv/sushi/masa_test_new_sushi_20260527/scripts/omakase_demo/reset_demo_store.sh
set -euo pipefail
ROOT=${OMAKASE_ROOT:-$HOME/.omakase}
T=$ROOT/test
[ -d "$T" ] || { echo "STOP: no $T" >&2; exit 2; }
if pgrep -u "$USER" -f 'omakase_core\.omakase .* run ' >/dev/null; then
  echo "STOP: a chain is still running. Wait until it is DONE, then reset." >&2
  exit 2
fi
stamp=$(date +%Y%m%d-%H%M%S)
A=$ROOT/archive/demo_resets/$stamp
mkdir -p "$A"
moved=0
for f in omakase.sqlite3 omakase.sqlite3-wal omakase.sqlite3-shm; do
  if [ -e "$T/$f" ]; then mv "$T/$f" "$A/"; moved=$((moved + 1)); fi
done
for d in runs outbox; do
  if [ -d "$T/$d" ]; then mv "$T/$d" "$A/$d"; moved=$((moved + 1)); fi
done
echo "archived $moved item(s) to $A"
echo "kept: $(ls "$T/fixtures" 2>/dev/null | wc -l) fixture(s), $(ls "$T/events" 2>/dev/null | wc -l) event(s)"
echo "Reload the panel page. The next Propose creates candidate 1 again."
