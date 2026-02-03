# Agent Workflow (Beads / bd)

This repo uses Beads (the `bd` CLI) to manage tasks and dependencies.

## When to use `bd`

Use `bd` whenever you:

- Start a user-visible feature/fix that will take more than a single small patch.
- Discover a new bug/regression or a new requirement during a session.
- Need to track blockers / ordering (dependencies), or want a clear audit trail.
- Need to coordinate multi-step work (e.g. host + controller + UI + tests).

Skip `bd` only for trivial one-line changes that are obviously safe.

## Stealth local workflow (recommended)

Default to "stealth" mode so beads files never get committed to the main repo.

Initialize once per machine:

```bash
bd init --stealth --no-db
```

- `--stealth` configures `.git/info/exclude` so `.beads/` is not committed.
- `--no-db` stores issues in `.beads/issues.jsonl` (no SQLite DB).

All commands in this repo should be run with `--no-db`:

```bash
bd --no-db ready
bd --no-db create "Title" -p 0 --description "Context + acceptance"
bd --no-db dep add <child> <parent>
bd --no-db show <id>
bd --no-db set-state <id> in_progress
bd --no-db close <id>
```

## Conventions

- Prefer one P0 "current focus" task at a time; everything else depends on it.
- Model dependencies explicitly with `bd dep add`.
- Keep issue descriptions short but concrete: repro steps + expected behavior.

## Quick checks

- Show ready work:
  - `bd --no-db ready`
- Show blocked work:
  - `bd --no-db blocked`
- Show a task:
  - `bd --no-db show <id>`

