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

    test        B-Fabric TEST        + fgcz-h-083 :3010   may submit (the test DB)       runs on fgcz-h-083
    production  B-Fabric PRODUCTION  + fgcz-h-082 :3010   submits ONLY with a separate   runs on fgcz-h-082
                                                          write credential (see below)

`test` is the default. Watching production is something a person asks for by name.
Shared by both, never profile-specific: ~/.omakase/audit (the history audit, evidence only)
and ~/.omakase/archive (records rescued from /tmp on 2026-09-24).

Production submits since 2026-09-30, and only with a WRITE credential that is not the read one.
082 grants OMAKASE an all-projects READ credential (`backend_token`), which the backend makes
read-only by construction. Writing needs a second bearer, `backend_write_token`, which exists
only while 082's operator grants it (`SUSHI_ENV_TOKEN_WRITE_*` + `SUSHI_WRITE_POLICY=submit_only`)
and whose scope names the projects that may be written. No file, no submission: the switch is
held by the person who runs 082, not by this code. `test` needs no second bearer, because its
one key already writes the test DB.

Each profile also runs on its own node only (2026-09-29, `check_host`). The home directory
is NFS-mounted on both nodes, so ~/.omakase/production/ was writable from fgcz-h-083 and
fgcz-h-082 at once, and SQLite over NFS does not survive two writers. Binding the profile
to the node that holds its backend also makes the address in the browser tell the truth:
the node you opened is the node that acts.
"""
from __future__ import annotations

import os
import socket
from dataclasses import dataclass
from pathlib import Path

DEFAULT_ROOT = Path.home() / ".omakase"
ROOT = Path(os.environ.get("OMAKASE_ROOT", str(DEFAULT_ROOT)))
DEFAULT = "test"


@dataclass(frozen=True)
class Profile:
    name: str
    bfabric_env: str      # the bfabricPy config_file_env: "TEST" or "PRODUCTION"
    backend: str          # the SUSHI backend whose datasets carry this instance's order ids
    token_env: str        # env var (or .mcp.json key) holding that backend's bearer
    may_submit: bool      # False = this pair only reads; `run` is refused
    host: str             # the only node this profile runs on (short hostname)
    # None = the read bearer also writes (test). Otherwise the env var of a SEPARATE write
    # bearer; without it (or `write_token_file`) `run` is refused.
    write_token_env: str | None = None

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

    @property
    def token_file(self) -> Path:
        """The backend bearer for this profile alone, when it must not be shared.

        Exists for production since 2026-09-25: 082 grants its all-projects read credential
        to OMAKASE only, so the bearer lives here (mode 600, never printed) instead of in
        .mcp.json, where the sushi-chain MCP — and so a hosted model — would present it too.
        """
        return self.home / "backend_token"

    @property
    def write_token_file(self) -> Path:
        """The SEPARATE write bearer, for a profile whose read bearer cannot write.

        Present only while the backend's operator grants writing (2026-09-30, production). Its
        scope - which projects may be written - is decided on the backend, not here.
        """
        return self.home / "backend_write_token"


PROFILES = {
    "test": Profile("test", "TEST", "http://fgcz-h-083.fgcz-net.unizh.ch:3010",
                    "NEWSUSHI_TOKEN_083", may_submit=True, host="fgcz-h-083"),
    "production": Profile("production", "PRODUCTION", "http://fgcz-h-082.fgcz-net.unizh.ch:3010",
                          "NEWSUSHI_TOKEN_082", may_submit=True, host="fgcz-h-082",
                          write_token_env="OMAKASE_WRITE_TOKEN_082"),
}

HISTORY = ROOT / "audit" / "shapes_by_service_type.json"


class EnvMismatch(Exception):
    """A state file or event belongs to the other B-Fabric instance, or does not say."""


class HostMismatch(Exception):
    """A profile was started on a node other than its own."""


def check_host(prof: Profile, hostname: str | None = None, root: Path | None = None) -> None:
    """Refuse to work on `prof`'s files from any node but `prof.host`.

    Only the real home is guarded. A scratch OMAKASE_ROOT (every test, a throwaway demo)
    is by construction not shared with the other node, so there is nothing to protect -
    and it holds no production token either (that lives in the real home, see token_file).
    """
    if Path(root or ROOT).resolve() != DEFAULT_ROOT.resolve():
        return
    here = (hostname or socket.gethostname()).split(".")[0]
    if here != prof.host:
        raise HostMismatch(
            f"profile {prof.name!r} runs on {prof.host} only, and this is {here}. Its files "
            f"under {prof.home} are on NFS and visible from both nodes; two nodes writing "
            f"one SQLite store corrupt it. Run this on {prof.host} instead.")


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
