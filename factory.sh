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
        f.write(f'---\nrepo: {project}\nissue: {repo}#{num}\n---\n\n# {title}\n\n{body}\n')

    print(f'  Created {filename}')

if not issues:
    print('  No issues with label \"shipyard\" found')
"
  exit 0
fi

# ── 1/12 PICK ──────────────────────────────────────────────
stage "PICK"
log "Reading tasks from $TASK_DIR"

TASK_FILE=$(find "$TASK_DIR" -maxdepth 1 -name '*.md' -type f 2>/dev/null | sort | head -1)

if [ -z "$TASK_FILE" ]; then
  log "No pending tasks"
  exit 0
fi

TASK_NAME=$(basename "$TASK_FILE" .md)
TASK_BODY=$(cat "$TASK_FILE")

# Parse optional frontmatter for repo field
TASK_REPO=""
IS_NEW_REPO=false
if echo "$TASK_BODY" | head -1 | grep -q '^---$'; then
  TASK_REPO=$(echo "$TASK_BODY" | awk '/^---$/{n++;next} n==1 && /^repo:/{gsub(/^repo: */, ""); print}')
  TASK_PROMPT=$(echo "$TASK_BODY" | awk 'BEGIN{n=0} /^---$/{n++;next} n>=2{print}')
else
  TASK_PROMPT="$TASK_BODY"
fi

log "Task: $TASK_NAME"
log "Repo: ${TASK_REPO:-(new repo)}"

if [ "$1" = "--dry-run" ]; then
  log "Dry run — stopping before execution"
  log "Prompt preview:"
  echo "$TASK_PROMPT" | head -5 | tee -a "$LOGFILE"
  exit 0
fi

# ── 2/12 ROUTE ─────────────────────────────────────────────
stage "ROUTE"

if [ -n "$TASK_REPO" ]; then
  # 1. Check local directory
  REPO_DIR=$(find "$PROJECTS" -maxdepth 1 -iname "$TASK_REPO" -type d 2>/dev/null | head -1)

  # 2. Not local — try cloning from GitHub (if gh is available)
  if [ -z "$REPO_DIR" ] && command -v gh &>/dev/null; then
    log "Not found locally, searching GitHub..."
    GH_REPO=$(gh repo list --limit 500 --json name,nameWithOwner 2>/dev/null | \
      python3 -c "import json,sys; repos=json.loads(sys.stdin.read()); matches=[r for r in repos if r['name'].lower()=='$TASK_REPO'.lower()]; print(matches[0]['nameWithOwner'] if matches else '')" 2>/dev/null)

    if [ -n "$GH_REPO" ]; then
      log "Found on GitHub: $GH_REPO — cloning"
      gh repo clone "$GH_REPO" "$PROJECTS/$TASK_REPO" 2>&1 | tee -a "$LOGFILE"
      REPO_DIR="$PROJECTS/$TASK_REPO"
    fi
  fi

  # 3. Not found anywhere — error
  if [ -z "$REPO_DIR" ]; then
    log "Could not find repo '$TASK_REPO' locally or on GitHub"
    exit 1
  fi
else
  # No repo specified — create new
  REPO_NAME=$(echo "$TASK_NAME" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9-]/-/g' | sed 's/--*/-/g' | sed 's/^-//;s/-$//')
  REPO_DIR="$PROJECTS/$REPO_NAME"
  mkdir -p "$REPO_DIR"
  cd "$REPO_DIR" && git init 2>&1 | tee -a "$LOGFILE"
  IS_NEW_REPO=true
  log "Created new repo: $REPO_NAME ($REPO_DIR)"
fi

REPO_NAME=$(basename "$REPO_DIR")
log "Repo: $REPO_NAME ($REPO_DIR)"

# ── 3/12 PULL ──────────────────────────────────────────────
stage "PULL"
cd "$REPO_DIR"
if [ "$IS_NEW_REPO" = false ]; then
  HAS_REMOTE=$(git remote 2>/dev/null | head -1)
  if [ -n "$HAS_REMOTE" ]; then
    # Detect default branch
    BASE_BRANCH=$(git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's@^refs/remotes/origin/@@')
    if [ -z "$BASE_BRANCH" ]; then
      BASE_BRANCH=$(git branch -r 2>/dev/null | grep -oE 'origin/(main|master)' | head -1 | sed 's@origin/@@')
    fi
    BASE_BRANCH="${BASE_BRANCH:-main}"
    log "Base branch: $BASE_BRANCH"
    git pull origin "$BASE_BRANCH" 2>&1 | tee -a "$LOGFILE"
  else
    BASE_BRANCH=$(git branch --show-current 2>/dev/null || echo "main")
    log "No remote — skipping pull (branch: $BASE_BRANCH)"
  fi
else
  BASE_BRANCH="main"
  log "New repo — skipping pull"
fi

# ── BRANCH ────────────────────────────────────────────────
stage "BRANCH"
BRANCH="factory/$TASK_NAME"
if [ "$IS_NEW_REPO" = false ]; then
  git checkout -b "$BRANCH" 2>&1 | tee -a "$LOGFILE"
else
  log "New repo — working on default branch"
fi
log "Branch: $BRANCH"

# Save pre-code state for lint checks
PRE_VERSION=""
if [ -f "$REPO_DIR/package.json" ]; then
  PRE_VERSION=$(python3 -c "import json; print(json.load(open('package.json')).get('version',''))" 2>/dev/null)
fi

# ── CODE + TEST (Claude session) ──────────────────────────
stage "CODE"
claude -p "
You are running in factory mode. Complete this task autonomously.

REPO: $REPO_NAME
NEW_REPO: $IS_NEW_REPO

--- TASK ---
$TASK_PROMPT
--- END TASK ---

Print a stage header before each step:
  [CODE] what you are building
  [TEST] running tests

Coding standards (enforce these regardless of project CLAUDE.md):
$(cat "$SHIPYARD/standards.md")

Workflow (BRANCH=$BRANCH, BASE_BRANCH=$BASE_BRANCH):
$(cat "$SHIPYARD/workflow.md")
" --dangerously-skip-permissions 2>&1 | tee -a "$LOGFILE"

# ── LINT (deterministic checks) ───────────────────────────
stage "LINT"
LINT_PASS=true

# Check: no .env or secrets committed on branch
if git diff "$BASE_BRANCH...$BRANCH" --name-only 2>/dev/null | grep -qE '\.env|\.pem|\.key|credentials|secrets|tokens'; then
  log "FAIL: secrets or .env in committed files"
  LINT_PASS=false
fi

# Check: changelog was modified
if ! git diff "$BASE_BRANCH...$BRANCH" --name-only 2>/dev/null | grep -qi "changelog"; then
  log "WARN: CHANGELOG.md not updated"
fi

# Check: package.json version bumped
if [ -f "$REPO_DIR/package.json" ] && [ -n "$PRE_VERSION" ]; then
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

# ── FIX (if lint failed, Claude fixes — max 3 attempts) ──
if [ "$LINT_PASS" = false ]; then
  stage "FIX"
  log "Skipped — lint failures were non-blocking this run"
  # TODO: re-run Claude to fix lint failures
fi

# ── SHIP ──────────────────────────────────────────────────
stage "SHIP"
if grep -q "FACTORY_RESULT:SUCCESS" "$LOGFILE" 2>/dev/null; then
  log "PR shipped on branch $BRANCH"
else
  log "No PR — Claude reported failure"
fi

# ── UPDATE ────────────────────────────────────────────────
stage "UPDATE"
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

# ── DONE ──────────────────────────────────────────────────
stage "DONE"
if grep -q "FACTORY_RESULT:SUCCESS" "$LOGFILE" 2>/dev/null; then
  log "Factory run successful"
else
  log "Factory run failed — check log: $LOGFILE"
fi

# Return to default branch (skip for new repos)
if [ "$IS_NEW_REPO" = false ]; then
  cd "$REPO_DIR" && git checkout "$BASE_BRANCH" 2>/dev/null
fi
