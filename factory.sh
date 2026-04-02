#!/bin/bash
# factory.sh — minimal code factory
# Reads next task from todos.md, lets Claude handle everything autonomously.
# Usage: bash factory.sh [--dry-run]

TODOS="$HOME/todos.md"
PROJECTS="$HOME/Desktop/projects"
LOGDIR="$HOME/Desktop/projects/shipyard/logs"
DATE=$(date +"%m/%d/%y")
TIMESTAMP=$(date +"%Y%m%d-%H%M%S")

mkdir -p "$LOGDIR"
LOGFILE="$LOGDIR/$TIMESTAMP.log"

log() { echo "[$(date +"%H:%M:%S")] $1" | tee -a "$LOGFILE"; }
stage() { echo "" | tee -a "$LOGFILE"; log "━━━ STAGE: $1 ━━━"; }

# ── 1/12 PICK ──────────────────────────────────────────────
stage "1/12 PICK"
log "Reading tasks from $TODOS"
TASK=$(awk '/^## (WIP|Tasks)$/{found=1;next} /^## /{found=0} found && /^- /{print; exit}' "$TODOS" \
  | sed 's/^- //')

if [ -z "$TASK" ]; then
  log "No tasks found"
  exit 0
fi

TASK_CLEAN=$(echo "$TASK" | sed 's/ \[[0-9]*\]//;s/ #[a-z]*//g')
log "Task: $TASK_CLEAN"

if [ "$1" = "--dry-run" ]; then
  log "Dry run — stopping before execution"
  exit 0
fi

# ── 2/12 ROUTE ─────────────────────────────────────────────
stage "2/12 ROUTE"
# Extract likely project name from task (first capitalized word or hyphenated name)
PROJECT_DIR=""
for candidate in $(echo "$TASK_CLEAN" | grep -oE '[A-Za-z][A-Za-z0-9_-]+' ); do
  match=$(find "$PROJECTS" -maxdepth 1 -iname "$candidate" -type d 2>/dev/null | head -1)
  if [ -n "$match" ]; then
    PROJECT_DIR="$match"
    break
  fi
done

if [ -z "$PROJECT_DIR" ]; then
  log "Could not find project for: $TASK_CLEAN"
  log "Available projects: $(ls "$PROJECTS" | head -20)"
  exit 1
fi

PROJECT_NAME=$(basename "$PROJECT_DIR")
log "Project: $PROJECT_NAME ($PROJECT_DIR)"

# ── 3/12 PULL ──────────────────────────────────────────────
stage "3/12 PULL"
cd "$PROJECT_DIR"
git pull origin master 2>&1 | tee -a "$LOGFILE"

# ── 4/12 PLAN ──────────────────────────────────────────────
stage "4/12 PLAN"
if [ -f "$PROJECT_DIR/todo.md" ]; then
  SUBTASK=$(awk '/^- /{print; exit}' "$PROJECT_DIR/todo.md" | sed 's/^- //')
  log "Found todo.md — subtask: $SUBTASK"
else
  SUBTASK="$TASK_CLEAN"
  log "No todo.md — using global task: $SUBTASK"
fi

if [ -f "$PROJECT_DIR/CLAUDE.md" ]; then
  log "Project CLAUDE.md found — will be loaded via --cwd"
else
  log "No project CLAUDE.md"
fi

# ── 5/12 BRANCH ───────────────────────────────────────────
stage "5/12 BRANCH"
BRANCH="factory/$(date +%Y%m%d-%H%M)"
git checkout -b "$BRANCH" 2>&1 | tee -a "$LOGFILE"
log "Branch: $BRANCH"

# Save pre-code state for lint checks
PRE_VERSION=""
if [ -f "$PROJECT_DIR/package.json" ]; then
  PRE_VERSION=$(python3 -c "import json; print(json.load(open('package.json')).get('version',''))" 2>/dev/null)
fi

# ── 6/12 CODE + 7/12 TEST (Claude session) ────────────────
stage "6/12 CODE (Claude session)"
claude -p "
You are running in factory mode. Complete this subtask autonomously.

SUBTASK: $SUBTASK
PROJECT: $PROJECT_NAME

Print a stage header before each step:
  [STAGE 6/12: CODE] what you are building
  [STAGE 7/12: TEST] running tests

Coding standards (enforce these regardless of project CLAUDE.md):
- Error handling: visible to user, human-readable messages, recovery actions, loading indicators >200ms
- Accessibility: labels or aria-label on all interactive elements, semantic HTML, WCAG 2.1 AA contrast, 44px touch targets
- API safety: exponential backoff on 429/5xx (1s>2s>4s>8s, max 3-5 retries), never loop without throttling
- Functions: max ~50 lines, single responsibility, early returns, no magic numbers
- Naming: camelCase functions, PascalCase components, UPPER_SNAKE_CASE constants, is/has/should booleans
- Imports: external > internal > relative
- Doc comments on exported/public functions (JSDoc for JS, # for Shell)
- Write tests for new code (Vitest, colocated .test.js files)
- Umami analytics: add data-umami-event on interactive elements if analytics is wired up

Steps:
1. Read todo.md if it exists for full context
2. Implement the subtask
3. Run tests if they exist (deno run test)
4. If tests fail, fix and re-run (max 3 attempts)
5. Stage only the files you modified (never git add . or git add -A)
6. Commit with a descriptive message (no AI attribution, no Co-Authored-By)
7. Update CHANGELOG.md (insert above previous, no dashes, 3 words max, present tense)
8. Bump version in package.json if it exists (minor bump)
9. Commit the version bump
10. Push the branch: git push origin $BRANCH
11. Open a PR: gh pr create --base master
12. Mark the subtask done in todo.md (remove the '- ' prefix)
13. Print FACTORY_RESULT:SUCCESS or FACTORY_RESULT:FAILED
14. Print FACTORY_REMAINING:N where N is the number of '- ' lines still in todo.md (0 if no todo.md)
" --cwd "$PROJECT_DIR" --dangerously-skip-permissions 2>&1 | tee -a "$LOGFILE"

# ── 8/12 LINT (deterministic checks) ──────────────────────
stage "8/12 LINT"
LINT_PASS=true

# Check: no .env or secrets staged
if git diff --cached --name-only 2>/dev/null | grep -qE '\.env|\.pem|\.key|credentials|secrets|tokens'; then
  log "FAIL: secrets or .env in staged files"
  LINT_PASS=false
fi

# Check: CHANGELOG.md was modified
if ! git diff "master...$BRANCH" --name-only 2>/dev/null | grep -q "CHANGELOG.md"; then
  log "WARN: CHANGELOG.md not updated"
fi

# Check: package.json version bumped
if [ -f "$PROJECT_DIR/package.json" ] && [ -n "$PRE_VERSION" ]; then
  POST_VERSION=$(python3 -c "import json; print(json.load(open('package.json')).get('version',''))" 2>/dev/null)
  if [ "$PRE_VERSION" = "$POST_VERSION" ]; then
    log "WARN: package.json version not bumped ($PRE_VERSION)"
  else
    log "OK: version $PRE_VERSION → $POST_VERSION"
  fi
fi

# Check: tests passed (look for failure indicators in log)
if grep -qE "(FAIL|ERROR|test.*failed|Tests:.*failed)" "$LOGFILE" 2>/dev/null && ! grep -q "FACTORY_RESULT:SUCCESS" "$LOGFILE"; then
  log "FAIL: tests did not pass"
  LINT_PASS=false
fi

if [ "$LINT_PASS" = true ]; then
  log "All lint checks passed"
else
  log "Lint checks failed"
fi

# ── 9/12 FIX (if lint failed, Claude fixes — max 3 attempts) ──
if [ "$LINT_PASS" = false ]; then
  stage "9/12 FIX"
  log "Skipped — lint failures were non-blocking this run"
  # TODO: re-run Claude to fix lint failures
fi

# ── 10/12 SHIP ─────────────────────────────────────────────
stage "10/12 SHIP"
if grep -q "FACTORY_RESULT:SUCCESS" "$LOGFILE" 2>/dev/null; then
  log "PR shipped on branch $BRANCH"
else
  log "No PR — Claude reported failure"
fi

# ── 11/12 UPDATE ───────────────────────────────────────────
stage "11/12 UPDATE"
if grep -q "FACTORY_RESULT:SUCCESS" "$LOGFILE" 2>/dev/null; then
  REMAINING=$(grep -o "FACTORY_REMAINING:[0-9]*" "$LOGFILE" | tail -1 | cut -d: -f2)
  log "Remaining subtasks: ${REMAINING:-unknown}"

  if [ "$REMAINING" = "0" ]; then
    log "All subtasks done — marking global task complete"
    sed -i '' "/^- $(echo "$TASK" | sed 's/[\/&]/\\&/g')$/d" "$TODOS"

    if grep -q "^## $DATE" "$TODOS"; then
      sed -i '' "/^## $DATE$/a\\
$TASK_CLEAN" "$TODOS"
    else
      sed -i '' "/^## Tasks$/i\\
## $DATE\\
$TASK_CLEAN\\
" "$TODOS"
    fi
    log "Moved task to completed: $DATE"
  else
    log "Project has $REMAINING subtasks remaining — keeping in global todos"
  fi
else
  log "Skipped — task failed"
fi

# ── 12/12 DONE ─────────────────────────────────────────────
stage "12/12 DONE"
if grep -q "FACTORY_RESULT:SUCCESS" "$LOGFILE" 2>/dev/null; then
  log "Factory run successful"
else
  log "Factory run failed — check log: $LOGFILE"
fi

# Return to master
cd "$PROJECT_DIR" && git checkout master 2>/dev/null
