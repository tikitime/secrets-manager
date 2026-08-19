#!/usr/bin/env python3
"""Create a Notion rotation task for one due secret. Idempotent.

This is the HEADLESS path used by the optional daily routine. The interactive
/secrets-rotation-check command prefers the Notion MCP instead, which needs no
token. This script needs a Notion integration token stored in 1Password; the
item name comes from config key `notion_token_item` (default: NOTION_TOKEN).

Never includes secret VALUES — only the item name, due date, and metadata.
"""
import argparse
import json
import os
import re
import subprocess
import sys
import urllib.request
import urllib.error

NOTION_VERSION = "2022-06-28"


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


def op_read(ref):
    r = subprocess.run(["op", "read", ref], capture_output=True, text=True)
    if r.returncode != 0:
        print(f"op read failed for {ref}: {r.stderr.strip()}", file=sys.stderr)
        sys.exit(1)
    return r.stdout.strip()


def notion(token, method, path, body=None):
    req = urllib.request.Request(
        f"https://api.notion.com/v1/{path}",
        data=json.dumps(body).encode() if body is not None else None,
        method=method,
        headers={
            "Authorization": f"Bearer {token}",
            "Notion-Version": NOTION_VERSION,
            "Content-Type": "application/json",
        },
    )
    try:
        with urllib.request.urlopen(req) as resp:
            return json.loads(resp.read())
    except urllib.error.HTTPError as e:
        print(f"Notion API error {e.code}: {e.read().decode()[:300]}", file=sys.stderr)
        sys.exit(1)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--config", default="secrets-manager.local.md")
    ap.add_argument("--item", required=True)
    ap.add_argument("--due", required=True)
    args = ap.parse_args()

    cfg = load_config(args.config)
    db = cfg.get("notion_tasks_db")
    assignee = cfg.get("notion_assignee")
    vault = os.environ.get("OP_VAULT") or cfg.get("op_vault")
    token_item = cfg.get("notion_token_item", "NOTION_TOKEN")
    if not db:
        print("ERROR: notion_tasks_db not configured.", file=sys.stderr)
        sys.exit(1)

    token = op_read(f"op://{vault}/{token_item}/credential")

    # Idempotency: skip if a task already exists whose title contains the item name.
    q = notion(token, "POST", f"databases/{db}/query", {
        "filter": {"property": _title_prop(notion(token, "GET", f"databases/{db}")),
                   "title": {"contains": args.item}},
        "page_size": 5,
    })
    if q.get("results"):
        print(f"Task already exists for {args.item}; skipping.")
        return

    schema = notion(token, "GET", f"databases/{db}")
    props_schema = schema["properties"]
    title_prop = _title_prop(schema)
    people_prop = next((k for k, v in props_schema.items() if v["type"] == "people"), None)
    date_prop = next((k for k, v in props_schema.items() if v["type"] == "date"), None)

    title = f"Rotate {args.item} — due {args.due}"
    props = {title_prop: {"title": [{"text": {"content": title}}]}}
    if people_prop and assignee:
        props[people_prop] = {"people": [{"id": assignee}]}
    if date_prop:
        props[date_prop] = {"date": {"start": args.due}}

    notion(token, "POST", "pages", {"parent": {"database_id": db}, "properties": props})
    print(f"Filed Notion task: {title}")


def _title_prop(schema):
    return next((k for k, v in schema["properties"].items() if v["type"] == "title"), "Name")


if __name__ == "__main__":
    main()
