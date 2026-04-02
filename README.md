# Shipyard

Autonomous code factory. Reads tasks from `todos.md`, ships them as PRs.

## How It Works

1. Picks the highest priority task from your global `todos.md`
2. Claude figures out the project, creates a feature branch, codes it, runs tests
3. Opens a PR on GitHub
4. Moves the task to today's completed section

## Usage

```bash
bash factory.sh              # run the factory
bash factory.sh --dry-run    # preview what it would pick
```

## Schedule

```bash
crontab -e
0 * * * * bash /path/to/shipyard/factory.sh >> /path/to/shipyard/shipyard.log 2>&1
```

## Factory Features

Based on patterns from Ramp Inspect and Stripe Minions:

1. **Task queue** — where work comes from (todos.md) ✓
2. **Task routing** — mapping a task to the right project/repo ✓
3. **Branch isolation** — agents work on feature branches, never master ✓
4. **Autonomous coding** — Claude runs non-interactively with full permissions ✓
5. **Test verification** — run tests, fail fast if broken ✓
6. **PR creation** — open a PR via gh CLI for every task ✓
7. **CI gate** — tests must pass before merge (iterate-pr pattern)
8. **Task completion** — update todos.md, move task to done ✓
9. **Logging** — capture what happened for debugging ✓
10. **Scheduling** — cron or trigger to run without you

## Stages

| Stage | Type | What |
|-------|------|------|
| 1/12 PICK | deterministic | Parse todos.md |
| 2/12 ROUTE | deterministic | Find project directory |
| 3/12 PULL | deterministic | git pull |
| 4/12 PLAN | deterministic | Read todo.md, select subtask |
| 5/12 BRANCH | deterministic | Create feature branch, save pre-state |
| 6/12 CODE | agentic | Claude implements (with coding standards in prompt) |
| 7/12 TEST | agentic | Claude runs tests (inside session) |
| 8/12 LINT | deterministic | Shell checks: no secrets, changelog, version bump |
| 9/12 FIX | agentic | Claude fixes lint failures (max 3 attempts) |
| 10/12 SHIP | deterministic | Confirm PR was opened |
| 11/12 UPDATE | deterministic | Update global todos.md |
| 12/12 DONE | deterministic | Report result, return to master |

## Requirements

- [Claude Code](https://claude.ai/claude-code) with `--dangerously-skip-permissions`
- `gh` CLI (authenticated)
- Global todos at `~/todos.md`
- Projects in `/path/to/projects/`
