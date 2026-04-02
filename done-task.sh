#!/bin/zsh
# Usage: ./done-task.sh TICKET-1234
# Removes all worktrees and the workspace directory for a completed task.
#
# Set REPOS_ROOT to the directory containing your repo clones (default: ~/GoProjects)

REPOS_ROOT=${REPOS_ROOT:-~/GoProjects}

TICKET=$1
if [[ -z "$TICKET" ]]; then
  echo "Usage: $0 TICKET-1234"
  exit 1
fi

WORKTREE_BASE="$REPOS_ROOT/worktrees"
TASK_DIR="$WORKTREE_BASE/$TICKET"

if [[ ! -d "$TASK_DIR" ]]; then
  echo "No worktree directory found at $TASK_DIR"
  exit 1
fi

echo "Cleaning up worktrees for $TICKET..."

for worktree_dir in "$TASK_DIR"/*/; do
  [[ -d "$worktree_dir" ]] || continue
  repo=$(basename "$worktree_dir")
  REPO_PATH="$REPOS_ROOT/$repo"

  if [[ -d "$REPO_PATH/.git" ]]; then
    echo "→ Removing worktree $repo..."
    git -C "$REPO_PATH" worktree remove "$worktree_dir" --force 2>/dev/null && echo "  ✓ Worktree removed"
    git -C "$REPO_PATH" worktree prune 2>/dev/null
    # Only delete local branch — remote branch stays for the PR
    git -C "$REPO_PATH" branch -d "$TICKET" 2>/dev/null && echo "  ✓ Local branch deleted" || true
  fi
done

rm -rf "$TASK_DIR"

echo ""
echo "✅ Cleaned up $TICKET"
