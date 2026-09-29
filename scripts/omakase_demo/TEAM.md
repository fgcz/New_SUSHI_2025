# The shared OMAKASE panel for a team (fgcz-h-083, test instance)

Since 2026-09-29 the team uses ONE panel, `http://fgcz-h-083.fgcz-net.unizh.ch:8770`, each
person with their own key. The panel then knows who is at the keyboard: whoever holds the
key is recorded as the approver of everything they release. (The alternative, each person
running their own instance, is in [README.md](README.md).)

```
member (own panel key) ─▶ shared panel :8770 ─▶ approver of record = the key's owner
                           └ engine ─▶ 083 backend (a key is required) with omakase-team-083
                                        └ the output dataset's comment: "approved by <name>"
chat (vLLM or hermes) ─▶ reads, fetches, proposes; approve / confirm / run are REQUESTS a
                         person must Allow (the model can never release anything itself)
```

## What is recorded where

| Question | Where the answer is |
|---|---|
| Who approved, confirmed, skipped, allowed or denied | OMAKASE's record (`~/.omakase/test/omakase.sqlite3`): the named key's owner |
| Who pressed Run | the run's record in `~/.omakase/test/runs/` (`started_by`) |
| Which key submitted a job | SUSHI: `apitoken:omakase-team-083` (the operator's own `chain` key is not used by the panel) |
| Who released it, as seen in SUSHI | the output dataset's comment: `OMAKASE candidate N step S, approved by <name>` (a label written by OMAKASE, not an identity SUSHI verified) |
| Whose chat thread it is | each thread's owner; a person sees only their own, the operator every thread |

## Limits, stated plainly

- **Results land in the real gStore**, in the input dataset's project folder
  (`/srv/gstore/projects/p<N>/`). 083's database is a test database, but the files are not.
- **Only data registered in 083's test database can be analysed.** On 2026-09-29, 19
  projects; raw data for the demo only in p35611 (dataset 9, bulk RNA mouse; dataset 819,
  tiny 10x 3' human).
- **B-Fabric TEST only.** An order is fetched from `fgcz-bfabric-test.uzh.ch`, never from
  production B-Fabric; 083's jobs register nothing in B-Fabric at all.
- **Automatic recipe choice declines today** (0 of 17 recipes match real order wording).
  Name the recipe.
- A named key cannot approve under another name; the name box is gone for it. Only the
  shared operator token still types a name.

## Part 1 — the operator (masaomi), once

Run each on fgcz-h-083, in this order.

```bash
# 1. the backend requires a key from now on (it ran without one since 2026-09-24)
bash ~/omakase_082_deploy/restart_backend_083.sh

# 2. only masaomi may change the code and records the panel runs
bash ~/omakase_082_deploy/fix_perms_083.sh

# 3. the team's backend key (all 083 projects, 90 days); written into the panel's and hermes' .env
bash /srv/sushi/masa_test_new_sushi_20260527/scripts/omakase_demo/issue_team_key.sh issue

# 4. restart the panel and hermes so they pick it up
bash ~/omakase_082_deploy/restart_chat_083.sh
```

## Part 2 — a key for each member

```bash
cd /srv/sushi/kairos_agent_server_dev

# issue (90 days by default; --days 30 for less). The key is never printed:
python3 -m kairos_agent.keys issue alice

# the URL with the key is in ~/.kairos_agent/issued/alice.url (mode 600).
# Hand it to alice privately (not in a chat, not in an AI tool), then:
rm ~/.kairos_agent/issued/alice.url

# who has a key, and until when (never shows a key)
python3 -m kairos_agent.keys list

# take a key away; it stops working on the next request, no restart
python3 -m kairos_agent.keys revoke alice
```

No restart is needed for issue or revoke: the panel re-reads the key file
(`~/.kairos_agent/keys_fgcz-h-083.json`, per host, so a key for 083 never opens the 082
production panel).

## Part 3 — the member

1. Open the URL once. The browser keeps a cookie; afterwards the plain address works.
2. The OMAKASE tab shows `signed in as <you>`.
3. Work as in the quickstart (`docs` link in the header): fetch an order, propose a named
   recipe, approve, run - from the buttons or from the chat. In the chat, approve / confirm /
   run come back as a request card; click **Allow** to release it (as yourself).
4. A step whose `when` does not hold (a combine step on one sample) has **Skip step**.

## Renewing

- The team key expires after 90 days, and new projects in 083 are not in its scope until
  it is refreshed: `bash .../issue_team_key.sh refresh` (a new key over all projects, the
  old one revoked), then `bash ~/omakase_082_deploy/restart_chat_083.sh`.
- Member keys: `keys issue` again after `keys revoke`, or when one expires.
