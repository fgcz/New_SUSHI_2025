#!/usr/bin/env bash
# The OMAKASE TEAM key on fgcz-h-083: the backend key the SHARED panel and hermes submit with.
#
# One static key, `omakase-team-083`, read+write, 90 days, scoped to EVERY project in 083's
# TEST database (counted from the database when it is issued; 19 on 2026-09-29). Jobs it
# submits are attributed to `apitoken:omakase-team-083`, so they stay distinguishable from
# the operator's own `chain` key (Claude Code, the command line) and from personal demo keys.
# Who released each chain is in OMAKASE's record and in the output dataset's comment.
#
# Writes only to 083's TEST database (`api_tokens`) and to two local files, never to
# production. The raw key is never printed: it goes straight into
#   /srv/sushi/kairos_agent_server_dev/.env              NEWSUSHI_TOKEN_083=      (the panel)
#   /srv/sushi/kairos_agent_server_dev/hermes_home/.env  OMAKASE_TEAM_TOKEN_083=  (hermes)
# each backed up first and kept at mode 600. Restart the panel and hermes afterwards.
#
# Usage, on fgcz-h-083:
#   bash scripts/omakase_demo/issue_team_key.sh issue     # the first time
#   bash scripts/omakase_demo/issue_team_key.sh refresh   # new projects in 083, or before it expires:
#                                                         # a new key over all projects, the old revoked
#   bash scripts/omakase_demo/issue_team_key.sh list
set -euo pipefail

NAME=omakase-team-083
PANEL_ENV=/srv/sushi/kairos_agent_server_dev/.env
HERMES_ENV=/srv/sushi/kairos_agent_server_dev/hermes_home/.env

die() { printf 'STOP: %s\n' "$*" >&2; exit 2; }

[ "$(hostname -s)" = fgcz-h-083 ] || die "run this on fgcz-h-083 (the TEST backend), not $(hostname -s)"
REPO=$(cd "$(dirname "$0")/../.." && pwd)
cd "$REPO/backend"

# The environment the running :3010 uses; the pinned secret salts every stored key hash.
set -a; . /etc/sushi/secret.env; set +a
SKB_FILE="$PWD/.secret_key_base_083"
[ -s "$SKB_FILE" ] || die "$SKB_FILE is missing; a key minted without it would not verify"
SECRET_KEY_BASE="$(cat "$SKB_FILE")"
export SECRET_KEY_BASE RAILS_ENV=development LEGACY_DATABASE=true

rake_list() { bundle exec rake api_token:list 2>/dev/null; }
active_ids() { rake_list | grep -E "^id=[0-9]+ +active .* name=$NAME\$" | sed -E 's/^id=([0-9]+).*/\1/' || true; }

# Put KEY=<the raw key> into FILE: replace the line or append it. The value travels in the
# environment of one python process, never on a command line (ps would show it).
put_env() {
  local file=$1 key=$2
  [ -f "$file" ] || die "$file does not exist"
  cp -p "$file" "$file.bak-$(date +%Y%m%d-%H%M%S)"
  RAW="$raw" python3 - "$file" "$key" <<'PYEOF'
import os, sys
path, key = sys.argv[1], sys.argv[2]
lines = open(path).read().splitlines()
new = f"{key}={os.environ['RAW']}"
out, done = [], False
for line in lines:
    if line.startswith(key + "="):
        if not done:
            out.append(new)
            done = True
        continue
    out.append(line)
if not done:
    out.append(new)
fd = os.open(path + ".tmp", os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
with os.fdopen(fd, "w") as fh:
    fh.write("\n".join(out) + "\n")
os.replace(path + ".tmp", path)
PYEOF
  chmod 600 "$file"
  echo "  $key written to $file (mode $(stat -c %a "$file")); backup beside it"
}

case "${1:-}" in
  issue|refresh)
    old=$(active_ids)
    if [ "$1" = issue ] && [ -n "$old" ]; then
      die "an active $NAME exists (id $old); use refresh to replace it"
    fi
    scope=$(bundle exec rails runner 'puts Project.order(:number).pluck(:number).join(",")' 2>/dev/null | tail -1)
    [[ "$scope" =~ ^[0-9]+(,[0-9]+)*$ ]] || die "could not read the project list from the 083 database"
    echo "scope: $(tr ',' '\n' <<<"$scope" | wc -l) project(s) in 083's TEST database"
    umask 077
    # Held in a variable only, so the raw key never touches the terminal or a temp file.
    out=$(bundle exec rake api_token:issue NAME="$NAME" PRINCIPAL=static SCOPE="$scope" \
            CAPABILITIES=read,write TTL_DAYS=90 2>/dev/null)
    printf '%s\n' "$out" | grep '^Issued API token' || die "the rake task did not issue a key"
    raw=$(printf '%s\n' "$out" | tail -1 | tr -d '[:space:]')
    [ "${#raw}" -ge 20 ] || die "unexpected rake output; nothing written"
    unset out
    put_env "$PANEL_ENV" NEWSUSHI_TOKEN_083
    put_env "$HERMES_ENV" OMAKASE_TEAM_TOKEN_083
    unset raw
    for id in $old; do
      bundle exec rake api_token:revoke ID="$id" 2>/dev/null
    done
    echo
    echo "Now restart the panel and hermes so they use it:"
    echo "  bash /srv/sushi/masa_test_new_sushi_20260527/scripts/omakase_deploy/restart_chat_083.sh"
    ;;
  list)
    rake_list | grep "name=$NAME\$" || echo "(no $NAME key yet)"
    ;;
  *)
    sed -n '2,20p' "$0" | sed 's/^# \{0,1\}//'
    exit 2
    ;;
esac
