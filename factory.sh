#!/bin/bash
# factory.sh — minimal code factory
# Reads next task from tasks.md, lets Claude handle everything autonomously.
# Usage: bash factory.sh [--dry-run]

SHIPYARD="${SHIPYARD_DIR:-$(cd "$(dirname "$0")" && pwd)}"
TASKS="$SHIPYARD/tasks.md"
PROJECTS="${SHIPYARD_PROJECTS:-$(dirname "$SHIPYARD")}"
LOGDIR="$SHIPYARD/logs"
DATE=$(date +"%m/%d/%y")
TIMESTAMP=$(date +"%Y%m%d-%H%M%S")

mkdir -p "$LOGDIR"
LOGFILE="$LOGDIR/$TIMESTAMP.log"

log() { echo "[$(date +"%H:%M:%S")] $1" | tee -a "$LOGFILE"; }
stage() { echo "" | tee -a "$LOGFILE"; log "━━━ STAGE: $1 ━━━"; }

# ── 1/12 PICK ──────────────────────────────────────────────
stage "1/12 PICK"
log "Reading tasks from $TASKS"

if [ ! -f "$TASKS" ]; then
  log "No tasks.md found at $TASKS"
  exit 0
fi

# First unchecked task: "- [ ] project: description" or "- [ ] description"
TASK_LINE=$(grep -n '^\- \[ \] ' "$TASKS" | head -1)

if [ -z "$TASK_LINE" ]; then
  log "No pending tasks"
  exit 0
fi

TASK_LINENUM=$(echo "$TASK_LINE" | cut -d: -f1)
TASK_RAW=$(echo "$TASK_LINE" | cut -d: -f2- | sed 's/^- \[ \] //')

# Parse format: "project: description" or just "description"
if echo "$TASK_RAW" | grep -q ':'; then
  TASK_PROJECT=$(echo "$TASK_RAW" | cut -d: -f1 | xargs)
  TASK_DESC=$(echo "$TASK_RAW" | cut -d: -f2- | xargs)
else
  TASK_PROJECT=""
  TASK_DESC=$(echo "$TASK_RAW" | xargs)
fi
log "Task: ${TASK_PROJECT:-(new project)} — $TASK_DESC"

if [ "$1" = "--dry-run" ]; then
  log "Dry run — stopping before execution"
  exit 0
fi

# ── 2/12 ROUTE ─────────────────────────────────────────────
stage "2/12 ROUTE"
IS_NEW_PROJECT=false

if [ -n "$TASK_PROJECT" ]; then
  PROJECT_DIR=$(find "$PROJECTS" -maxdepth 1 -iname "$TASK_PROJECT" -type d 2>/dev/null | head -1)
  if [ -z "$PROJECT_DIR" ]; then
    log "Could not find project: $TASK_PROJECT"
    log "Available projects: $(ls "$PROJECTS" | head -20)"
    exit 1
  fi
else
  # Slugify description into a project name
  PROJECT_NAME=$(echo "$TASK_DESC" | tr '[:upper:]' '[:lower:]' \
    | sed 's/[^a-z0-9 ]//g' \
    | sed 's/^add //' | sed 's/^create //' | sed 's/^build //' | sed 's/^make //' \
    | sed 's/^a //' | sed 's/^an //' | sed 's/^the //' \
    | xargs | tr ' ' '-')
  PROJECT_DIR="$PROJECTS/$PROJECT_NAME"
  mkdir -p "$PROJECT_DIR"
  cd "$PROJECT_DIR" && git init 2>&1 | tee -a "$LOGFILE"
  IS_NEW_PROJECT=true
  log "Created new project: $PROJECT_NAME ($PROJECT_DIR)"
fi

PROJECT_NAME=$(basename "$PROJECT_DIR")
log "Project: $PROJECT_NAME ($PROJECT_DIR)"

# ── 3/12 PULL ──────────────────────────────────────────────
stage "3/12 PULL"
cd "$PROJECT_DIR"
if [ "$IS_NEW_PROJECT" = false ]; then
  git pull origin master 2>&1 | tee -a "$LOGFILE"
else
  log "New project — skipping pull"
fi

# ── 4/12 PLAN ──────────────────────────────────────────────
stage "4/12 PLAN"
SUBTASK="$TASK_DESC"
if [ -f "$PROJECT_DIR/CLAUDE.md" ]; then
  log "Project CLAUDE.md found — will be loaded from working directory"
else
  log "No project CLAUDE.md"
fi

# ── 5/12 BRANCH ───────────────────────────────────────────
stage "5/12 BRANCH"
BRANCH="factory/$(date +%Y%m%d-%H%M)"
if [ "$IS_NEW_PROJECT" = false ]; then
  git checkout -b "$BRANCH" 2>&1 | tee -a "$LOGFILE"
else
  log "New project — working on default branch"
fi
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
NEW_PROJECT: $IS_NEW_PROJECT

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
1. If NEW_PROJECT is true, scaffold the project from scratch (create README, package.json, etc.)
2. Implement the subtask
3. Run tests if they exist (deno run test)
4. If tests fail, fix and re-run (max 3 attempts)
5. Stage only the files you modified (never git add . or git add -A)
6. Commit with a descriptive message (no AI attribution, no Co-Authored-By)
7. Update CHANGELOG.md (insert above previous, no dashes, 3 words max, present tense)
8. Bump version in package.json if it exists (minor bump)
9. Commit the version bump
10. If NEW_PROJECT is true, create a GitHub repo: gh repo create PROJECT --public --source=. --push
11. Push the branch: git push origin $BRANCH
12. If NEW_PROJECT is false, open a PR: gh pr create --base master
13. Print FACTORY_RESULT:SUCCESS or FACTORY_RESULT:FAILED
" --dangerously-skip-permissions 2>&1 | tee -a "$LOGFILE"

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
  # Mark task done: "- [ ]" → "- [x]" with date
  sed -i '' "${TASK_LINENUM}s/- \[ \]/- [x]/" "$TASKS"
  sed -i '' "${TASK_LINENUM}s/$/ ($DATE)/" "$TASKS"
  log "Marked done: $TASK_PROJECT — $TASK_DESC"

  REMAINING=$(grep -c '^\- \[ \] ' "$TASKS" 2>/dev/null || echo 0)
  log "Remaining tasks: $REMAINING"
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

# Return to master (skip for new projects)
if [ "$IS_NEW_PROJECT" = false ]; then
  cd "$PROJECT_DIR" && git checkout master 2>/dev/null
fi
