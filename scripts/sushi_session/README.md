# `sushi-session` — one B-Fabric login, then a usable backend session

The New SUSHI backend can be driven without the web UI. This is the client side of that:
a human approves once in a browser, and afterwards this helper keeps a valid session alive
on its own until B-Fabric's refresh token expires.

```bash
scripts/sushi_session/sushi-session login --instance test --sushi http://localhost:3010
scripts/sushi_session/sushi-session status
curl -H "Authorization: Bearer $(scripts/sushi_session/sushi-session token)" \
     http://localhost:3010/api/v1/projects
```

Add `--write` at login if you intend to submit jobs. Without `api:write` the backend
refuses every non-safe method with `403 insufficient_scope` — that is the gate working, not
a bug.

## How often is a human needed?

```
[approve in a browser]  ← the only human step
        ↓
B-Fabric refresh token     lifetime: NOT YET MEASURED   ← re-approve when this lapses
        ↓ automatic
B-Fabric access token      3600 s (measured)
        ↓ automatic
SUSHI JWT                  30 min
        ↓
   every API route
```

`token` walks that chain: it returns the cached JWT if it is still good, otherwise
re-exchanges, otherwise refreshes against B-Fabric first. **Nothing in the middle two steps
needs a person.** One approval therefore lasts as long as the refresh token — a number
nobody has measured yet, and one of the open questions for the B-Fabric team.

## Where the credentials live

| what | where |
|---|---|
| the session (refresh token, access token, JWT) | `~/.config/new-sushi/session.enc`, AES-256-GCM, mode 0600 |
| the 32-byte key | the **kernel keyring** (`@u`, description `new-sushi-session`), never written to disk |

That split is chosen from two measurements on the FGCZ nodes, not from habit:

* **`$HOME` is NFS** (`fgcz-home-linux:/Homes/<user>`). A plaintext token in the home
  directory crosses the network and lands on a fileserver, inside whatever backup regime it
  has. bfabricPy's own token cache is plaintext-in-`$HOME`; here that is a worse trade than
  it looks.
* **The kernel keyring is available** (keyutils 1.6.1, a live `@u` keyring), so the key can
  stay in kernel memory, scoped to this user on this host.

### What this protects against — and what it does not

| | |
|---|---|
| **defeated** | the file leaving the host: backup, rsync, scp, an accidental commit |
| **defeated** | another user on the node reading the file (0600 as well) |
| **defeated** | the NFS server, or anyone holding a snapshot of it |
| **not defeated** | root on this host |
| **not defeated** | anything running as you on this host — including this helper, by design |

"Encrypted at rest" is often claimed to mean more than that. It does not here. If you need
the last two rows, use `--key-mode passphrase`: the key is then derived from something only
you know and nothing on the machine can decrypt the file. The cost is that you type it —
`SUSHI_SESSION_PASSPHRASE` avoids the typing and puts the secret back on the machine, which
is a fair trade only if you know that is what you are doing.

`--no-refresh` keeps B-Fabric's refresh token out of the file entirely. It is the strongest
credential in play — LIMS-wide and long-lived, strictly bigger than the SUSHI session it
renews — so leaving it out is a real option; the cost is re-approving about hourly.

`logout` removes the file and drops the key. It does **not** end your B-Fabric session:
B-Fabric publishes no `end_session_endpoint`, so signing in again often completes with no
prompt.

## Not a replacement for the static token

`ApiToken` / `SUSHI_ENV_TOKEN_*` remains the only credential for work where a human can
never be present, such as unattended CI. Device code always needs one approval. This helper
narrows how often, not whether.

## Self-test

```bash
python3 scripts/sushi_session/selftest.py     # 19 checks, no network, no approval
```

It uses a throwaway config directory and keyring entry. The load-bearing check is
**"the file alone is useless once the key is dropped"** — if that ever fails, the design's
central claim is false and the encryption is decoration.
