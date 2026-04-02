# Shipyard

Autonomous code factory. Reads task files from `tasks/`, ships them as PRs.

## How It Works

1. Picks the next task file from `tasks/`
2. Routes to the project directory (or creates a new one)
3. Claude codes it, runs tests, commits, opens a PR
4. Moves the task file to `tasks/done/`

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
bash factory.sh                        # run the factory
bash factory.sh --dry-run              # preview what it would pick
bash factory.sh --issues owner/repo    # pull GitHub issues into tasks/
```

## Task Format

Each task is a markdown file in `tasks/`. The filename becomes the task name. The file body is the full prompt sent to Claude — write as much or as little as you need.

**Existing project** — add `project:` in frontmatter:

```markdown
---
project: my-app
---

Add a dark mode toggle to the settings page. Should respect system
preference by default. Use the existing ThemeProvider context.
```

**New project** — omit `project:` and Shipyard creates one (named from the filename):

```markdown
Build a weather dashboard that shows 5-day forecast.
Use OpenWeatherMap API. Include a search bar for city lookup.
```

Tasks run in alphabetical order by filename. Prefix with numbers to control priority:

```
tasks/
  01-fix-auth.md           ← runs first
  02-add-dashboard.md
  03-refactor-api.md
```

Completed tasks move to `tasks/done/`.

## GitHub Issues

Pull issues from any repo into your task queue:

```bash
bash factory.sh --issues owner/repo
```

This fetches open issues labeled `shipyard` and creates task files from them. After the factory completes a task, it comments the PR link on the issue and closes it.

## Schedule

```bash
crontab -e
0 * * * * bash /path/to/shipyard/factory.sh >> /path/to/shipyard/shipyard.log 2>&1
```

## Factory Features

Based on patterns from Ramp Inspect and Stripe Minions:

1. **Task queue** — `tasks/` folder, one markdown file per task
2. **Task routing** — maps to existing project or creates a new one
3. **Branch isolation** — agents work on feature branches, never master
4. **Autonomous coding** — Claude runs non-interactively with full permissions
5. **Test verification** — run tests, fail fast if broken
6. **PR creation** — open a PR via `gh` CLI for every task
7. **CI gate** — tests must pass before merge (iterate-pr pattern)
8. **Task completion** — move task file to `tasks/done/`
9. **Logging** — timestamped logs per run for debugging
10. **Scheduling** — cron or trigger to run without you

## Stages

| Stage | Type | What |
|-------|------|------|
| 1/12 PICK | deterministic | Take first `.md` file from `tasks/` |
| 2/12 ROUTE | deterministic | Find project directory or create new one |
| 3/12 PULL | deterministic | git pull |
| 4/12 PLAN | deterministic | Read project context (CLAUDE.md) |
| 5/12 BRANCH | deterministic | Create feature branch, save pre-state |
| 6/12 CODE | agentic | Claude implements (with coding standards in prompt) |
| 7/12 TEST | agentic | Claude runs tests (inside session) |
| 8/12 LINT | deterministic | Shell checks: no secrets, changelog, version bump |
| 9/12 FIX | agentic | Claude fixes lint failures (max 3 attempts) |
| 10/12 SHIP | deterministic | Confirm PR was opened |
| 11/12 UPDATE | deterministic | Move task file to `tasks/done/` |
| 12/12 DONE | deterministic | Report result, return to master |

## Coding Standards

`standards.md` defines the baseline rules injected into every Claude session (error handling, accessibility, naming, etc.). Edit it to match your preferences.

## Requirements

- [Claude Code](https://claude.ai/claude-code) with `--dangerously-skip-permissions`
- `gh` CLI (authenticated)
