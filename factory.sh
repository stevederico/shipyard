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

stage "1/10 PICK"
log "Reading tasks from $TODOS"
TASK=$(awk '/^## (WIP|Tasks)$/{found=1;next} /^## /{found=0} found && /^- /{print; exit}' "$TODOS" \
  | sed 's/^- //')

if [ -z "$TASK" ]; then
  log "No tasks found"
  exit 0
fi

# Strip completion and tags for display
TASK_CLEAN=$(echo "$TASK" | sed 's/ \[[0-9]*\]//;s/ #[a-z]*//g')
log "Task: $TASK_CLEAN"

if [ "$1" = "--dry-run" ]; then
  log "Dry run — stopping before execution"
  exit 0
fi

stage "2/10 ROUTE → 9/10 UPDATE (Claude session)"

# Let Claude figure out the project, code it, test it, ship it
claude -p "
You are running in factory mode. Complete this task autonomously.

TASK: $TASK_CLEAN

Print a stage header before each step using this exact format:
  [STAGE N/10: NAME] description

The stages are:
  [STAGE 2/10: ROUTE] Finding the project directory
  [STAGE 3/10: PULL] Git pulling latest
  [STAGE 4/10: PLAN] Reading todo.md and CLAUDE.md, selecting subtask
  [STAGE 5/10: BRANCH] Creating feature branch
  [STAGE 6/10: CODE] Implementing the task (narrate what you are building)
  [STAGE 7/10: TEST] Running tests
  [STAGE 8/10: SHIP] Committing, pushing, opening PR
  [STAGE 9/10: UPDATE] Marking subtask done in project todo.md

Steps:
1. Find which project in $PROJECTS this task belongs to (ls the directory, match by name)
2. cd to that project and git pull origin master
3. Read CLAUDE.md in the project root if it exists — it has project-specific instructions
4. Read todo.md in the project root if it exists — pick the FIRST incomplete item (lines starting with '- ')
5. If todo.md exists, work on that specific subtask. If no todo.md, work on the global task description above.
6. Create a feature branch: factory/$(date +%Y%m%d-%H%M)
7. Complete the subtask
8. Run tests if they exist (deno run test)
9. If tests pass: commit and push the branch, then open a PR via gh pr create
10. If no tests exist: commit and push the branch, open a PR
11. After shipping, mark the subtask as done in todo.md (remove the '- ' prefix)
12. At the end, print FACTORY_RESULT:SUCCESS or FACTORY_RESULT:FAILED
13. Also print FACTORY_REMAINING:N where N is the number of '- ' lines still in todo.md (0 if no todo.md)
" --dangerously-skip-permissions 2>&1 | tee -a "$LOGFILE"

stage "10/10 DONE"

# Check result from log
if grep -q "FACTORY_RESULT:SUCCESS" "$LOGFILE" 2>/dev/null; then
  log "Subtask completed successfully"

  # Check how many subtasks remain in the project's todo.md
  REMAINING=$(grep -o "FACTORY_REMAINING:[0-9]*" "$LOGFILE" | tail -1 | cut -d: -f2)
  log "Remaining subtasks: ${REMAINING:-unknown}"

  if [ "$REMAINING" = "0" ]; then
    log "All subtasks done — marking global task complete"

    # Remove the task line from global todos
    sed -i '' "/^- $(echo "$TASK" | sed 's/[\/&]/\\&/g')$/d" "$TODOS"

    # Add to today's date section (or create it)
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
  log "Task failed — check log: $LOGFILE"
fi
