# B-Fabric OAuth2 / OIDC checks

Read-only measurement tooling for the B-Fabric OIDC login. Nothing here writes to a
database, starts a server, or touches the production node's processes.

## Why a measurement step exists at all

New SUSHI refuses to enable B-Fabric OIDC until `BFABRIC_OIDC_AUDIENCE` is set. That is
deliberate: without an expected `aud`, a token minted for **any** other B-Fabric relying
party would verify here on its signature alone, and any tool a user ever consented to
would hold a working New SUSHI credential. The audience is a *measurement*, not a guess,
so the feature stays off until someone has taken it.

## `measure_token_claims.sh`

```
bash scripts/bfabric_oauth_check/measure_token_claims.sh test    # M1
bash scripts/bfabric_oauth_check/measure_token_claims.sh prod    # M2
```

Runs a real device-code login using the **public** client `CLI`, which already exists on
both instances — so this needs no client registration, no client secret and no
`redirect_uri`. It prints the discovery endpoints, then a URL and a user code.

**One human step:** open that URL in any browser, on any machine, and approve. Everything
else is `curl`. About ten minutes.

It then decodes the returned tokens **locally** and prints:

| what | why it matters |
|---|---|
| the access token's claim names | the verifier's accept criteria are defined from this |
| `iss`, `aud`, `scope`, `sub` | `aud` is the blocking value; `sub` is expected to be the login string |
| whether `client_id` / `azp` exists | decides whether a per-client allow-list is possible at all |
| the id_token's `aud` | differs from the access token's; confirms the two are distinguishable |
| `/userinfo`'s claim names | the second channel `sub` can come from |
| `expires_in`, refresh token present | how long a headless session lasts before re-approval |

Finally it prints the exact `export` lines to set on the node.

### What it does not do

- **It never writes a token to disk.** Both tokens live in memory and are gone when the
  process exits.
- **It never prints a raw token** — only claim names and the handful of claim values the
  verifier needs.
- It does not touch 082, any database, or any running SUSHI process.

### If `client_id` and `azp` are both absent

That is the expected outcome: production's `claims_supported` lists neither (measured
2026-09-03). Leave `BFABRIC_OIDC_ALLOWED_CLIENT_IDS` **unset**. The backend then logs a
warning at boot saying plainly that any B-Fabric client's token is accepted, which is a
stated risk rather than a hidden one. Setting the variable turns the check on and makes it
strict — a token carrying neither claim is then *rejected*, because an allow-list that
silently passes everything reads like a control while being none.

## Related

- Backend implementation: `backend/lib/bfabric_oidc/`,
  `backend/app/controllers/api/v1/bfabric_auth_controller.rb`
- Posture assertions on a live node: `scripts/082_gate_check/` (sections 7 and 8)
