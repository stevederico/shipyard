# Shipyard

Autonomous code factory that reads tasks from `~/todos.md` and ships them as PRs.

## Structure

- `factory.sh` — the factory script. Picks a task, runs Claude in non-interactive mode, updates todos.md on success.

## Task Format

Tasks in todos.md use this format:
- `- task name [priority]` — incomplete, priority 0-9 (9 = highest)
- `task name` (no dash) under a date header = completed

## Factory Flow

1. Parse todos.md Tasks section for highest `[N]` priority
2. Pass task to `claude -p` with `--dangerously-skip-permissions`
3. Claude: find project → pull → branch → code → test → PR
4. On success: move task from Tasks to today's date section
5. Logs to `/tmp/factory-latest.log`
