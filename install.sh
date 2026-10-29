#!/bin/zsh
# Installs dev-workspace task scripts.
#
# Scripts are symlinked into $REPOS_ROOT (default: ~/GoProjects) so they're
# available from anywhere. Re-running is safe — existing symlinks are updated.
#
# Usage:
#   ./install.sh
#   ./install.sh --no-shell-path   # skip PATH updates to shell rc

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPOS_ROOT=${REPOS_ROOT:-~/GoProjects}
SHELL_PATH=true

while [[ $# -gt 0 ]]; do
  case "$1" in
    --no-shell-path) SHELL_PATH=false; shift ;;
    *) echo "Unknown option: $1"; exit 1 ;;
  esac
done

echo "Installing task scripts → $REPOS_ROOT"

for f in "$SCRIPT_DIR"/task-journal.py "$SCRIPT_DIR"/{new-task,add-repo,done-task,quick-start-repo,sync-task,sync-main-clones,clean-clones}.sh; do
  [[ -f "$f" ]] || continue
  name=$(basename "$f")
  target="$REPOS_ROOT/$name"
  if [[ -L "$target" ]]; then
    current=$(readlink "$target")
    if [[ "$current" == "$f" ]]; then
      echo "  ✓ $name (up to date)"
    else
      ln -sf "$f" "$target"
      echo "  ✓ $name (updated)"
    fi
  elif [[ -f "$target" ]]; then
    echo "  ⚠  $name exists (not a symlink) — skipping. Remove it manually to use the repo version."
  else
    ln -s "$f" "$target"
    echo "  + $name"
  fi
done

# --- Workspace git settings ---
# Prevent main workspace from discovering worktree repos in the SCM view

echo ""
echo "Patching workspace git settings"
for ws in "$REPOS_ROOT"/*.code-workspace; do
  [[ -f "$ws" ]] || continue
  name=$(basename "$ws")
  if grep -q '"git.autoRepositoryDetection"' "$ws" 2>/dev/null; then
    echo "  ✓ $name (already patched)"
  elif command -v python3 &>/dev/null; then
    python3 -c "
import json, sys
with open(sys.argv[1], 'r') as f:
    ws = json.load(f)
s = ws.setdefault('settings', {})
s['git.autoRepositoryDetection'] = False
repos = []
for folder in ws.get('folders', []):
    p = folder.get('path', '')
    if '/' not in p:
        repos.append(p)
if repos:
    s['git.scanRepositories'] = repos
with open(sys.argv[1], 'w') as f:
    json.dump(ws, f, indent=2)
    f.write('\n')
" "$ws" && echo "  ✓ $name (patched)" || echo "  ⚠  $name — failed to patch"
  else
    echo "  ⚠  $name — python3 not found, skipping"
  fi
done

# --- Shell PATH ---

if $SHELL_PATH && [[ -d "$REPOS_ROOT" ]]; then
  SHELL_RC="$HOME/.zshrc"
  [[ -f "$SHELL_RC" ]] || SHELL_RC="$HOME/.bashrc"
  PATH_LINE="export PATH=\"$REPOS_ROOT:\$PATH\""

  if [[ -f "$SHELL_RC" ]] && ! grep -qF "$REPOS_ROOT" "$SHELL_RC" 2>/dev/null; then
    echo "" >> "$SHELL_RC"
    echo "# dev-workspace task scripts" >> "$SHELL_RC"
    echo "$PATH_LINE" >> "$SHELL_RC"
    echo ""
    echo "Added $REPOS_ROOT to PATH in $SHELL_RC"
    echo "Run: source $SHELL_RC"
  fi
fi

echo ""
echo "✅ Done. Pull this repo and re-run to update."
