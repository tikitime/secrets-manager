---
name: secrets-rotation-check
description: Find secrets past their rotation cadence and file a Notion task (assigned to you) for each. Idempotent — won't duplicate an open task for the same secret. Run on demand, or let the optional daily routine / SessionStart nudge prompt you.
---

# /secrets-rotation-check

Find overdue secrets and file Notion rotation tasks. Invoke the `secrets-management` skill first. Load config from `secrets-manager.local.md`; if missing, run `/secrets-onboard`.

## Run the check

```bash
python3 "${CLAUDE_PLUGIN_ROOT}/scripts/rotation-check.py" --config secrets-manager.local.md
```

The script:
1. Lists every item in `$OP_VAULT` with rotation metadata.
2. Computes `due_date = last_rotated_at + rotation_cadence_days`.
3. For each item due (or within the warning window), creates a Notion task in `notion_tasks_db` assigned to `notion_assignee`, titled "Rotate `<ITEM>` — due `<date>`" — **skipping any item that already has an open task** (idempotent).

Pass `--dry-run` to list what WOULD be filed without writing to Notion. Use this first if the user wants to preview.

## Report

Summarize what came back: how many secrets are due, which ones, and which got a fresh Notion task vs. already had one open. Offer to start `/secrets-rotate` on the most urgent (e.g. anything `prod-phi-payment` or already `leaked_*`).

## Notes

- This command WRITES to Notion (creates tasks). The SessionStart hook never does — it only counts and nudges.
- The script never reads or prints secret values — only names, dates, and rotation metadata.
- If the user wants this automatic, suggest the daily routine set up in `/secrets-onboard`.
