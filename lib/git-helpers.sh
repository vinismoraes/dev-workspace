#!/bin/zsh
# Shared git helpers for the task-workflow scripts.
# Source with:  source "$(dirname "$0")/lib/git-helpers.sh"

# safe_update_main REPO_PATH REPO_NAME
#
# Fast-forwards the local `main` ref to match `origin/main` without ever
# desyncing an open working tree.
#
# Behavior:
#   - HEAD is on main + working tree clean → `git merge --ff-only origin/main`
#     (updates both ref and working tree together — safe).
#   - HEAD is on main + working tree dirty → skip and warn (would clobber WIP).
#   - HEAD is not on main → `git update-ref refs/heads/main origin/main`
#     (working tree unaffected — safe).
#
# Assumes `git fetch origin` has already been called by the caller.
safe_update_main() {
  local repo_path=$1 repo_name=$2
  local current_branch
  current_branch=$(git -C "$repo_path" symbolic-ref --short HEAD 2>/dev/null || echo "")

  if [[ "$current_branch" == "main" ]]; then
    if [[ -z "$(git -C "$repo_path" status --porcelain --untracked-files=no)" ]]; then
      git -C "$repo_path" merge --ff-only --quiet origin/main 2>/dev/null || \
        echo "  ⚠️  Could not fast-forward $repo_name main (diverged?). Leaving as-is."
    else
      echo "  ⚠️  $repo_name main clone has local changes on main — skipping ref update to avoid desyncing the working tree"
    fi
  else
    git -C "$repo_path" update-ref refs/heads/main refs/remotes/origin/main 2>/dev/null || true
  fi
}
