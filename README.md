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

## Requirements

- [Claude Code](https://claude.ai/claude-code) with `--dangerously-skip-permissions`
- `gh` CLI (authenticated)
- Global todos at `~/todos.md`
- Projects in `/path/to/projects/`
