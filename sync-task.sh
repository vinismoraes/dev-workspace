#!/bin/zsh
# Usage: ./sync-task.sh BRANCH [--merge] [--dry-run]
# Rebases every worktree of a task onto the latest origin/main so you absorb
# what others have shipped without leaving your task branch.
#
# Behavior per repo worktree:
#   1. Fetch origin (safe — no working-tree changes).
#   2. Refresh the local `main` ref via safe_update_main (never desyncs any
#      main-clone window that happens to have main checked out).
#   3. If the worktree has uncommitted changes → skip and warn (won't touch WIP).
#   4. If already up to date with origin/main → skip silently.
#   5. Otherwise run `git rebase origin/main` (or `merge` with --merge).
#      On conflict, aborts the rebase cleanly and warns.
#
# --merge     use `git merge origin/main` instead of `git rebase origin/main`
# --dry-run   report what would happen without changing anything

set -e

REPOS_ROOT=${REPOS_ROOT:-~/GoProjects}

source "${0:A:h}/lib/git-helpers.sh"

BRANCH=""
STRATEGY="rebase"
DRY_RUN=false

for arg in "$@"; do
  case "$arg" in
    --merge) STRATEGY="merge" ;;
    --dry-run|-n) DRY_RUN=true ;;
    -h|--help)
      sed -n '2,16p' "$0"
      exit 0
      ;;
    -*)
      echo "Unknown flag: $arg"
      exit 1
      ;;
    *)
      if [[ -z "$BRANCH" ]]; then
        BRANCH="$arg"
      else
        echo "Unexpected extra argument: $arg"
        exit 1
      fi
      ;;
  esac
done

if [[ -z "$BRANCH" ]]; then
  echo "Usage: $0 BRANCH [--merge] [--dry-run]"
  exit 1
fi

TASK_DIR="$REPOS_ROOT/worktrees/$BRANCH"
if [[ ! -d "$TASK_DIR" ]]; then
  echo "❌ No task directory at $TASK_DIR"
  echo "   Available tasks:"
  ls "$REPOS_ROOT/worktrees" 2>/dev/null | sed 's/^/     /'
  exit 1
fi

[[ "$DRY_RUN" == true ]] && echo "🔍 DRY RUN — no changes will be made"
echo "→ Syncing $BRANCH worktrees onto origin/main ($STRATEGY strategy)"
echo ""

updated=0
skipped_dirty=0
skipped_uptodate=0
conflicts=0

for worktree_dir in "$TASK_DIR"/*/; do
  [[ -d "$worktree_dir" ]] || continue
  repo=$(basename "$worktree_dir")
  REPO_PATH="$REPOS_ROOT/$repo"

  [[ -d "$REPO_PATH/.git" ]] || { echo "⚠️  $repo has no main clone at $REPO_PATH — skipping"; continue; }

  echo "=== $repo ==="

  echo "  → Fetching origin..."
  if [[ "$DRY_RUN" != true ]]; then
    git -C "$REPO_PATH" fetch origin --quiet --prune
    safe_update_main "$REPO_PATH" "$repo"
  fi

  # Distance from origin/main
  behind=$(git -C "$worktree_dir" rev-list --count HEAD..origin/main 2>/dev/null || echo "?")
  ahead=$(git -C "$worktree_dir" rev-list --count origin/main..HEAD 2>/dev/null || echo "?")

  if [[ "$behind" == "0" ]]; then
    echo "  ✓ Already up to date with origin/main (ahead $ahead)"
    skipped_uptodate=$((skipped_uptodate + 1))
    continue
  fi

  # WIP guard
  if [[ -n "$(git -C "$worktree_dir" status --porcelain)" ]]; then
    echo "  ⚠️  Uncommitted changes in worktree — skipping (behind $behind, ahead $ahead)"
    echo "     commit/stash first, then re-run: ./sync-task.sh $BRANCH"
    skipped_dirty=$((skipped_dirty + 1))
    continue
  fi

  echo "  → $STRATEGY onto origin/main (behind $behind, ahead $ahead)"

  if [[ "$DRY_RUN" == true ]]; then
    continue
  fi

  if [[ "$STRATEGY" == "rebase" ]]; then
    if git -C "$worktree_dir" rebase --quiet origin/main; then
      echo "  ✓ Rebased"
      updated=$((updated + 1))
    else
      echo "  ❌ Rebase conflict — aborting cleanly. Resolve manually in $worktree_dir"
      git -C "$worktree_dir" rebase --abort 2>/dev/null || true
      conflicts=$((conflicts + 1))
    fi
  else
    if git -C "$worktree_dir" merge --quiet --no-edit origin/main; then
      echo "  ✓ Merged"
      updated=$((updated + 1))
    else
      echo "  ❌ Merge conflict — aborting cleanly. Resolve manually in $worktree_dir"
      git -C "$worktree_dir" merge --abort 2>/dev/null || true
      conflicts=$((conflicts + 1))
    fi
  fi
done

echo ""
echo "Summary: $updated updated · $skipped_uptodate up-to-date · $skipped_dirty skipped (WIP) · $conflicts conflicts"
[[ $conflicts -gt 0 ]] && exit 2 || exit 0
