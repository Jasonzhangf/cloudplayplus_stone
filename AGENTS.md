# Agent Workflow (Beads / bd)

This repo uses Beads (the `bd` CLI) to manage tasks and dependencies.

## When to use `bd`

Use `bd` whenever you:

- Start a user-visible feature/fix that will take more than a single small patch.
- Discover a new bug/regression or a new requirement during a session.
- Need to track blockers / ordering (dependencies), or want a clear audit trail.
- Need to coordinate multi-step work (e.g. host + controller + UI + tests).

Skip `bd` only for trivial one-line changes that are obviously safe.

## Hard rule (enforced process)

All **new requirements / bugs / follow-ups** must be captured in Beads
*before* implementation work starts.

Minimum required workflow:

```bash
# 1) Capture the work
bd --no-db create "Title" -p 0 --description "Repro + expected + acceptance"

# 2) Link dependencies (if any)
bd --no-db dep add <child> <parent>

# 3) Start work
bd --no-db set-state <id> in_progress

# 4) Finish work
bd --no-db close <id>
```

If a change is urgent and tiny, you may implement first, but you must create a
bead immediately after and link it to the related parent task.

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

### Shell compatibility

If your shell has aliases/wrappers that interfere with `bd` flag parsing,
prefer:

```bash
sh -lc 'bd --no-db ready'
sh -lc 'bd --no-db show <id>'
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

## Common Search Commands

Prefer `bd search` for quick full-text lookup (title/description/notes/ID).
Prefer `bd list` for exact field-level filtering.

### `bd search` (Full-Text)

```bash
bd --no-db search "keyword"
bd --no-db search "authentication bug"
bd --no-db search "cloudplayplus_stone-2"   # partial IDs work
bd --no-db search --query "performance"

# Common filters
bd --no-db search "bug" --status open
bd --no-db search "database" --label backend --limit 10
bd --no-db search "refactor" --assignee alice
bd --no-db search "security" --priority-min 0 --priority-max 2

# Time range
bd --no-db search "bug" --created-after 2025-01-01
bd --no-db search "refactor" --updated-after 2025-01-01
bd --no-db search "cleanup" --closed-before 2025-12-31

# Sorting / display
bd --no-db search "bug" --sort priority
bd --no-db search "task" --sort created --reverse
bd --no-db search "design" --long
```

Supported `--sort` fields:

- priority, created, updated, closed, status, id, title, type, assignee

### `bd list` (Field Filters)

```bash
# Status / priority / type
bd --no-db list --status open --priority 1
bd --no-db list --type bug

# Labels
bd --no-db list --label bug,critical
bd --no-db list --label-any frontend,backend

# Substring match
bd --no-db list --title-contains "auth"
bd --no-db list --desc-contains "implement"
bd --no-db list --notes-contains "TODO"

# Date ranges
bd --no-db list --created-after 2024-01-01
bd --no-db list --updated-before 2024-12-31
bd --no-db list --closed-after 2024-01-01

# Empty field filters
bd --no-db list --empty-description
bd --no-db list --no-assignee
bd --no-db list --no-labels

# Priority range
bd --no-db list --priority-min 0 --priority-max 1
bd --no-db list --priority-min 2

# Combine filters
bd --no-db list --status open --priority 1 --label-any urgent,critical --no-assignee
```
