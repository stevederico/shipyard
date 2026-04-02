# Shipyard

Autonomous code factory that reads task files from `tasks/` and ships them as PRs.

## Structure

- `factory.sh` — 12-stage factory pipeline. Deterministic stages interleaved with agentic Claude sessions.
- `tasks/` — task queue. One markdown file per task. Completed tasks move to `tasks/done/`.
- `standards.md` — coding standards injected into every Claude session. Edit to customize.
- `logs/` — timestamped logs per run (gitignored)

## Task Format

Each file in `tasks/` is a task. The filename is the task name, the body is the prompt.

- Optional `project:` in YAML frontmatter routes to an existing project directory.
- No frontmatter = new project (name slugified from filename).
- Files run in alphabetical order.

## Factory Flow

1. Pick first `.md` file from `tasks/`
2. Route to existing project or create a new one
3. Git pull, read project's CLAUDE.md for context
4. Claude codes, tests, commits, pushes branch, opens PR
5. Deterministic lint checks: no secrets staged, changelog updated, version bumped
6. Task file moved to `tasks/done/`
7. Logs to `logs/{timestamp}.log`

## Coding Standards

`standards.md` defines the baseline coding standards injected into every Claude session. Edit this file to customize what the factory enforces.
