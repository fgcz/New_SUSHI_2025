#!/usr/bin/env python3
"""2026-09-30. ONLY if the panel's Fetch DECLINED order 35755 because it is not `processed`
on B-Fabric PRODUCTION. Writes the event `watch --order` would have written, marked
HAND-MARKED, so the order can be proposed the way the 083 demo was (its TEST order was
hand-marked the same way on 2026-09-11). Run it ON 082:

    cd /srv/sushi/masa_test_new_sushi_20260527/scripts
    python3 /srv/sushi/masa_test_new_sushi_20260527/scripts/omakase_deploy/hand_mark_order_082.py 35755

Reads ONE order from B-Fabric PRODUCTION (read only; B-Fabric is not changed). Writes
~/.omakase/production/events/order_<id>.json (mode 600); never the watcher's state file.
Refuses: any project but 35611, an order that IS processed (use Fetch instead), and an
order that already has an event. The event records the order's REAL status next to the
hand-marking, so nobody later mistakes it for a detection.
"""
from __future__ import annotations

import getpass
import json
import os
import sys
import time

sys.path.insert(0, "/srv/sushi/masa_test_new_sushi_20260527/scripts")
from omakase_core import profile as P  # noqa: E402
from omakase_order_watch import watch as W  # noqa: E402

ALLOWED_PROJECT = 35611


def main() -> int:
    if len(sys.argv) != 2 or not sys.argv[1].isdigit():
        print(__doc__)
        return 2
    oid = int(sys.argv[1])
    prof = P.get("production")
    try:
        P.check_host(prof)
    except P.HostMismatch as exc:
        print(f"refused: {exc}", file=sys.stderr)
        return 2
    path = W.event_path(prof.events_dir, oid)
    if path.exists():
        print(f"refused: {path} already exists; propose from it in the panel", file=sys.stderr)
        return 2
    from bfabric import Bfabric
    client = Bfabric.connect(config_file_env=prof.bfabric_env)
    found = W.fetch_orders(client, [oid])
    if not found:
        print(f"refused: order {oid} is not in B-Fabric {prof.bfabric_env}", file=sys.stderr)
        return 2
    order = found[0]
    project = (order.get("project") or {}).get("id")
    if project != ALLOWED_PROJECT:
        print(f"refused: order {oid} is in project {project}, not {ALLOWED_PROJECT}",
              file=sys.stderr)
        return 2
    status = order.get("status")
    if status == W.TRIGGER_STATUS:
        print(f"refused: order {oid} IS {status!r} - use the panel's Fetch, it needs no marking",
              file=sys.stderr)
        return 2
    path = W.write_event(prof.events_dir, order, prof.bfabric_env, source="hand-marked")
    event = json.loads(path.read_text(encoding="utf-8"))
    event["fixture"] = (
        f"HAND-MARKED by {getpass.getuser()} on {time.strftime('%Y-%m-%d %H:%M')}, not produced "
        f"by the watcher. The order's real status on B-Fabric {prof.bfabric_env} is {status!r}, "
        f"not {W.TRIGGER_STATUS!r}. Written to run the first production chain on project "
        f"{ALLOWED_PROJECT}'s test data, the same way the fgcz-h-083 demo was run.")
    fd = os.open(path, os.O_WRONLY | os.O_TRUNC)
    with os.fdopen(fd, "w", encoding="utf-8") as fh:
        json.dump(event, fh, indent=2, sort_keys=True, default=str)
    os.chmod(path, 0o600)
    print(f"HAND-MARKED order {oid} (real status {status!r}, project {project}) -> {path}")
    print("Reload the panel: the order is listed; pick recipe and dataset, then Propose.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
