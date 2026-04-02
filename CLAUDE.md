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
4. Generate CI workflow if repo has none (`.github/workflows/ci.yml`)
5. Claude codes, tests, follows workflow.md (commit, push, PR) — output streams in real time
6. Deterministic lint checks: no secrets, test failures, changelog, version bump
7. Ship PR, watch GitHub Actions CI — fix failures (max 2 attempts)
8. Verify: start dev server + backend, Claude screenshots affected pages via agent-browser
9. Task file moved to `tasks/done/`
10. Logs to `logs/{timestamp}.log`

## Configuration

- `standards.md` — coding standards injected into every Claude session. Edit to customize.
- `workflow.md` — step-by-step instructions Claude follows after coding (commit, push, PR, etc.). Edit to customize.
