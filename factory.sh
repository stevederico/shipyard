#!/bin/bash
# factory.sh — minimal code factory
# Reads next task file from tasks/, lets Claude handle everything autonomously.
# Usage: bash factory.sh [--dry-run] [--issues owner/repo]

SHIPYARD="${SHIPYARD_DIR:-$(cd "$(dirname "$0")" && pwd)}"
TASK_DIR="$SHIPYARD/tasks"
DONE_DIR="$TASK_DIR/done"
PROJECTS="${SHIPYARD_PROJECTS:-$(dirname "$SHIPYARD")}"
LOGDIR="$SHIPYARD/logs"
TIMESTAMP=$(date +"%Y%m%d-%H%M%S")

mkdir -p "$LOGDIR" "$DONE_DIR"
LOGFILE="$LOGDIR/$TIMESTAMP.log"

log() { echo "[$(date +"%H:%M:%S")] $1" | tee -a "$LOGFILE"; }
stage() { echo "" | tee -a "$LOGFILE"; log "━━━ STAGE: $1 ━━━"; }

# ── ISSUES: pull GitHub issues into tasks/ ─────────────────
if [ "$1" = "--issues" ]; then
  REPO="$2"
  if [ -z "$REPO" ]; then
    echo "Usage: bash factory.sh --issues owner/repo"
    exit 1
  fi

  log "Syncing issues from $REPO (label: shipyard)"
  export PROJECT_NAME=$(echo "$REPO" | cut -d/ -f2)
  export REPO TASK_DIR

  gh issue list --repo "$REPO" --label "shipyard" --state open --json number,title,body --limit 50 2>/dev/null | \
    python3 -c "
import json, sys, re, os

task_dir = os.environ['TASK_DIR']
project = os.environ['PROJECT_NAME']
repo = os.environ['REPO']

issues = json.loads(sys.stdin.read())
for issue in issues:
    num = issue['number']
    title = issue['title']
    body = issue.get('body', '') or ''
    slug = re.sub(r'[^a-z0-9]+', '-', title.lower()).strip('-')
    filename = os.path.join(task_dir, f'{num:03d}-{slug}.md')

    with open(filename, 'w') as f:
        f.write(f'---\nproject: {project}\nissue: {repo}#{num}\n---\n\n# {title}\n\n{body}\n')

    print(f'  Created {filename}')

if not issues:
    print('  No issues with label \"shipyard\" found')
"
  exit 0
fi

# ── 1/12 PICK ──────────────────────────────────────────────
stage "1/12 PICK"
log "Reading tasks from $TASK_DIR"

TASK_FILE=$(find "$TASK_DIR" -maxdepth 1 -name '*.md' -type f 2>/dev/null | sort | head -1)

if [ -z "$TASK_FILE" ]; then
  log "No pending tasks"
  exit 0
fi

TASK_NAME=$(basename "$TASK_FILE" .md)
TASK_BODY=$(cat "$TASK_FILE")

# Parse optional frontmatter for project field
TASK_PROJECT=""
IS_NEW_PROJECT=false
if echo "$TASK_BODY" | head -1 | grep -q '^---$'; then
  TASK_PROJECT=$(echo "$TASK_BODY" | awk '/^---$/{n++;next} n==1 && /^project:/{gsub(/^project: */, ""); print}')
  TASK_PROMPT=$(echo "$TASK_BODY" | awk 'BEGIN{n=0} /^---$/{n++;next} n>=2{print}')
else
  TASK_PROMPT="$TASK_BODY"
fi

log "Task: $TASK_NAME"
log "Project: ${TASK_PROJECT:-(new project)}"

if [ "$1" = "--dry-run" ]; then
  log "Dry run — stopping before execution"
  log "Prompt preview:"
  echo "$TASK_PROMPT" | head -5 | tee -a "$LOGFILE"
  exit 0
fi

# ── 2/12 ROUTE ─────────────────────────────────────────────
stage "2/12 ROUTE"

if [ -n "$TASK_PROJECT" ]; then
  PROJECT_DIR=$(find "$PROJECTS" -maxdepth 1 -iname "$TASK_PROJECT" -type d 2>/dev/null | head -1)
  if [ -z "$PROJECT_DIR" ]; then
    log "Could not find project: $TASK_PROJECT"
    log "Available projects: $(ls "$PROJECTS" | head -20)"
    exit 1
  fi
else
  # Slugify task name into a project name
  PROJECT_NAME=$(echo "$TASK_NAME" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9-]/-/g' | sed 's/--*/-/g' | sed 's/^-//;s/-$//')
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

# ── 5/12 BRANCH ───────────────────────────────────────────
stage "5/12 BRANCH"
BRANCH="factory/$TASK_NAME"
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
You are running in factory mode. Complete this task autonomously.

PROJECT: $PROJECT_NAME
NEW_PROJECT: $IS_NEW_PROJECT

--- TASK ---
$TASK_PROMPT
--- END TASK ---

Print a stage header before each step:
  [STAGE 6/12: CODE] what you are building
  [STAGE 7/12: TEST] running tests

Coding standards (enforce these regardless of project CLAUDE.md):
$(cat "$SHIPYARD/standards.md")

Steps:
1. If NEW_PROJECT is true, scaffold the project from scratch (create README, package.json, etc.)
2. Implement the task
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

# Check: no .env or secrets committed on branch
if git diff "master...$BRANCH" --name-only 2>/dev/null | grep -qE '\.env|\.pem|\.key|credentials|secrets|tokens'; then
  log "FAIL: secrets or .env in committed files"
  LINT_PASS=false
fi

# Check: changelog was modified
if ! git diff "master...$BRANCH" --name-only 2>/dev/null | grep -qi "changelog"; then
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
  # If task came from a GitHub issue, comment the PR link and close it
  ISSUE_REF=$(echo "$TASK_BODY" | sed -n '/^---$/,/^---$/p' | grep '^issue:' | sed 's/^issue: *//')
  if [ -n "$ISSUE_REF" ]; then
    ISSUE_REPO=$(echo "$ISSUE_REF" | cut -d'#' -f1)
    ISSUE_NUM=$(echo "$ISSUE_REF" | cut -d'#' -f2)
    PR_URL=$(grep -o 'https://github.com/[^ ]*pull/[0-9]*' "$LOGFILE" | tail -1)
    gh issue comment "$ISSUE_NUM" --repo "$ISSUE_REPO" --body "Shipped in ${PR_URL:-branch $BRANCH}" 2>&1 | tee -a "$LOGFILE"
    gh issue close "$ISSUE_NUM" --repo "$ISSUE_REPO" 2>&1 | tee -a "$LOGFILE"
    log "Closed issue: $ISSUE_REF"
  fi

  mv "$TASK_FILE" "$DONE_DIR/$(basename "$TASK_FILE")"
  log "Moved to done: $TASK_NAME"

  REMAINING=$(find "$TASK_DIR" -maxdepth 1 -name '*.md' -type f 2>/dev/null | wc -l | xargs)
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
