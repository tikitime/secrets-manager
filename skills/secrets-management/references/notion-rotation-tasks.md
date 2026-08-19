# Rotation reminders → Notion tasks

When a secret passes its rotation cadence, this plugin files a **Notion task assigned to you** so it doesn't silently rot. This is the default notifier — no Discord, no dependency on anyone else's tooling.

## How it flows

`/secrets-rotation-check` (or the SessionStart hook's nudge, or an optional daily routine) runs `${CLAUDE_PLUGIN_ROOT}/scripts/rotation-check.py`, which:

1. Lists every item in your vault with rotation metadata.
2. Computes `due_date = last_rotated_at + rotation_cadence_days`.
3. For each item where `due_date <= today` (or within a warning window), calls `notify-notion.py`.
4. `notify-notion.py` creates one Notion task in your configured database, assigned to you, titled **"Rotate `<ITEM_NAME>` — due `<date>`"**, with the rotation steps and, if the item has a `rotation_runbook_url` set, that link in the body. (Most items leave it empty — that's fine; the task still files.)

## Idempotency (no duplicate tasks)

Before creating a task, the notifier queries the database for an **open** task whose title contains the same `<ITEM_NAME>`. If one exists, it does nothing. So re-running the check daily never piles up duplicates; it only files a task the first time a secret goes overdue (and again only after you close the prior one and it goes overdue again).

## Required database schema

The Notion database you point `notion_tasks_db` at must have at least:

| Property | Type | Used for |
|----------|------|----------|
| Title (any name) | `title` | "Rotate `<ITEM>` — due `<date>`" |
| Assignee | `people` | set to `notion_assignee` |
| Due date | `date` | the computed due date |
| Status | `status` or `select` | new tasks created as the DB's default / "To do"; idempotency checks for not-done |

`/secrets-onboard` validates the DB has these before saving config, and tells you exactly which property is missing if not. If your DB uses different property names, onboarding records the mapping in the config so the notifier targets the right ones.

## What it never does

- It never reads or includes the secret **value** — only the item name, dates, and rotation metadata.
- It never writes anything on session start. The SessionStart hook is read-only and only prints a count; task creation is always an explicit command or the scheduled routine.

## Turning it into a daily routine (optional)

`/secrets-onboard` offers to register a daily scheduled run so you get tasks without remembering to check. If you decline, just run `/secrets-rotation-check` whenever the session-start nudge tells you something's due.
