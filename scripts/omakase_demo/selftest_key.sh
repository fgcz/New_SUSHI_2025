#!/usr/bin/env bash
# Check a demo key end to end, as its future owner would use it, before handing it over.
#
# For the 083 operator, on fgcz-h-083. Uses a fresh scratch record under
# ~/.omakase/archive/key_selftests/<time>/ (mode 700, kept as the record of the check),
# never the operator's own ~/.omakase/test. The operator's own key is ignored
# (NEWSUSHI_TOKEN_083 is unset), so a pass can only come from the key under test.
#
# Default: propose fastqc_only on the demo order, show, approve, dry run - reads only.
# --run:   also run it for real (one FastQC job, about 6 minutes), which proves the key
#          may submit, and print who the backend recorded as the submitter.
#
# Usage:
#   bash scripts/omakase_demo/selftest_key.sh ~/.omakase/demo_keys/<login>.key [--run]
set -euo pipefail

die() { printf 'STOP: %s\n' "$*" >&2; exit 2; }

KEY="${1:-}"
RUN="${2:-}"
[ -r "$KEY" ] || die "give the key file: selftest_key.sh <file> [--run]"
[ "$(stat -c %a "$KEY")" = 600 ] || die "$KEY must be mode 600"
[ -z "$RUN" ] || [ "$RUN" = "--run" ] || die "the only option is --run"

HERE=$(cd "$(dirname "$0")" && pwd)
SCRIPTS=$(dirname "$HERE")
FIXTURE="$HERE/order_35755_chain_fixture.json"

umask 077
ROOT="$HOME/.omakase/archive/key_selftests/$(date +%Y%m%d-%H%M%S)"
mkdir -p "$ROOT/test"
cp "$KEY" "$ROOT/test/backend_token"
chmod 600 "$ROOT/test/backend_token"
unset NEWSUSHI_TOKEN_083
export OMAKASE_ROOT="$ROOT" PYTHONDONTWRITEBYTECODE=1
cd "$SCRIPTS"
O=(python3 -m omakase_core.omakase)

echo "== scratch record: $ROOT"
echo "== 1. propose fastqc_only on order 35755"
"${O[@]}" ingest --event "$FIXTURE" --recipe fastqc_only 2>&1 | grep -E "candidate [0-9]+:|input:|DECLINED|FAILED" || true
"${O[@]}" show 2>&1 | grep -E "^ +[0-9]+ " | head -3 || true
cid=$("${O[@]}" show 2>&1 | awk '/^ +[0-9]+ +PROPOSED/{print $1; exit}')
[ -n "$cid" ] || die "no PROPOSED candidate: the key could not read project 35611 (see the lines above)"

echo "== 2. approve candidate $cid as $USER (key self-test)"
"${O[@]}" approve --candidate "$cid" --actor "$USER (key self-test)" 2>&1 | tail -1

echo "== 3. dry run"
"${O[@]}" run --candidate "$cid" --dry-run 2>&1 | grep -v -E "DEBUG|INFO" | tail -3 || true

if [ "$RUN" = "--run" ]; then
  echo "== 4. real run (about 6 minutes)"
  "${O[@]}" run --candidate "$cid" 2>&1 | grep -E "COMPLETED|DONE|HALTED|FAILED" | tail -4 || true
  python3 - "$ROOT/test/omakase.sqlite3" "$ROOT/test/backend_token" <<'PY'
import json, sqlite3, sys, urllib.request
db = sqlite3.connect(f"file:{sys.argv[1]}?mode=ro", uri=True)
key = open(sys.argv[2]).read().strip()
for (jobs,) in db.execute("select sushi_job_ids_json from submissions"):
    for j in json.loads(jobs or "[]"):
        req = urllib.request.Request(f"http://fgcz-h-083.fgcz-net.unizh.ch:3010/api/v1/jobs/{j}",
                                     headers={"Authorization": "Bearer " + key})
        job = json.load(urllib.request.urlopen(req, timeout=60))["job"]
        print(f"   job {j}: {job['status']}, submitted as {job['user']}")
PY
fi
echo "== done. Record kept in $ROOT"
