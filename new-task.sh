#!/bin/zsh
# Usage: ./new-task.sh TICKET-1234 [repo1 repo2 ...]
# Default repo: services
# Example: ./new-task.sh PCHAT-9999
# Example: ./new-task.sh PCHAT-9999 services backend-extensions api-specs
#
# Set REPOS_ROOT to the directory containing your repo clones (default: ~/GoProjects)
# Example: export REPOS_ROOT=~/src

set -e

REPOS_ROOT=${REPOS_ROOT:-~/GoProjects}

TICKET=$1
if [[ -z "$TICKET" ]]; then
  echo "Usage: $0 TICKET-1234 [repo1 repo2 ...]"
  exit 1
fi

shift
REPOS=("${@:-services}")

WORKTREE_BASE="$REPOS_ROOT/worktrees"
TASK_DIR="$WORKTREE_BASE/$TICKET"
WORKSPACE_FILE="$TASK_DIR/$TICKET.code-workspace"

mkdir -p "$TASK_DIR"

declare -a folder_paths
declare -a git_repos

for repo in $REPOS; do
  REPO_PATH="$REPOS_ROOT/$repo"
  WORKTREE_PATH="$TASK_DIR/$repo"

  if [[ ! -d "$REPO_PATH/.git" ]]; then
    echo "⚠️  Repo '$repo' not found at $REPO_PATH — skipping"
    continue
  fi

  echo "→ Fetching latest for $repo..."
  git -C "$REPO_PATH" fetch origin --quiet --prune

  # Update local main to match origin/main
  echo "→ Updating $repo local main..."
  git -C "$REPO_PATH" update-ref refs/heads/main refs/remotes/origin/main 2>/dev/null || true

  echo "→ Creating worktree for $repo at $WORKTREE_PATH..."
  if git -C "$REPO_PATH" worktree add "$WORKTREE_PATH" -b "$TICKET" origin/main 2>/dev/null; then
    echo "  ✓ Created branch $TICKET from origin/main"
  elif git -C "$REPO_PATH" worktree add "$WORKTREE_PATH" "$TICKET" 2>/dev/null; then
    echo "  ✓ Checked out existing branch $TICKET"
  else
    echo "  ❌ Failed to create worktree for $repo — skipping"
    continue
  fi

  # Refresh worktree index so VS Code's git extension reads correct stat info
  # (fresh checkouts have uniform mtimes which confuse VS Code's diff engine)
  git -C "$WORKTREE_PATH" status > /dev/null 2>&1

  folder_paths+=("$repo")

  # services requires src/el as a separate root (go.mod lives there)
  if [[ "$repo" == "services" ]]; then
    folder_paths+=("$repo/src/el")
  fi

  # Track top-level repo folders for git scanning
  git_repos+=("$repo")
done

if [[ ${#folder_paths[@]} -eq 0 ]]; then
  echo "❌ No worktrees created. Aborting."
  exit 1
fi

# Color palette — each task gets a unique color, avoiding colors already used by other active worktrees
PALETTE=(
  "#1a5276:#1a3c50"   # deep blue
  "#1e8449:#175c35"   # forest green
  "#884ea0:#6a3d7d"   # purple
  "#c0392b:#8e2b20"   # red
  "#d68910:#a3680c"   # amber
  "#2e86c1:#225f8a"   # sky blue
  "#17a589:#128068"   # teal
  "#cb4335:#993227"   # crimson
  "#7d3c98:#5b2c6f"   # violet
  "#2874a6:#1b4f72"   # navy
  "#148f77:#0e6655"   # emerald
  "#b9770e:#7e5109"   # gold
)

# Collect colors already used by other active worktree workspaces
used_colors=()
for ws in "$WORKTREE_BASE"/*//*.code-workspace(N); do
  [[ "$(dirname "$ws")" == "$TASK_DIR" ]] && continue
  color=$(grep -o '"titleBar.activeBackground": *"[^"]*"' "$ws" 2>/dev/null | head -1 | sed 's/.*"\(#[^"]*\)".*/\1/')
  [[ -n "$color" ]] && used_colors+=("$color")
done

# Pick the first unused color; fall back to hash if all are taken
color_idx=0
for i in {1..${#PALETTE[@]}}; do
  active=${PALETTE[$i]%%:*}
  if (( ! ${used_colors[(Ie)$active]} )); then
    color_idx=$i
    break
  fi
done
if [[ $color_idx -eq 0 ]]; then
  hash_val=$(echo -n "$TICKET" | cksum | awk '{print $1}')
  color_idx=$(( (hash_val % ${#PALETTE[@]}) + 1 ))
fi
IFS=: read -r BG_ACTIVE BG_INACTIVE <<< "${PALETTE[$color_idx]}"

# Generate .code-workspace file
{
  echo '{'
  echo '  "folders": ['
  local last_idx=$((${#folder_paths[@]}))
  local idx=0
  for p in $folder_paths; do
    idx=$((idx + 1))
    if [[ $idx -lt $last_idx ]]; then
      echo "    { \"path\": \"${p}\" },"
    else
      echo "    { \"path\": \"${p}\" }"
    fi
  done
  echo '  ],'
  echo '  "settings": {'
  echo "    \"window.title\": \"🔧 ${TICKET} — \${activeEditorShort}\","
  echo '    "git.autoRepositoryDetection": false,'
  # Only scan top-level repo folders — prevents duplicate git discovery from subfolders
  local git_scan="["
  local gi=0
  for r in $git_repos; do
    gi=$((gi + 1))
    git_scan+="\"${r}\""
    [[ $gi -lt ${#git_repos[@]} ]] && git_scan+=", "
  done
  git_scan+="]"
  echo "    \"git.scanRepositories\": ${git_scan},"
  echo '    "git.autoFetch": false,'
  echo '    "git.detectSubmodules": false,'
  echo '    "workbench.colorCustomizations": {'
  echo "      \"titleBar.activeBackground\": \"${BG_ACTIVE}\","
  echo '      "titleBar.activeForeground": "#ffffff",'
  echo "      \"titleBar.inactiveBackground\": \"${BG_INACTIVE}\","
  echo '      "titleBar.inactiveForeground": "#cccccc",'
  echo "      \"statusBar.background\": \"${BG_ACTIVE}\","
  echo '      "statusBar.foreground": "#ffffff"'
  echo '    }'
  echo '  }'
  echo '}'
} > "$WORKSPACE_FILE"

echo ""
echo "✅ Task $TICKET is ready!"
echo "   Workspace: $WORKSPACE_FILE"
echo "   Repos: ${folder_paths[*]}"
echo ""

# Try to open VS Code; fall back to macOS open; print manual instructions if neither works
if command -v code &>/dev/null; then
  code --new-window "$WORKSPACE_FILE"
elif [[ "$(uname)" == "Darwin" ]]; then
  open -a "Visual Studio Code" "$WORKSPACE_FILE"
else
  echo "→ Open this workspace in VS Code:"
  echo "   code --new-window $WORKSPACE_FILE"
fi
