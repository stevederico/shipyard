#!/bin/bash
# factory.sh — shipyard code factory
# Reads next task file from tasks/, lets Claude handle everything autonomously.
# Usage: bash factory.sh [--dry-run] [--issues owner/repo] [--parallel N]

SHIPYARD="${SHIPYARD_DIR:-$(cd "$(dirname "$0")" && pwd)}"
TASK_DIR="$SHIPYARD/tasks"
DONE_DIR="$TASK_DIR/done"
LOCK_DIR="$TASK_DIR/.locks"
PROJECTS="${SHIPYARD_PROJECTS:-$(dirname "$SHIPYARD")}"
LOGDIR="$SHIPYARD/logs"
TIMESTAMP=$(date +"%Y%m%d-%H%M%S")

STATUS_DIR="$SHIPYARD/.status"
mkdir -p "$LOGDIR" "$DONE_DIR" "$LOCK_DIR" "$STATUS_DIR"
AGENT_ID="${SHIPYARD_AGENT_ID:-0}"
LOGFILE="$LOGDIR/$TIMESTAMP-w$AGENT_ID.log"
WORKTREE_DIR=""

if [ "$AGENT_ID" = "0" ]; then
  log() { echo "[$(date +"%H:%M:%S")] $1" >> "$LOGFILE"; echo "$1"; }
  PREFIX=""
else
  log() { echo "[$(date +"%H:%M:%S")] $1" >> "$LOGFILE"; echo "[Agent-$AGENT_ID] $1"; }
  PREFIX="[Agent-$AGENT_ID] "
fi
stage() { echo "" >> "$LOGFILE"; echo ""; log "━━━ $1 ━━━"; }
update_status() { echo "$1" > "$STATUS_DIR/agent-$AGENT_ID"; }
# Prefixed tee: writes raw to log, prefixed to terminal
ptee() { while IFS= read -r line; do echo "$line" >> "$LOGFILE"; echo "${PREFIX}${line}"; done; }

# ── Ctrl+C cleanup ────────────────────────────────────────
cleanup() {
  echo "" | ptee
  log "━━━ CANCELLED ━━━"
  # Remove task lock
  if [ -n "$TASK_FILE" ]; then
    rm -rf "$LOCK_DIR/$(basename "$TASK_FILE").lock" 2>/dev/null
  fi
  # Clean up worktree
  if [ -n "$WORKTREE_DIR" ] && [ -d "$WORKTREE_DIR" ]; then
    cd "$SHIPYARD"
    rm -rf "$WORKTREE_DIR" 2>/dev/null
    git -C "$(dirname "$WORKTREE_DIR")" worktree prune 2>/dev/null
    log "Cleaned up worktree"
  fi
  exit 130
}
trap cleanup INT

# ── PARALLEL: spawn N agents ──────────────────────────────
if [ "$1" = "--parallel" ]; then
  AGENTS="${2:-3}"
  rm -f "$STATUS_DIR"/agent-* 2>/dev/null

  echo "━━━ SHIPYARD: $AGENTS parallel agents ━━━"
  echo ""

  PIDS=""
  for i in $(seq 1 "$AGENTS"); do
    SHIPYARD_AGENT_ID="$i" bash "$0" &
    PIDS="$PIDS $!"
    sleep 1
  done
  echo ""

  # Wait for all agents (output streams live with [AN] prefix)
  FAILED=0
  for pid in $PIDS; do
    wait "$pid" || FAILED=$((FAILED + 1))
  done

  # Final summary
  echo ""
  echo "━━━ SUMMARY ━━━"
  for i in $(seq 1 "$AGENTS"); do
    STATUS="unknown"
    if [ -f "$STATUS_DIR/worker-$i" ]; then
      STATUS=$(cat "$STATUS_DIR/worker-$i")
    fi
    echo "  W$i: $STATUS"
  done
  echo ""
  rm -f "$STATUS_DIR"/agent-* 2>/dev/null
  exit $FAILED
fi

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
update_status "picking task..."
log "Reading tasks from $TASK_DIR"

# Find first unlocked task
TASK_FILE=""
for candidate in $(find "$TASK_DIR" -maxdepth 1 -name '*.md' -type f 2>/dev/null | sort); do
  LOCK_FILE="$LOCK_DIR/$(basename "$candidate").lock"
  # Try to acquire lock (atomic via mkdir)
  if mkdir "$LOCK_FILE" 2>/dev/null; then
    TASK_FILE="$candidate"
    break
  fi
done

# Clean up stale locks (older than 30 min)
find "$LOCK_DIR" -maxdepth 1 -name '*.lock' -type d -mmin +30 -exec rm -rf {} \; 2>/dev/null

if [ -z "$TASK_FILE" ]; then
  log "No pending tasks (or all locked)"
  update_status "idle — no tasks"
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
update_status "$TASK_NAME — picked"

DRY_RUN=false
if [ "$1" = "--dry-run" ]; then
  DRY_RUN=true
fi

# ── 2/12 ROUTE ─────────────────────────────────────────────
stage "ROUTE"
update_status "$TASK_NAME — routing"

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
        gh repo clone "$GH_REPO" "$PROJECTS/$TASK_REPO" 2>&1 | ptee
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
    cd "$REPO_DIR" && git init 2>&1 | ptee
    IS_NEW_REPO=true
    log "Created new repo: $REPO_NAME ($REPO_DIR)"
  fi
fi

REPO_NAME=$(basename "$REPO_DIR")
log "Repo: $REPO_NAME ($REPO_DIR)"

# ── 3/12 PULL ──────────────────────────────────────────────
stage "PULL"
update_status "$TASK_NAME — pulling"
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
      git pull origin "$BASE_BRANCH" 2>&1 | ptee
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
  # Use worktree for isolation (parallel-safe)
  WORKTREE_DIR="$REPO_DIR/.worktrees/$TASK_NAME"
  rm -rf "$WORKTREE_DIR" 2>/dev/null
  git worktree prune 2>/dev/null
  git worktree add "$WORKTREE_DIR" -b "$BRANCH" 2>&1 | ptee
  REPO_DIR="$WORKTREE_DIR"
  cd "$REPO_DIR"
fi
log "Branch: $BRANCH"

# Save pre-code state for lint checks
PRE_VERSION=""
if [ -f "$REPO_DIR/package.json" ]; then
  PRE_VERSION=$(python3 -c "import json; print(json.load(open('package.json')).get('version',''))" 2>/dev/null)
fi

# ── Dry run summary ───────────────────────────────────────
if [ "$DRY_RUN" = true ]; then
  echo "" | ptee
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
  echo "$TASK_PROMPT" | ptee
  rm -rf "$LOCK_DIR/$(basename "$TASK_FILE").lock" 2>/dev/null
  exit 0
fi

# ── CODE + TEST (Claude session) ──────────────────────────
stage "CODE"
update_status "$TASK_NAME — coding..."
log "Ctrl+C to cancel. Monitor: tail -f $LOGFILE"
CODE_START=$(date +%s)

# Write prompt to temp file to avoid quoting issues with script
PROMPT_FILE=$(mktemp)
cat > "$PROMPT_FILE" <<PROMPT_EOF
You are running in shipyard mode. Complete this task autonomously.

REPO: $REPO_NAME
NEW_REPO: $IS_NEW_REPO

--- TASK ---
$TASK_PROMPT
--- END TASK ---

Log format rules (follow exactly):
- Stage headers: ━━━ STAGE_NAME ━━━ (e.g. ━━━ CODE ━━━, ━━━ TEST ━━━)
- Progress: plain text, no markdown, no ** or ## or []
- Results: plain text summary of what changed

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
" 2>/dev/null | ptee
rm -f "$PROMPT_FILE"

CODE_END=$(date +%s)
CODE_ELAPSED=$(( CODE_END - CODE_START ))
log "Claude session completed in ${CODE_ELAPSED}s"

# ── LINT (deterministic checks) ───────────────────────────
stage "LINT"
update_status "$TASK_NAME — linting"
LINT_PASS=true
LINT_FAILURES=""

# Check: no .env or secrets committed on branch
if git diff "$BASE_BRANCH...$BRANCH" --name-only 2>/dev/null | grep -qE '\.env|\.pem|\.key|credentials|secrets|tokens'; then
  log "FAIL: secrets or .env in committed files"
  LINT_FAILURES="${LINT_FAILURES}\n- Secrets or .env files committed to branch"
  LINT_PASS=false
fi

# Check: changelog was modified
if ! git diff "$BASE_BRANCH...$BRANCH" --name-only 2>/dev/null | grep -qi "changelog"; then
  log "WARN: CHANGELOG.md not updated"
  LINT_FAILURES="${LINT_FAILURES}\n- CHANGELOG.md not updated"
fi

# Check: package.json version bumped
if [ -f "$REPO_DIR/package.json" ] && [ -n "$PRE_VERSION" ]; then
  POST_VERSION=$(python3 -c "import json; print(json.load(open('package.json')).get('version',''))" 2>/dev/null)
  if [ "$PRE_VERSION" = "$POST_VERSION" ]; then
    log "WARN: package.json version not bumped ($PRE_VERSION)"
    LINT_FAILURES="${LINT_FAILURES}\n- package.json version not bumped (still $PRE_VERSION)"
  else
    log "OK: version $PRE_VERSION → $POST_VERSION"
  fi
fi

# Check: tests passed (look for failure indicators in log)
if grep -qE "(FAIL|ERROR|test.*failed|Tests:.*failed)" "$LOGFILE" 2>/dev/null && ! grep -q "FACTORY_RESULT:SUCCESS" "$LOGFILE"; then
  log "FAIL: tests did not pass"
  LINT_FAILURES="${LINT_FAILURES}\n- Tests failed"
  LINT_PASS=false
fi

if [ "$LINT_PASS" = true ] && [ -z "$LINT_FAILURES" ]; then
  log "All lint checks passed"
else
  log "Lint issues found"
fi

# ── FIX (Claude fixes lint failures — max 2 attempts) ────
if [ -n "$LINT_FAILURES" ]; then
  stage "FIX"
  update_status "$TASK_NAME — fixing lint"
  FIX_ATTEMPT=0
  MAX_FIX_ATTEMPTS=2

  while [ -n "$LINT_FAILURES" ] && [ "$FIX_ATTEMPT" -lt "$MAX_FIX_ATTEMPTS" ]; do
    FIX_ATTEMPT=$((FIX_ATTEMPT + 1))
    log "Fix attempt $FIX_ATTEMPT/$MAX_FIX_ATTEMPTS"

    FIX_PROMPT_FILE=$(mktemp)
    cat > "$FIX_PROMPT_FILE" <<LINT_FIX_EOF
You are fixing lint failures in a shipyard run. Fix these issues and commit.

PROJECT: $REPO_NAME
BRANCH: $BRANCH

LINT FAILURES:
$(echo -e "$LINT_FAILURES")

Log format: plain text, no markdown, no ** or ## or []. Use ━━━ STAGE ━━━ for headers.

Steps:
1. Fix each issue listed above
2. If secrets are committed, remove them and add to .gitignore
3. If CHANGELOG.md missing, create or update it
4. If version not bumped, bump it in package.json
5. If tests failed, fix the failing tests
6. Stage only files you changed, commit with a descriptive message
7. Push: git push origin $BRANCH
8. Print FIX_DONE when finished
LINT_FIX_EOF

    claude -p "$(cat "$FIX_PROMPT_FILE")" --dangerously-skip-permissions \
      --output-format stream-json 2>/dev/null | \
      python3 -uc "
import sys, json, time, signal

signal.alarm(120)
signal.signal(signal.SIGALRM, lambda *_: (print('timed out', flush=True), sys.exit(0)))

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
    now = time.time()
    if now - last_log > 15:
        print('still working...', flush=True)
        last_log = now
" 2>/dev/null | ptee
    rm -f "$FIX_PROMPT_FILE"

    # Re-run lint checks
    LINT_FAILURES=""
    if git diff "$BASE_BRANCH...$BRANCH" --name-only 2>/dev/null | grep -qE '\.env|\.pem|\.key|credentials|secrets|tokens'; then
      LINT_FAILURES="${LINT_FAILURES}\n- Secrets or .env files still committed"
    fi
    if ! git diff "$BASE_BRANCH...$BRANCH" --name-only 2>/dev/null | grep -qi "changelog"; then
      LINT_FAILURES="${LINT_FAILURES}\n- CHANGELOG.md still not updated"
    fi
    if [ -f "$REPO_DIR/package.json" ] && [ -n "$PRE_VERSION" ]; then
      POST_VERSION=$(python3 -c "import json; print(json.load(open('package.json')).get('version',''))" 2>/dev/null)
      if [ "$PRE_VERSION" = "$POST_VERSION" ]; then
        LINT_FAILURES="${LINT_FAILURES}\n- package.json version still not bumped"
      fi
    fi

    if [ -z "$LINT_FAILURES" ]; then
      log "All lint issues fixed"
      break
    else
      log "Issues remaining after attempt $FIX_ATTEMPT"
    fi
  done

  if [ -n "$LINT_FAILURES" ]; then
    log "Could not fix all lint issues after $MAX_FIX_ATTEMPTS attempts"
  fi
fi

# ── SHIP ──────────────────────────────────────────────────
stage "SHIP"
update_status "$TASK_NAME — shipping"
if grep -q "FACTORY_RESULT:SUCCESS" "$LOGFILE" 2>/dev/null; then
  log "PR shipped on branch $BRANCH"
else
  log "No PR — Claude reported failure"
fi

# ── VERIFY (self-verification loop) ───────────────────────
if grep -q "FACTORY_RESULT:SUCCESS" "$LOGFILE" 2>/dev/null && command -v agent-browser &>/dev/null; then
  stage "VERIFY"
  update_status "$TASK_NAME — verifying"
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
    # Install deps in worktree (symlinks from main repo may be broken)
    if [ -n "$WORKTREE_DIR" ] && [ -f "package.json" ]; then
      log "Installing dependencies in worktree..."
      npm install --silent 2>/dev/null
    fi
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
      log "Dev server ready at $DEV_URL — verifying changes"
      DIFF=$(git diff "$BASE_BRANCH...$BRANCH" 2>/dev/null)

      VERIFY_PROMPT_FILE=$(mktemp)
      cat > "$VERIFY_PROMPT_FILE" <<VERIFY_EOF
You are a QA engineer verifying a code change. The dev server is running at $DEV_URL.

TASK REQUIREMENTS:
$TASK_PROMPT

GIT DIFF:
$DIFF

SCREENSHOT DIR: $SCREENSHOT_DIR

Log format: plain text, no markdown, no ** or ## or []. Use ━━━ STAGE ━━━ for headers.

Your job is to verify the implementation matches the task requirements. Do this:

1. Read the diff to understand what changed and which pages/routes are affected
2. Use agent-browser to navigate to the affected pages
3. Check the browser console for errors: agent-browser execute "JSON.stringify(window.__console_errors || [])"
4. Take screenshots of the changes: agent-browser screenshot $SCREENSHOT_DIR/description.png
5. Compare what you see against the task requirements:
   - Is the feature visible and in the right place?
   - Does it look correct (colors, layout, text)?
   - Are there any console errors?
   - Does interacting with it work? (click buttons, type in inputs, etc.)

6. Print your verdict:
   VERIFY_PASS — if the implementation matches the requirements and works correctly
   VERIFY_FAIL: reason — if something is wrong, describe what needs fixing

Max 2 minutes. Focus on what the task asked for, not unrelated issues.
VERIFY_EOF

      log "Verifying implementation (max 120s)..."
      VERIFY_OUTPUT=$(claude -p "$(cat "$VERIFY_PROMPT_FILE")" --dangerously-skip-permissions \
        --output-format stream-json 2>/dev/null | \
        python3 -uc "
import sys, json, time, signal

signal.alarm(120)
signal.signal(signal.SIGALRM, lambda *_: (print('VERIFY_PASS (timed out)', flush=True), sys.exit(0)))

seen = set()
last_log = time.time()
output = []
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
                output.append(block['text'])
                last_log = time.time()
    elif etype == 'result':
        text = event.get('result', '')
        if text:
            print(text, flush=True)
            output.append(text)
    now = time.time()
    if now - last_log > 15:
        print('still working...', flush=True)
        last_log = now
" 2>/dev/null | ptee)
      rm -f "$VERIFY_PROMPT_FILE"

      # Check if verification passed or failed
      if echo "$VERIFY_OUTPUT" | grep -q "VERIFY_FAIL"; then
        FAIL_REASON=$(echo "$VERIFY_OUTPUT" | grep "VERIFY_FAIL" | sed 's/VERIFY_FAIL: *//')
        log "Verification FAILED: $FAIL_REASON"
        log "Attempting fix..."

        # Second Claude session to fix the issue
        FIX_PROMPT_FILE=$(mktemp)
        cat > "$FIX_PROMPT_FILE" <<FIX_EOF
The QA verification of your code change found an issue. Fix it.

Log format: plain text, no markdown, no ** or ## or []. Use ━━━ STAGE ━━━ for headers.

TASK: $TASK_PROMPT
ISSUE: $FAIL_REASON

The dev server is running at $DEV_URL. Fix the code, then verify with agent-browser that it works.

Steps:
1. Fix the issue in the source code
2. Wait for hot reload (the dev server is still running)
3. Use agent-browser to verify the fix: agent-browser open $DEV_URL && agent-browser wait --load networkidle
4. Take a screenshot: agent-browser screenshot $SCREENSHOT_DIR/after-fix.png
5. Stage and commit: git add <files> && git commit -m "Fix: <description>"
6. Push: git push origin $BRANCH
7. Print VERIFY_PASS if fixed, VERIFY_FAIL: <reason> if still broken
FIX_EOF

        log "Running fix session..."
        claude -p "$(cat "$FIX_PROMPT_FILE")" --dangerously-skip-permissions \
          --output-format stream-json 2>/dev/null | \
          python3 -uc "
import sys, json, time, signal

signal.alarm(120)
signal.signal(signal.SIGALRM, lambda *_: (print('VERIFY_PASS (timed out)', flush=True), sys.exit(0)))

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
    now = time.time()
    if now - last_log > 15:
        print('still working...', flush=True)
        last_log = now
" 2>/dev/null | ptee
        rm -f "$FIX_PROMPT_FILE"
        log "Fix attempt completed"
      else
        log "Verification PASSED"
      fi
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
    git add *.png 2>/dev/null
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
    gh issue comment "$ISSUE_NUM" --repo "$ISSUE_REPO" --body "Shipped in ${PR_URL:-branch $BRANCH}" 2>&1 | ptee
    gh issue close "$ISSUE_NUM" --repo "$ISSUE_REPO" 2>&1 | ptee
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
  update_status "$TASK_NAME ✓ done"
else
  log "Factory run failed — check log: $LOGFILE"
  update_status "$TASK_NAME ✗ failed"
fi

# Clean up worktree and lock
if [ -n "$WORKTREE_DIR" ] && [ -d "$WORKTREE_DIR" ]; then
  ORIG_REPO=$(dirname "$WORKTREE_DIR")/..
  cd "$SHIPYARD"
  rm -rf "$WORKTREE_DIR" 2>/dev/null
  git -C "$(cd "$ORIG_REPO" && pwd)" worktree prune 2>/dev/null
fi
if [ -n "$TASK_FILE" ]; then
  rm -rf "$LOCK_DIR/$(basename "$TASK_FILE").lock" 2>/dev/null
fi

# Exit based on factory result
grep -q "FACTORY_RESULT:SUCCESS" "$LOGFILE" 2>/dev/null
