# Shipyard

Autonomous code factory that reads task files from `tasks/` and ships them as PRs.

## Structure

- `factory.sh` — factory pipeline. Deterministic stages interleaved with agentic Claude sessions.
- `tasks/` — task queue. One markdown file per task. Completed tasks move to `tasks/done/`.
- `standards.md` — coding standards injected into every Claude session.
- `workflow.md` — post-coding steps (commit, push, PR). Edit to customize.
- `logs/` — timestamped logs per run (gitignored)

## Task Format

Each file in `tasks/` is a task. The filename is the task name, the body is the prompt.

- Optional `repo:` in YAML frontmatter routes to an existing repo (local or GitHub).
- No frontmatter = new repo (name slugified from filename).
- Files run in alphabetical order.

## Factory Flow

1. Pick first `.md` file from `tasks/`
2. Route to repo (local → GitHub clone → create new)
3. Detect default branch (`main`/`master`), git pull
4. Claude codes, tests, follows workflow.md (commit, push, PR)
5. Deterministic lint checks: no secrets, test failures
6. Task file moved to `tasks/done/`
7. Logs to `logs/{timestamp}.log`

## Configuration

- `standards.md` — coding standards injected into every Claude session. Edit to customize.
- `workflow.md` — step-by-step instructions Claude follows after coding (commit, push, PR, etc.). Edit to customize.
