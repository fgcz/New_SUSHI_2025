# `sushi-session` — one B-Fabric login, then a usable backend session

The New SUSHI backend can be driven without the web UI. This is the client side of that:
a human approves once in a browser, and afterwards this helper keeps a valid session alive
on its own until B-Fabric's refresh token expires.

```bash
S="python3 scripts/sushi_session/sushi-session"     # or chmod +x it and drop the python3

$S login --instance test --sushi http://localhost:3010
$S status
curl -H "Authorization: Bearer $($S token)" http://localhost:3010/api/v1/projects
```

The file is committed without an executable bit, so invoke it through `python3` unless you
`chmod +x` your own checkout. Putting it on `PATH` as `sushi-session` is the intended
end state.

Add `--write` at login if you intend to submit jobs. Without `api:write` the backend
refuses every non-safe method with `403 insufficient_scope` — that is the gate working, not
a bug.

## How often is a human needed?

```
[approve in a browser]  ← the only human step
        ↓
B-Fabric refresh token     lifetime: UNKNOWABLE from the client (measured, see below)
        ↓ automatic
B-Fabric access token      3600 s (measured)
        ↓ automatic
SUSHI JWT                  30 min
        ↓
   every API route

local encryption key       --key-ttl, default 12 h   ← lapses INDEPENDENTLY of all
                                                       of the above; see below
```

`token` walks that chain: it returns the cached JWT if it is still good, otherwise
re-exchanges, otherwise refreshes against B-Fabric first. **Nothing in the middle two steps
needs a person.** One approval therefore lasts as long as the refresh token, and `status`
prints how long that is together with where the number came from — the token endpoint's
own `refresh_expires_in`, an `exp` claim inside the refresh token, or `UNKNOWN` when
B-Fabric states neither.

### The answer, measured 2026-09-04: `UNKNOWN`, and that is final from here

Both sources were checked against a real login on the test instance, and neither carries
the number:

| source | result |
|---|---|
| `refresh_expires_in` / `refresh_token_expires_in` in the token response | absent |
| `exp` inside the refresh token | not applicable — the token is **36 characters with no dots**, a UUID-shaped opaque string, not a JWT |

So the lifetime is server-side state at B-Fabric and nothing returned to the client
reveals it. `status` says `lifetime UNKNOWN` because that is the honest answer, not
because the recording failed. Two ways remain to learn it, and only two:

1. **Wait it out.** Log in with a key that outlives the token (`--key-ttl 604800`, below)
   and keep calling `token`. The first `login` it demands is the answer.
2. **Ask the B-Fabric team.** It belongs with the other open questions for them.

### The trap that made this number look unmeasurable

The obvious way to find the refresh token's lifetime is to keep using the session and see
when it asks for another approval. **That measures the wrong thing.** The local key that
decrypts the state file has its own TTL — `--key-ttl`, 12 hours by default — and it is
usually the first to go. Observed: a session created at 16:08 could not be decrypted at
11:00 the next morning, 19 hours later, and the refresh token had nothing to do with it.

To actually reach the refresh token's expiry, ask for a key that outlives it:

```bash
$S --key-ttl 604800 login --instance test        # 7 days
```

**`--key-ttl` must come BEFORE the subcommand.** It is a top-level option, so
`login --key-ttl 604800` fails with `unrecognized arguments` (exit 2). This is easy to get
backwards and the error message does not hint at the cause.

Losing the key is not data loss and not a corrupted file: the ciphertext at
`~/.config/new-sushi/session.enc` survives and is simply useless without the key, which is
the property it was built for. The answer is `login` again, not repair.

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
