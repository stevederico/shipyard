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

# ── Ctrl+C cleanup ────────────────────────────────────────
cleanup() {
  echo "" | tee -a "$LOGFILE"
  log "━━━ CANCELLED ━━━"
  if [ -n "$REPO_DIR" ] && [ -n "$BASE_BRANCH" ] && [ "$IS_NEW_REPO" = false ]; then
    cd "$REPO_DIR" && git checkout "$BASE_BRANCH" 2>/dev/null
    log "Returned to $BASE_BRANCH"
  fi
  exit 130
}
trap cleanup INT

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

DRY_RUN=false
if [ "$1" = "--dry-run" ]; then
  DRY_RUN=true
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
      if [ "$DRY_RUN" = true ]; then
        log "Found on GitHub: $GH_REPO (would clone)"
        REPO_DIR="$PROJECTS/$TASK_REPO"
      else
        log "Found on GitHub: $GH_REPO — cloning"
        gh repo clone "$GH_REPO" "$PROJECTS/$TASK_REPO" 2>&1 | tee -a "$LOGFILE"
        REPO_DIR="$PROJECTS/$TASK_REPO"
      fi
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
  if [ "$DRY_RUN" = true ]; then
    IS_NEW_REPO=true
    log "Would create new repo: $REPO_NAME ($REPO_DIR)"
  else
    mkdir -p "$REPO_DIR"
    cd "$REPO_DIR" && git init 2>&1 | tee -a "$LOGFILE"
    IS_NEW_REPO=true
    log "Created new repo: $REPO_NAME ($REPO_DIR)"
  fi
fi

REPO_NAME=$(basename "$REPO_DIR")
log "Repo: $REPO_NAME ($REPO_DIR)"

# ── 3/12 PULL ──────────────────────────────────────────────
stage "PULL"
cd "$REPO_DIR" 2>/dev/null
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
    if [ "$DRY_RUN" = false ]; then
      git pull origin "$BASE_BRANCH" 2>&1 | tee -a "$LOGFILE"
    fi
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
BRANCH="shipyard/$TASK_NAME"
if [ "$IS_NEW_REPO" = false ] && [ "$DRY_RUN" = false ]; then
  git branch -D "$BRANCH" 2>/dev/null
  git checkout -b "$BRANCH" 2>&1 | tee -a "$LOGFILE"
fi
log "Branch: $BRANCH"

# Save pre-code state for lint checks
PRE_VERSION=""
if [ -f "$REPO_DIR/package.json" ]; then
  PRE_VERSION=$(python3 -c "import json; print(json.load(open('package.json')).get('version',''))" 2>/dev/null)
fi

# ── Dry run summary ───────────────────────────────────────
if [ "$DRY_RUN" = true ]; then
  echo "" | tee -a "$LOGFILE"
  log "━━━ DRY RUN SUMMARY ━━━"
  log "Task:       $TASK_NAME"
  log "Repo:       ${TASK_REPO:-(new repo)} → $REPO_DIR"
  log "New repo:   $IS_NEW_REPO"
  log "Branch:     $BRANCH"
  log "Base:       $BASE_BRANCH"
  log "Verify:     $(command -v agent-browser &>/dev/null && echo 'agent-browser available' || echo 'agent-browser not installed — skip')"
  log "Standards:  $SHIPYARD/standards.md"
  log "Workflow:   $SHIPYARD/workflow.md"
  log ""
  log "━━━ PROMPT ━━━"
  echo "$TASK_PROMPT" | tee -a "$LOGFILE"
  exit 0
fi

# ── CODE + TEST (Claude session) ──────────────────────────
stage "CODE"
log "Ctrl+C to cancel. Monitor: tail -f $LOGFILE"
CODE_START=$(date +%s)

# Write prompt to temp file to avoid quoting issues with script
PROMPT_FILE=$(mktemp)
cat > "$PROMPT_FILE" <<PROMPT_EOF
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
PROMPT_EOF

# Stream Claude output in real time via stream-json
claude -p "$(cat "$PROMPT_FILE")" --dangerously-skip-permissions --verbose \
  --output-format stream-json 2>/dev/null | \
  python3 -uc "
import sys, json
seen = set()
for line in sys.stdin:
    line = line.strip()
    if not line:
        continue
    try:
        event = json.loads(line)
    except json.JSONDecodeError:
        continue
    etype = event.get('type', '')
    # Assistant text messages (deduplicate by uuid)
    if etype == 'assistant':
        msg = event.get('message', {})
        uid = event.get('uuid', '')
        if uid in seen:
            continue
        seen.add(uid)
        for block in msg.get('content', []):
            if block.get('type') == 'text':
                print(block['text'], flush=True)
    # Final result
    elif etype == 'result':
        text = event.get('result', '')
        if text:
            print(text, flush=True)
" 2>/dev/null | tee -a "$LOGFILE"
rm -f "$PROMPT_FILE"

CODE_END=$(date +%s)
CODE_ELAPSED=$(( CODE_END - CODE_START ))
log "Claude session completed in ${CODE_ELAPSED}s"

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

# ── VERIFY (targeted screenshots of changes) ─────────────
if grep -q "FACTORY_RESULT:SUCCESS" "$LOGFILE" 2>/dev/null && command -v agent-browser &>/dev/null; then
  stage "VERIFY"
  PR_NUM=$(grep -o 'https://github.com/[^ ]*pull/[0-9]*' "$LOGFILE" | tail -1 | grep -o '[0-9]*$')
  SCREENSHOT_DIR="$LOGDIR/screenshots/$TASK_NAME"
  mkdir -p "$SCREENSHOT_DIR"

  # Detect dev server command from package.json
  DEV_CMD=""
  DEV_URL=""
  cd "$REPO_DIR"
  if [ -f "package.json" ]; then
    DEV_CMD=$(python3 -c "
import json
scripts = json.load(open('package.json')).get('scripts', {})
for cmd in ['dev', 'start', 'preview']:
    if cmd in scripts:
        print(cmd)
        break
" 2>/dev/null)
  fi

  if [ -n "$DEV_CMD" ]; then
    log "Starting dev server: npm run $DEV_CMD"
    DEV_LOG=$(mktemp)
    npm run "$DEV_CMD" > "$DEV_LOG" 2>&1 &
    DEV_PID=$!

    # Wait for server URL in output (max 30s)
    for i in $(seq 1 30); do
      DEV_URL=$(grep -oE 'https?://localhost:[0-9]+' "$DEV_LOG" 2>/dev/null | head -1)
      if [ -n "$DEV_URL" ]; then
        break
      fi
      sleep 1
    done
    rm -f "$DEV_LOG"

    if [ -n "$DEV_URL" ]; then
      log "Dev server ready at $DEV_URL — running targeted screenshots"
      DIFF=$(git diff "$BASE_BRANCH...$BRANCH" 2>/dev/null)

      # Claude session to take targeted screenshots of the changes
      VERIFY_PROMPT_FILE=$(mktemp)
      cat > "$VERIFY_PROMPT_FILE" <<VERIFY_EOF
You are verifying a code change. The dev server is running at $DEV_URL.
Use agent-browser to screenshot the specific pages and components affected by this change.

TASK: $TASK_PROMPT

GIT DIFF:
$DIFF

SCREENSHOT DIR: $SCREENSHOT_DIR

Steps:
1. Look at the diff to understand what changed (components, pages, routes)
2. Use agent-browser to navigate to the affected pages
3. Take a screenshot of each affected area: agent-browser screenshot $SCREENSHOT_DIR/description.png
4. If the change is on a specific route, navigate there first
5. Take 1-3 screenshots max — focus on what changed, not everything
6. Print VERIFY_DONE when finished
VERIFY_EOF

      # Run verify session with progress feedback
      log "Screenshotting changes (max 120s)..."
      claude -p "$(cat "$VERIFY_PROMPT_FILE")" --dangerously-skip-permissions \
        --output-format stream-json 2>/dev/null | \
        python3 -uc "
import sys, json, time, signal

# Auto-kill after 120s
signal.alarm(120)
signal.signal(signal.SIGALRM, lambda *_: (print('[VERIFY] timed out after 120s', flush=True), sys.exit(0)))

seen = set()
last_log = time.time()
for line in sys.stdin:
    line = line.strip()
    if not line:
        continue
    try:
        event = json.loads(line)
    except json.JSONDecodeError:
        continue
    etype = event.get('type', '')
    if etype == 'assistant':
        uid = event.get('uuid', '')
        if uid in seen:
            continue
        seen.add(uid)
        for block in event.get('message', {}).get('content', []):
            if block.get('type') == 'text':
                print(block['text'], flush=True)
                last_log = time.time()
    elif etype == 'result':
        text = event.get('result', '')
        if text:
            print(text, flush=True)
    # Heartbeat every 15s of silence
    now = time.time()
    if now - last_log > 15:
        print('[VERIFY] still working...', flush=True)
        last_log = now
" 2>/dev/null | tee -a "$LOGFILE"
      rm -f "$VERIFY_PROMPT_FILE"
      log "VERIFY completed"
    else
      log "Dev server did not start within 30s"
    fi

    # Kill the dev server
    kill "$DEV_PID" 2>/dev/null
    wait "$DEV_PID" 2>/dev/null
  else
    log "No dev/start/preview script found — skipping verification"
  fi

  # Attach screenshots to PR
  SCREENSHOTS=$(find "$SCREENSHOT_DIR" -name '*.png' -type f 2>/dev/null)
  if [ -n "$SCREENSHOTS" ] && [ -n "$PR_NUM" ]; then
    GH_OWNER=$(gh api user --jq '.login' 2>/dev/null)

    # Commit screenshots to branch
    cp "$SCREENSHOT_DIR"/*.png "$REPO_DIR/" 2>/dev/null
    cd "$REPO_DIR"
    git add *.png
    git commit -m "Add verification screenshots" 2>/dev/null
    git push origin "$BRANCH" 2>/dev/null

    # Build PR comment with all screenshots
    COMMENT="## Verification Screenshots\n"
    for img in "$REPO_DIR"/*.png; do
      IMG_NAME=$(basename "$img")
      COMMENT="${COMMENT}\n### ${IMG_NAME%.png}\n![${IMG_NAME}](https://github.com/${GH_OWNER}/${REPO_NAME}/blob/${BRANCH}/${IMG_NAME}?raw=true)\n"
    done

    gh pr comment "$PR_NUM" --repo "${GH_OWNER}/${REPO_NAME}" \
      --body "$(echo -e "$COMMENT")" 2>/dev/null
    log "Screenshots attached to PR #$PR_NUM"
  fi
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

# Exit based on factory result
grep -q "FACTORY_RESULT:SUCCESS" "$LOGFILE" 2>/dev/null
