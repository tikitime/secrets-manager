#!/usr/bin/env python3
"""Find 1Password secrets that are past (or near) their rotation cadence.

Reads the user's vault from secrets-manager.local.md, lists every item with
rotation metadata, computes each due date, and prints the due/overdue set as
JSON on stdout plus a human summary on stderr.

This script does NOT touch Notion. Task creation is done by the
/secrets-rotation-check command via the Notion MCP (no extra token needed), or
by notify-notion.py for headless/scheduled runs (pass --notify).

It never reads or prints secret VALUES — only item names, dates, and metadata.
"""
import argparse
import datetime
import json
import os
import re
import subprocess
import sys


def load_config(path):
    cfg = {}
    if os.path.isfile(path):
        text = open(path).read()
        m = re.search(r"^---\s*(.*?)\s*---", text, re.S | re.M)
        body = m.group(1) if m else text
        for line in body.splitlines():
            mm = re.match(r"\s*([a-z_]+):\s*(.*)", line)
            if mm:
                cfg[mm.group(1)] = mm.group(2).strip().strip('"').strip("'")
    return cfg


def op_json(args):
    r = subprocess.run(["op"] + args, capture_output=True, text=True)
    if r.returncode != 0:
        print(f"op error: {r.stderr.strip()}", file=sys.stderr)
        sys.exit(1)
    return json.loads(r.stdout) if r.stdout.strip() else None


def field(item, label):
    for f in item.get("fields", []) or []:
        if f.get("label") == label:
            return f.get("value")
    return None


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--config", default="secrets-manager.local.md")
    ap.add_argument("--warn-days", type=int, default=14,
                    help="also flag secrets due within N days (default 14)")
    ap.add_argument("--dry-run", action="store_true", help="print only; never notify")
    ap.add_argument("--notify", action="store_true",
                    help="call notify-notion.py for each due item (headless path)")
    args = ap.parse_args()

    cfg = load_config(args.config)
    vault = os.environ.get("OP_VAULT") or cfg.get("op_vault")
    if not vault:
        print("ERROR: no vault configured. Run /secrets-onboard.", file=sys.stderr)
        sys.exit(1)

    stubs = op_json(["item", "list", "--vault", vault, "--format", "json"]) or []
    today = datetime.date.today()
    due = []
    for stub in stubs:
        item = op_json(["item", "get", stub["id"], "--vault", vault, "--format", "json"])
        if not item:
            continue
        last = field(item, "last_rotated_at")
        cadence = field(item, "rotation_cadence_days")
        if not last or not cadence:
            continue  # not a managed secret
        try:
            last_d = datetime.date.fromisoformat(last)
            cad = int(cadence)
        except (ValueError, TypeError):
            continue
        if cad <= 0:
            continue  # no_rotation / reference id
        due_date = last_d + datetime.timedelta(days=cad)
        days_left = (due_date - today).days
        if days_left <= args.warn_days:
            due.append({
                "item": item.get("title"),
                "due_date": due_date.isoformat(),
                "days_left": days_left,
                "overdue": days_left < 0,
                "rotation_class": field(item, "rotation_class"),
                "runbook_url": field(item, "rotation_runbook_url"),
            })

    due.sort(key=lambda d: d["days_left"])

    if due:
        print(f"{len(due)} secret(s) due/overdue:", file=sys.stderr)
        for d in due:
            tag = "OVERDUE" if d["overdue"] else f"{d['days_left']}d"
            print(f"  [{tag}] {d['item']} (due {d['due_date']}, {d['rotation_class']})",
                  file=sys.stderr)
    else:
        print("No secrets due.", file=sys.stderr)

    print(json.dumps(due, indent=2))

    if args.notify and not args.dry_run and due:
        here = os.path.dirname(os.path.abspath(__file__))
        notifier = os.path.join(here, "notify-notion.py")
        for d in due:
            subprocess.run([sys.executable, notifier, "--config", args.config,
                            "--item", d["item"], "--due", d["due_date"]])


if __name__ == "__main__":
    main()
