#!/usr/bin/env bash
# 2026-09-29. Take away GROUP write from what the shared OMAKASE panel executes or trusts.
# Run it ON 083 as masaomi:   bash /srv/sushi/masa_test_new_sushi_20260527/scripts/omakase_deploy/fix_perms_083.sh
#
# Why: SG_Employees could write these (measured 2026-09-29: *.py 664, dirs 775). Every panel
# button starts a fresh `python -m omakase_core.omakase` as masaomi with the 083 key in its
# environment, so an edit by any group member would run as masaomi on the next click; and a
# planted runs/*.json could make the panel show the tail of any file masaomi can read.
# Only group WRITE is removed; reading stays as it is. The rest of the New SUSHI repository
# is left alone (it may be shared on purpose).
set -euo pipefail

[ "$(hostname -s)" = fgcz-h-083 ] || { echo "STOP: run this on fgcz-h-083" >&2; exit 2; }

targets=(
  /srv/sushi/kairos_agent_server_dev                       # panel + chat code, run.sh, tools.yaml, hermes_home
  /srv/sushi/masa_test_new_sushi_20260527/scripts/omakase_core
  /srv/sushi/masa_test_new_sushi_20260527/scripts/omakase_order_watch
  /srv/sushi/masa_test_new_sushi_20260527/scripts/omakase_demo
  /srv/sushi/masa_test_new_sushi_20260527/scripts/bin          # omakase_cli (2026-09-30)
  /srv/sushi/masa_test_new_sushi_20260527/scripts/omakase_deploy   # these scripts (2026-09-30)
  "$HOME/.omakase"
  "$HOME/.kairos_agent"
)
for t in "${targets[@]}"; do
  [ -e "$t" ] || { echo "skip (absent): $t"; continue; }
  before=$(find "$t" -perm -g+w 2>/dev/null | wc -l)
  chmod -R g-w "$t"
  after=$(find "$t" -perm -g+w 2>/dev/null | wc -l)
  echo "$t: group-writable entries $before -> $after"
done
echo
echo "DONE. Group members can still read these; only masaomi can change them."
