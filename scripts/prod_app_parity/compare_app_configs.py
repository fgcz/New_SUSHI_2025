#!/usr/bin/env python3
"""Compare the INPUT surface of the allow-listed apps between two backend nodes.

Both nodes must run the SAME backend revision, otherwise this measures code drift
rather than app-source drift; the script checks that it can and warns if it cannot.

Read-only: GETs only. Exits non-zero if any app's input surface differs, so this is
usable as a check.

    python3 compare_app_configs.py [--baseline 083] [--candidate 082]

Node bearer tokens are read from the repo's .mcp.json and never printed.
"""
import argparse
import json
import os
import subprocess
import sys
import urllib.request

REPO = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
MCP_JSON = os.path.join(REPO, ".mcp.json")

NODES = {
    "083": ("http://fgcz-h-083.fgcz-net.unizh.ch:3010", "NEWSUSHI_TOKEN_083"),
    "082": ("http://fgcz-h-082.fgcz-net.unizh.ch:3010", "NEWSUSHI_TOKEN_082"),
}

# Compared fields. form_fields is compared by NAME, the rest as sets of strings.
LIST_FIELDS = ["required_columns", "required_params", "modules", "inherit_tags"]


def allowlist():
    """Read the allow-list from config/application.rb so it cannot drift from the app."""
    path = os.path.join(REPO, "backend", "config", "application.rb")
    src = open(path).read()
    start = src.find("legacy_apps_allowlist")
    if start == -1:
        raise SystemExit("could not find legacy_apps_allowlist in %s" % path)
    names = []
    for piece in src[start:start + 1200].split("'"):
        for n in piece.split(","):
            n = n.strip()
            if n and n[0].isupper() and n.isalnum():
                names.append(n)
    # native apps live in backend/lib/apps
    native = [f[:-len("App.rb")] for f in sorted(os.listdir(os.path.join(REPO, "backend", "lib", "apps")))
              if f.endswith("App.rb")]
    return sorted(set(names + native))


def token(env_var):
    cfg = json.load(open(MCP_JSON))
    return cfg["mcpServers"]["sushi-chain"]["env"][env_var]


def fetch(node, app):
    base, env_var = NODES[node]
    req = urllib.request.Request("%s/api/v1/application_configs/%s" % (base, app),
                                 headers={"Authorization": "Bearer " + token(env_var)})
    try:
        with urllib.request.urlopen(req, timeout=120) as r:
            return json.loads(r.read()).get("application")
    except Exception as e:
        return {"__error__": "%s: %s" % (type(e).__name__, e)}


def field_names(cfg):
    out = []
    for f in (cfg.get("form_fields") or []):
        out.append(f.get("name") if isinstance(f, dict) else str(f))
    return out


def as_set(cfg, key):
    vals = cfg.get(key) or []
    return {(v.get("name") if isinstance(v, dict) else str(v)) for v in vals}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--baseline", default="083", choices=sorted(NODES))
    ap.add_argument("--candidate", default="082", choices=sorted(NODES))
    args = ap.parse_args()

    try:
        rev = subprocess.check_output(["git", "-C", REPO, "rev-parse", "--short", "HEAD"],
                                      text=True).strip()
        print("local repo HEAD: %s  (verify BOTH nodes run this, or the comparison is "
              "measuring code drift)\n" % rev)
    except Exception:
        print("WARNING: could not read local HEAD; cannot warn about code drift\n")

    apps = allowlist()
    print("%-17s %-11s %-11s %s" % ("APP", args.baseline, args.candidate, "DELTA"))
    print("-" * 100)
    drifted, failed = [], []
    for a in apps:
        cb, cc = fetch(args.baseline, a), fetch(args.candidate, a)
        if not cb or "__error__" in cb or not cc or "__error__" in cc:
            print("%-17s %s" % (a, "FETCH FAILED  %s=%s  %s=%s" % (
                args.baseline, (cb or {}).get("__error__", "ok"),
                args.candidate, (cc or {}).get("__error__", "ok"))))
            failed.append(a)
            continue
        fb, fc = field_names(cb), field_names(cc)
        delta = []
        gone = [x for x in fb if x not in fc]
        added = [x for x in fc if x not in fb]
        if gone:
            delta.append("-" + ",".join(gone))
        if added:
            delta.append("+" + ",".join(added))
        for key in LIST_FIELDS:
            sb, sc = as_set(cb, key), as_set(cc, key)
            if sb != sc:
                delta.append("%s -%s +%s" % (key.upper(), sorted(sb - sc), sorted(sc - sb)))
        if cb.get("category") != cc.get("category"):
            delta.append("CATEGORY %s -> %s" % (cb.get("category"), cc.get("category")))
        print("%-17s %-11s %-11s %s" % (a, "%d fields" % len(fb), "%d fields" % len(fc),
                                        "  |  ".join(delta) if delta else "(identical)"))
        if delta:
            drifted.append(a)

    print("-" * 100)
    print("compared %d | drifted %d | fetch failed %d" % (len(apps), len(drifted), len(failed)))
    if drifted:
        print("DRIFTED ->", ", ".join(drifted))
    if failed:
        print("FAILED  ->", ", ".join(failed),
              "  (a failed `show` means the app did NOT load -- Level-1 failure)")
    return 1 if (drifted or failed) else 0


if __name__ == "__main__":
    sys.exit(main())
