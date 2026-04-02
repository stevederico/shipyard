# Shipyard

Autonomous code factory. Reads task files from `tasks/`, ships them as PRs.

## How It Works

1. Picks the next task file from `tasks/`
2. Routes to the repo (local, GitHub, or creates a new one)
3. Claude codes it, runs tests, commits, opens a PR
4. Moves the task file to `tasks/done/`

## Setup

Shipyard expects your repos to live in the parent directory:

```
projects/
  shipyard/        # this repo
  my-app/          # a repo shipyard can work on
  another-app/     # another repo
```

If a repo isn't local, Shipyard searches your GitHub account and clones it automatically.

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

Run in its own terminal — not inside another tool. Monitor progress in a second terminal:

```bash
tail -f logs/*.log
```

Cancel anytime with `Ctrl+C` — Shipyard cleans up the branch and returns to the default branch.

## Task Format

Each task is a markdown file in `tasks/`. The filename becomes the task name. The file body is the full prompt sent to Claude — write as much or as little as you need.

**Existing repo** — add `repo:` in frontmatter:

```markdown
---
repo: my-app
---

Add a dark mode toggle to the settings page. Should respect system
preference by default. Use the existing ThemeProvider context.
```

**With screenshot verification** — add `url:` to take a screenshot after shipping and attach it to the PR:

```markdown
---
repo: my-app
url: http://localhost:5173
---

Add a dark mode toggle to the settings page.
```

**New repo** — omit `repo:` and Shipyard creates one (named from the filename):

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
2. **Task routing** — finds repo locally, clones from GitHub, or creates new
3. **Branch isolation** — agents work on feature branches, never the default branch
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
| PICK | deterministic | Take first `.md` file from `tasks/` |
| ROUTE | deterministic | Find repo locally, clone from GitHub, or create new |
| PULL | deterministic | Detect default branch, git pull |
| BRANCH | deterministic | Create feature branch, save pre-state |
| CODE | agentic | Claude implements (standards.md + workflow.md) |
| TEST | agentic | Claude runs tests (inside same session) |
| LINT | deterministic | Shell checks: no secrets, test failures |
| FIX | agentic | Claude fixes lint failures (max 3 attempts) |
| SHIP | deterministic | Confirm PR was opened |
| VERIFY | deterministic | Screenshot URL via agent-browser, attach to PR |
| UPDATE | deterministic | Move task file to `tasks/done/`, close GitHub issue |
| DONE | deterministic | Report result, return to default branch |

## Configuration

Two files control what the factory tells Claude to do:

- **`standards.md`** — coding standards (error handling, accessibility, naming, etc.)
- **`workflow.md`** — post-coding steps (commit, push, open PR, etc.)

Edit either file to match your preferences. The factory auto-detects your default branch (`main` or `master`) and new repos are created as private.

## Requirements

- [Claude Code](https://claude.ai/claude-code) with `--dangerously-skip-permissions`
- `gh` CLI (authenticated)
- `agent-browser` (optional, for screenshot verification)
