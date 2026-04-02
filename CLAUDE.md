# Shipyard

Autonomous code factory that reads tasks from `~/todos.md` and ships them as PRs.

## Structure

- `factory.sh` — 12-stage factory pipeline. Deterministic stages interleaved with agentic Claude sessions.
- `logs/` — timestamped logs per run (gitignored)

## Task Format

Tasks in todos.md:
- `- task name [N]` — incomplete. `[N]` is completion percentage (0-10), not priority.
- `task name` (no dash) under a date header = completed
- File order determines what runs next (WIP first, then Tasks)

## Factory Flow

1. Pick first incomplete task from WIP, then Tasks (file order)
2. Route to project directory in `/path/to/projects/`
3. Git pull, read project's todo.md for subtask context
4. Run Claude with `--cwd` (loads project CLAUDE.md automatically)
5. Claude codes, tests, commits, pushes branch, opens PR
6. Deterministic lint checks: no secrets staged, changelog updated, version bumped
7. Subtask marked done in project todo.md
8. Global task only marked done when ALL project subtasks complete (0 remaining)
9. Logs to `logs/{timestamp}.log`

## Factory Prompt

The Claude session enforces baseline coding standards regardless of project CLAUDE.md:
- Error handling, accessibility (WCAG 2.1 AA), API safety (exponential backoff)
- Max 50-line functions, proper naming conventions, doc comments
- Vitest tests for new code, Umami analytics on interactive elements
- Selective staging, no AI attribution, changelog + version bump
