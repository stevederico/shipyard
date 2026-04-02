# Shipyard

Autonomous code factory. Reads tasks from `tasks.md`, ships them as PRs.

## How It Works

1. Picks the next pending task from `tasks.md`
2. Routes to the project directory, creates a feature branch
3. Claude codes it, runs tests, commits, opens a PR
4. Marks the task done with today's date

## Setup

Shipyard expects your projects to live in the parent directory:

```
projects/
  shipyard/        # this repo
  my-app/          # a project shipyard can work on
  another-app/     # another project
```

Or set `SHIPYARD_PROJECTS` to point elsewhere:

```bash
export SHIPYARD_PROJECTS="$HOME/code"
```

## Usage

```bash
bash factory.sh              # run the factory
bash factory.sh --dry-run    # preview what it would pick
```

## Task Format

Add tasks to `tasks.md`:

```markdown
- [ ] my-app: Add dark mode toggle
- [ ] another-app: Fix pagination bug
```

The project name before the colon must match a directory in your projects folder.

## Schedule

```bash
crontab -e
0 * * * * bash /path/to/shipyard/factory.sh >> /path/to/shipyard/shipyard.log 2>&1
```

## Stages

| Stage | Type | What |
|-------|------|------|
| 1/12 PICK | deterministic | Parse `tasks.md`, take first `- [ ]` |
| 2/12 ROUTE | deterministic | Find project directory |
| 3/12 PULL | deterministic | git pull |
| 4/12 PLAN | deterministic | Read project context (CLAUDE.md, todo.md) |
| 5/12 BRANCH | deterministic | Create feature branch, save pre-state |
| 6/12 CODE | agentic | Claude implements (with coding standards in prompt) |
| 7/12 TEST | agentic | Claude runs tests (inside session) |
| 8/12 LINT | deterministic | Shell checks: no secrets, changelog, version bump |
| 9/12 FIX | agentic | Claude fixes lint failures (max 3 attempts) |
| 10/12 SHIP | deterministic | Confirm PR was opened |
| 11/12 UPDATE | deterministic | Mark task done in `tasks.md` |
| 12/12 DONE | deterministic | Report result, return to master |

## Requirements

- [Claude Code](https://claude.ai/claude-code) with `--dangerously-skip-permissions`
- `gh` CLI (authenticated)
