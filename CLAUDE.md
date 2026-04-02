# Shipyard

Autonomous code factory that reads tasks from `tasks.md` and ships them as PRs.

## Structure

- `factory.sh` — 12-stage factory pipeline. Deterministic stages interleaved with agentic Claude sessions.
- `tasks.md` — task queue. Self-contained, not coupled to any external todo system.
- `logs/` — timestamped logs per run (gitignored)

## Task Format

Tasks in `tasks.md`:
- `- [ ] project: description` — pending task targeting an existing project directory.
- `- [ ] description` — pending task with no project. Creates a new project (name slugified from description).
- `- [x] description (MM/DD/YY)` — completed task with date.
- First unchecked task runs next (file order).

## Factory Flow

1. Pick first `- [ ]` task from `tasks.md`
2. Route to existing project or create a new one
3. Git pull, read project's CLAUDE.md for context
4. Claude codes, tests, commits, pushes branch, opens PR
5. Deterministic lint checks: no secrets staged, changelog updated, version bumped
6. Task marked `- [x]` with date in `tasks.md`
7. Logs to `logs/{timestamp}.log`

## Factory Prompt

The Claude session enforces baseline coding standards regardless of project CLAUDE.md:
- Error handling, accessibility (WCAG 2.1 AA), API safety (exponential backoff)
- Max 50-line functions, proper naming conventions, doc comments
- Vitest tests for new code, Umami analytics on interactive elements
- Selective staging, no AI attribution, changelog + version bump
