"""Which B-Fabric instance pairs with which SUSHI backend, and where each pair keeps its files.

B-Fabric PRODUCTION and TEST are separate instances with separate order-id spaces, and each
SUSHI node holds datasets from exactly one of them: fgcz-h-083's test DB carries TEST order
ids, fgcz-h-082's production DB carries PRODUCTION ones. Measured 2026-09-24: until this
module existed the watcher's state (seeded from PRODUCTION) and the 083 test runs shared one
directory, and neither the state file nor an event said which instance an id came from — so
a TEST order could be reconciled against a PRODUCTION handled-set, and the panel listed 30
PRODUCTION orders that the 083 backend can never resolve.

A profile fixes the pair and gives it its own home under ~/.omakase/<profile>/, so the two
cannot read each other's files, and `env` is written into every state file and event so a
file that strays is refused instead of misread.

    test        B-Fabric TEST        + fgcz-h-083 :3010   may submit (the test DB)
    production  B-Fabric PRODUCTION  + fgcz-h-082 :3010   NEVER submits (phase 0: read only)

`test` is the default. Watching production is something a person asks for by name.
Shared by both, never profile-specific: ~/.omakase/audit (the history audit, evidence only)
and ~/.omakase/archive (records rescued from /tmp on 2026-09-24).
"""
from __future__ import annotations

import os
from dataclasses import dataclass
from pathlib import Path

ROOT = Path(os.environ.get("OMAKASE_ROOT", str(Path.home() / ".omakase")))
DEFAULT = "test"


@dataclass(frozen=True)
class Profile:
    name: str
    bfabric_env: str      # the bfabricPy config_file_env: "TEST" or "PRODUCTION"
    backend: str          # the SUSHI backend whose datasets carry this instance's order ids
    token_env: str        # env var (or .mcp.json key) holding that backend's bearer
    may_submit: bool      # False = this pair only reads; `run` is refused

    @property
    def home(self) -> Path:
        return ROOT / self.name

    @property
    def state_path(self) -> Path:
        return self.home / "order_watch_state.json"

    @property
    def events_dir(self) -> Path:
        return self.home / "events"

    @property
    def fixtures_dir(self) -> Path:
        return self.home / "fixtures"

    @property
    def store_path(self) -> Path:
        return self.home / "omakase.sqlite3"


PROFILES = {
    "test": Profile("test", "TEST", "http://fgcz-h-083.fgcz-net.unizh.ch:3010",
                    "NEWSUSHI_TOKEN_083", may_submit=True),
    "production": Profile("production", "PRODUCTION", "http://fgcz-h-082.fgcz-net.unizh.ch:3010",
                          "NEWSUSHI_TOKEN_082", may_submit=False),
}

HISTORY = ROOT / "audit" / "shapes_by_service_type.json"


class EnvMismatch(Exception):
    """A state file or event belongs to the other B-Fabric instance, or does not say."""


def get(name: str | None = None) -> Profile:
    """`name`, else $OMAKASE_PROFILE, else `test`. An unknown name is refused, not guessed."""
    chosen = name or os.environ.get("OMAKASE_PROFILE") or DEFAULT
    if chosen not in PROFILES:
        raise SystemExit(f"unknown OMAKASE profile {chosen!r}; one of {sorted(PROFILES)}")
    return PROFILES[chosen]


def check_env(found: str | None, prof: Profile, what: str) -> None:
    """Refuse `what` unless it records exactly this profile's B-Fabric instance.

    A missing env is refused too. Every file written before 2026-09-24 lacks one, and
    guessing which instance an order id came from is precisely the mistake this prevents.
    """
    if found is None:
        raise EnvMismatch(
            f"{what} records no B-Fabric env, so it cannot be told apart from the other "
            f"instance's ids; profile {prof.name!r} expects env {prof.bfabric_env!r}. "
            f"Files from before 2026-09-24 need `\"env\"` added by someone who knows its origin.")
    if found != prof.bfabric_env:
        raise EnvMismatch(
            f"{what} is from B-Fabric {found}, but profile {prof.name!r} pairs "
            f"B-Fabric {prof.bfabric_env} with {prof.backend}. Use --profile for the other "
            f"instance instead of mixing the two.")
