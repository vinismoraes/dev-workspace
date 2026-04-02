#!/bin/zsh
# Usage: ./add-repo.sh TICKET-1234 repo1 [repo2 ...]
# Adds one or more repos to an existing task mid-flight.
# Example: ./add-repo.sh PCHAT-9999 api-specs
#
# Set REPOS_ROOT to the directory containing your repo clones (default: ~/GoProjects)

set -e

REPOS_ROOT=${REPOS_ROOT:-~/GoProjects}

TICKET=$1
shift
REPOS=("$@")

if [[ -z "$TICKET" || ${#REPOS[@]} -eq 0 ]]; then
  echo "Usage: $0 TICKET-1234 repo1 [repo2 ...]"
  exit 1
fi

TASK_DIR="$REPOS_ROOT/worktrees/$TICKET"
WORKSPACE_FILE="$TASK_DIR/$TICKET.code-workspace"

if [[ ! -f "$WORKSPACE_FILE" ]]; then
  echo "❌ No workspace found for $TICKET at $TASK_DIR"
  echo "   Run ./new-task.sh $TICKET first."
  exit 1
fi

for repo in $REPOS; do
  REPO_PATH="$REPOS_ROOT/$repo"
  WORKTREE_PATH="$TASK_DIR/$repo"

  if [[ ! -d "$REPO_PATH/.git" ]]; then
    echo "⚠️  Repo '$repo' not found at $REPO_PATH — skipping"
    continue
  fi

  if [[ -d "$WORKTREE_PATH" ]]; then
    echo "⚠️  Worktree for '$repo' already exists at $WORKTREE_PATH — skipping"
    continue
  fi

  echo "→ Fetching latest for $repo..."
  git -C "$REPO_PATH" fetch origin --quiet --prune

  echo "→ Updating $repo local main..."
  git -C "$REPO_PATH" update-ref refs/heads/main refs/remotes/origin/main 2>/dev/null || true

  echo "→ Creating worktree for $repo..."
  if git -C "$REPO_PATH" worktree add "$WORKTREE_PATH" -b "$TICKET" origin/main 2>/dev/null; then
    echo "  ✓ Created branch $TICKET from origin/main"
  elif git -C "$REPO_PATH" worktree add "$WORKTREE_PATH" "$TICKET" 2>/dev/null; then
    echo "  ✓ Checked out existing branch $TICKET"
  else
    echo "  ❌ Failed to create worktree for $repo — skipping"
    continue
  fi

  # Refresh worktree index so VS Code's git extension reads correct stat info
  git -C "$WORKTREE_PATH" status > /dev/null 2>&1

  # Inject new folder(s) into the workspace JSON using Python (relative paths)
  rel_paths=("$repo")
  [[ "$repo" == "services" ]] && rel_paths+=("$repo/src/el")

  for p in $rel_paths; do
    python3 - "$WORKSPACE_FILE" "$p" <<'EOF'
import sys, json
workspace_file, new_path = sys.argv[1], sys.argv[2]
with open(workspace_file) as f:
    ws = json.load(f)
if not any(folder.get("path") == new_path for folder in ws["folders"]):
    ws["folders"].append({"path": new_path})
with open(workspace_file, "w") as f:
    json.dump(ws, f, indent=2)
    f.write("\n")
EOF
  done

  echo "  ✓ Added $repo to workspace"
done

echo ""
echo "✅ Done. Workspace reloaded: $WORKSPACE_FILE"

if command -v code &>/dev/null; then
  code "$WORKSPACE_FILE"
elif [[ "$(uname)" == "Darwin" ]]; then
  open -a "Visual Studio Code" "$WORKSPACE_FILE"
fi
