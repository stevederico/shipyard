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

## Requirements

- [Claude Code](https://claude.ai/claude-code) with `--dangerously-skip-permissions`
- `gh` CLI (authenticated)
- Global todos at `~/todos.md`
- Projects in `/path/to/projects/`
