# Shipyard

Autonomous code factory that reads task files from `tasks/` and ships them as PRs.

## Structure

- `factory.sh` — 12-stage factory pipeline. Deterministic stages interleaved with agentic Claude sessions.
- `tasks/` — task queue. One markdown file per task. Completed tasks move to `tasks/done/`.
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

## Factory Prompt

The Claude session enforces baseline coding standards regardless of project CLAUDE.md:
- Error handling, accessibility (WCAG 2.1 AA), API safety (exponential backoff)
- Max 50-line functions, proper naming conventions, doc comments
- Vitest tests for new code, Umami analytics on interactive elements
- Selective staging, no AI attribution, changelog + version bump
