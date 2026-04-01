#!/bin/bash
# factory.sh — minimal code factory
# Reads next task from todos.md, lets Claude handle everything autonomously.
# Usage: bash factory.sh [--dry-run]

TODOS="$HOME/todos.md"
PROJECTS="$HOME/Desktop/projects"
DATE=$(date +"%m/%d/%y")

# Get highest priority task (sort by [N] descending, take first)
TASK=$(sed -n '/^## Tasks$/,/^## /{/^- /p}' "$TODOS" \
  | sed 's/^- //' \
  | sort -t'[' -k2 -rn \
  | head -1)

if [ -z "$TASK" ]; then
  echo "No tasks"
  exit 0
fi

# Strip priority and tags for display
TASK_CLEAN=$(echo "$TASK" | sed 's/ \[[0-9]*\]//;s/ #[a-z]*//g')
echo "Factory picking up: $TASK_CLEAN"

if [ "$1" = "--dry-run" ]; then
  echo "Dry run — would execute: $TASK_CLEAN"
  exit 0
fi

# Let Claude figure out the project, code it, test it, ship it
claude -p "
You are running in factory mode. Complete this task autonomously.

TASK: $TASK_CLEAN

Steps:
1. Figure out which project in $PROJECTS this task belongs to (ls the directory, match by name)
2. cd to that project and git pull origin master
3. Create a feature branch: factory/$(date +%Y%m%d-%H%M)
4. Complete the task
5. Run tests if they exist (deno run test)
6. If tests pass: commit and push the branch, then open a PR via gh pr create
7. If no tests exist: commit and push the branch, open a PR
8. At the end, print FACTORY_RESULT:SUCCESS or FACTORY_RESULT:FAILED
" --dangerously-skip-permissions 2>&1 | tee /tmp/factory-latest.log

# Check if Claude reported success
if grep -q "FACTORY_RESULT:SUCCESS" /tmp/factory-latest.log; then
  # Move task from Tasks to today's completed section
  # Remove the task line
  sed -i '' "/^- $(echo "$TASK" | sed 's/[\/&]/\\&/g')$/d" "$TODOS"

  # Add to today's date section (or create it)
  if grep -q "^## $DATE" "$TODOS"; then
    sed -i '' "/^## $DATE$/a\\
$TASK_CLEAN" "$TODOS"
  else
    # Insert new date section after WIP section
    sed -i '' "/^## Tasks$/i\\
## $DATE\\
$TASK_CLEAN\\
" "$TODOS"
  fi

  echo "Factory complete: $TASK_CLEAN"
else
  echo "Factory failed: $TASK_CLEAN (see /tmp/factory-latest.log)"
fi
