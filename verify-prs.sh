#!/bin/bash
# verify-prs.sh — rerun VERIFY on all open PRs for a repo
# Usage: bash verify-prs.sh owner/repo

SHIPYARD="$(cd "$(dirname "$0")" && pwd)"
REPO="${1:-stevederico/x-data}"
REPO_NAME=$(echo "$REPO" | cut -d/ -f2)
PROJECTS="${SHIPYARD_PROJECTS:-$(dirname "$SHIPYARD")}"
REPO_DIR=$(find "$PROJECTS" -maxdepth 1 -iname "$REPO_NAME" -type d 2>/dev/null | head -1)
LOGDIR="$SHIPYARD/logs"
TIMESTAMP=$(date +"%Y%m%d-%H%M%S")

if [ -z "$REPO_DIR" ]; then
  echo "Could not find repo: $REPO_NAME"
  exit 1
fi

echo "━━━ VERIFY ALL PRs: $REPO ━━━"
echo "Repo: $REPO_DIR"
echo ""

cd "$REPO_DIR"
git checkout master 2>/dev/null
git pull origin master 2>/dev/null

# Detect dev server command
DEV_CMD=$(python3 -c "
import json
scripts = json.load(open('package.json')).get('scripts', {})
for cmd in ['dev', 'start', 'preview']:
    if cmd in scripts:
        print(cmd)
        break
" 2>/dev/null)

if [ -z "$DEV_CMD" ]; then
  echo "No dev/start/preview script found"
  exit 1
fi

# Get all open PRs
PRS=$(gh pr list --repo "$REPO" --state open --json number,title,headRefName --limit 50 2>/dev/null)
PR_COUNT=$(echo "$PRS" | python3 -c "import json,sys; print(len(json.loads(sys.stdin.read())))")

echo "Found $PR_COUNT open PRs"
echo ""

echo "$PRS" | python3 -c "
import json, sys
prs = json.loads(sys.stdin.read())
for pr in prs:
    print(f\"{pr['number']}|{pr['headRefName']}|{pr['title']}\")
" | while IFS='|' read -r PR_NUM BRANCH TITLE; do
  echo "━━━ PR #$PR_NUM: $TITLE ━━━"

  SCREENSHOT_DIR="$LOGDIR/screenshots/pr-$PR_NUM"
  mkdir -p "$SCREENSHOT_DIR"

  # Create worktree for this branch
  WORKTREE="$REPO_DIR/.worktrees/verify-pr-$PR_NUM"
  rm -rf "$WORKTREE" 2>/dev/null
  cd "$REPO_DIR"
  git worktree prune 2>/dev/null
  git worktree add "$WORKTREE" "$BRANCH" 2>/dev/null

  if [ ! -d "$WORKTREE" ]; then
    echo "  Could not checkout $BRANCH — skipping"
    echo ""
    continue
  fi

  cd "$WORKTREE"
  npm install --silent 2>/dev/null

  # Start dev server
  DEV_LOG=$(mktemp)
  npm run "$DEV_CMD" > "$DEV_LOG" 2>&1 &
  DEV_PID=$!

  DEV_URL=""
  for i in $(seq 1 30); do
    DEV_URL=$(grep -oE 'https?://localhost:[0-9]+' "$DEV_LOG" 2>/dev/null | head -1)
    if [ -n "$DEV_URL" ]; then break; fi
    sleep 1
  done
  rm -f "$DEV_LOG"

  if [ -z "$DEV_URL" ]; then
    echo "  Dev server failed to start — skipping"
    kill "$DEV_PID" 2>/dev/null
    wait "$DEV_PID" 2>/dev/null
    rm -rf "$WORKTREE" 2>/dev/null
    git -C "$REPO_DIR" worktree prune 2>/dev/null
    echo ""
    continue
  fi

  echo "  Dev server at $DEV_URL"

  # Get the diff for context
  BASE_BRANCH=$(git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's@^refs/remotes/origin/@@')
  BASE_BRANCH="${BASE_BRANCH:-master}"
  DIFF=$(git diff "$BASE_BRANCH...$BRANCH" 2>/dev/null | head -200)

  # Claude verifies and screenshots
  VERIFY_PROMPT="You are verifying PR #$PR_NUM: $TITLE
Dev server is running at $DEV_URL.

Log format: plain text only, no markdown.

GIT DIFF (truncated):
$DIFF

Steps:
1. Navigate to the affected pages with agent-browser
2. Take 1-2 screenshots of the changes: agent-browser screenshot $SCREENSHOT_DIR/description.png
3. Print VERIFY_DONE when finished"

  echo "  Verifying..."
  echo "$VERIFY_PROMPT" | claude -p --dangerously-skip-permissions 2>/dev/null | tail -5

  # Kill dev server
  kill "$DEV_PID" 2>/dev/null
  wait "$DEV_PID" 2>/dev/null

  # Attach screenshots to PR
  SCREENSHOTS=$(find "$SCREENSHOT_DIR" -name '*.png' -type f 2>/dev/null)
  if [ -n "$SCREENSHOTS" ]; then
    GH_OWNER=$(echo "$REPO" | cut -d/ -f1)

    # Commit screenshots to branch
    cp "$SCREENSHOT_DIR"/*.png "$WORKTREE/" 2>/dev/null
    cd "$WORKTREE"
    git add *.png 2>/dev/null
    git commit -m "Add verification screenshots" 2>/dev/null
    git push origin "$BRANCH" 2>/dev/null

    COMMENT="## Verification Screenshots\n"
    for img in "$WORKTREE"/*.png; do
      IMG_NAME=$(basename "$img")
      COMMENT="${COMMENT}\n### ${IMG_NAME%.png}\n![${IMG_NAME}](https://github.com/${GH_OWNER}/${REPO_NAME}/blob/${BRANCH}/${IMG_NAME}?raw=true)\n"
    done

    gh pr comment "$PR_NUM" --repo "$REPO" \
      --body "$(echo -e "$COMMENT")" 2>/dev/null
    echo "  Screenshots attached to PR #$PR_NUM"
  else
    echo "  No screenshots taken"
  fi

  # Clean up worktree
  cd "$REPO_DIR"
  rm -rf "$WORKTREE" 2>/dev/null
  git worktree prune 2>/dev/null
  echo ""
done

cd "$REPO_DIR"
git checkout master 2>/dev/null
echo "━━━ DONE ━━━"
