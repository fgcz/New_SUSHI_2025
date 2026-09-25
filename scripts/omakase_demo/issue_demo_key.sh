#!/usr/bin/env bash
# Issue, list or revoke a personal OMAKASE demo key on fgcz-h-083 (the TEST backend).
#
# For the 083 operator. Writes only to 083's TEST database (`api_tokens`), never to
# production. Each key is static, scoped to project 35611 (where the demo data is),
# may submit jobs, expires after TTL days, and is named `omakase-demo-<login>`, so jobs
# it submits are attributed to `apitoken:omakase-demo-<login>`.
#
# The raw key is NEVER printed: it goes to ~/.omakase/demo_keys/<login>.key (mode 600).
# Hand it to the person privately; they save it as ~/.omakase/test/backend_token.
#
# Usage (from anywhere, on fgcz-h-083):
#   bash scripts/omakase_demo/issue_demo_key.sh issue  <login> [ttl_days, default 30]
#   bash scripts/omakase_demo/issue_demo_key.sh list
#   bash scripts/omakase_demo/issue_demo_key.sh revoke <id>     (demo keys only)
set -euo pipefail

die() { printf 'STOP: %s\n' "$*" >&2; exit 2; }

[ "$(hostname -s)" = fgcz-h-083 ] || die "run this on fgcz-h-083 (the TEST backend), not $(hostname -s)"
REPO=$(cd "$(dirname "$0")/../.." && pwd)
cd "$REPO/backend"

# The same environment the running :3010 uses (run_backend_083.sh). The pinned secret
# matters: a key's stored hash is salted with it, so a key minted under any other
# secret would never verify against the running server.
set -a; . /etc/sushi/secret.env; set +a
SKB_FILE="$PWD/.secret_key_base_083"
[ -s "$SKB_FILE" ] || die "$SKB_FILE is missing; a key minted without it would not verify"
SECRET_KEY_BASE="$(cat "$SKB_FILE")"
export SECRET_KEY_BASE RAILS_ENV=development LEGACY_DATABASE=true

rake_list() { bundle exec rake api_token:list 2>/dev/null; }

case "${1:-}" in
  issue)
    login="${2:-}"
    ttl="${3:-30}"
    [[ "$login" =~ ^[a-z][a-z0-9._-]{0,31}$ ]] || die "give a login name: issue <login> [ttl_days]"
    [[ "$ttl" =~ ^[0-9]+$ ]] && [ "$ttl" -ge 1 ] && [ "$ttl" -le 90 ] || die "ttl_days must be 1-90"
    umask 077
    keydir="$HOME/.omakase/demo_keys"
    mkdir -p "$keydir"
    keyfile="$keydir/$login.key"
    [ -e "$keyfile" ] && die "$keyfile exists; revoke the old key first (list, then revoke <id>)"
    # Held in a variable only, so the raw key never touches the terminal or a temp file.
    out=$(bundle exec rake api_token:issue NAME="omakase-demo-$login" PRINCIPAL=static \
            SCOPE=35611 CAPABILITIES=read,write TTL_DAYS="$ttl" 2>/dev/null)
    printf '%s\n' "$out" | grep '^Issued API token' || die "the rake task did not issue a key"
    raw=$(printf '%s\n' "$out" | tail -1 | tr -d '[:space:]')
    [ "${#raw}" -ge 20 ] || die "unexpected rake output; nothing written"
    printf '%s' "$raw" > "$keyfile"
    unset out raw
    echo "key written to $keyfile (mode $(stat -c %a "$keyfile")); not shown."
    echo "Give it to $login privately. They run, on fgcz-h-083:"
    echo "  mkdir -p ~/.omakase/test && (umask 077; cat > ~/.omakase/test/backend_token)"
    echo "then paste the key, press Enter, then Ctrl-D."
    ;;
  list)
    rake_list | grep 'name=omakase-demo-' || echo "(no demo keys)"
    ;;
  revoke)
    id="${2:-}"
    [[ "$id" =~ ^[0-9]+$ ]] || die "give a token id: revoke <id> (see list)"
    rake_list | grep -E "^id=$id +.*name=omakase-demo-" >/dev/null \
      || die "id $id is not an omakase-demo key; refusing"
    bundle exec rake api_token:revoke ID="$id" 2>/dev/null
    ;;
  *)
    sed -n '2,16p' "$0" | sed 's/^# \{0,1\}//'
    exit 2
    ;;
esac
