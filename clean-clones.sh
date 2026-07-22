#!/bin/zsh
# Usage: ./clean-clones.sh [--dry-run] [--purge-untracked]
# Resets every main clone under REPOS_ROOT to match origin/<primary-branch>.
#
# A "main clone" is a top-level directory under REPOS_ROOT with a .git
# directory (not a file — worktrees have a .git file that points elsewhere).
# Worktrees under REPOS_ROOT/worktrees/ and REPOS_ROOT/studies/ are skipped.
#
# For each main clone:
#   - Fetches origin
#   - Determines primary branch from origin/HEAD (fallbacks: main, master)
#   - If HEAD is on the primary branch → git reset --hard origin/<primary>
#   - If HEAD is on some other branch → skips with a warning (assumes an
#     in-progress PR checkout you don't want nuked)
#
# --dry-run          print what would happen without changing anything
# --purge-untracked  also `git clean -fd` after the reset (removes untracked
#                    files and directories — destructive; use only when you're
#                    sure the invariant "nothing on main to commit" holds)

set -e

REPOS_ROOT=${REPOS_ROOT:-~/GoProjects}

DRY_RUN=false
PURGE_UNTRACKED=false
for arg in "$@"; do
  case "$arg" in
    --dry-run|-n) DRY_RUN=true ;;
    --purge-untracked) PURGE_UNTRACKED=true ;;
    -h|--help)
      sed -n '2,21p' "$0"
      exit 0
      ;;
  esac
done

if [[ "$DRY_RUN" == true ]]; then
  echo "🔍 DRY RUN — no changes will be made"
fi
if [[ "$PURGE_UNTRACKED" == true ]]; then
  echo "🧹 --purge-untracked enabled — untracked files will be removed"
fi
echo ""

reset_count=0
skip_count=0
error_count=0
already_clean_count=0

for entry in "$REPOS_ROOT"/*(/N); do
  repo_name=$(basename "$entry")

  # Skip the worktrees / studies parent dirs — those hold worktrees, not clones
  [[ "$repo_name" == "worktrees" || "$repo_name" == "studies" ]] && continue

  # Main clones have .git as a directory. Worktrees would have .git as a file
  # pointing to the shared gitdir — those live under worktrees/ anyway.
  [[ -d "$entry/.git" ]] || continue

  echo "→ $repo_name"

  # Determine the primary branch. Prefer origin/HEAD, fall back to main/master.
  primary=""
  if origin_head=$(git -C "$entry" symbolic-ref refs/remotes/origin/HEAD 2>/dev/null); then
    primary="${origin_head##*/}"
  fi
  if [[ -z "$primary" ]]; then
    for candidate in main master; do
      if git -C "$entry" show-ref --quiet --verify "refs/remotes/origin/$candidate"; then
        primary="$candidate"
        break
      fi
    done
  fi
  if [[ -z "$primary" ]]; then
    echo "   ⚠️  no origin/HEAD, main, or master — skipping"
    error_count=$((error_count + 1))
    continue
  fi

  # Fetch quietly. If it fails (no network, bad remote, etc.), skip.
  if ! git -C "$entry" fetch origin --quiet --prune 2>/dev/null; then
    echo "   ⚠️  fetch failed — skipping"
    error_count=$((error_count + 1))
    continue
  fi

  current_branch=$(git -C "$entry" symbolic-ref --short -q HEAD 2>/dev/null || echo "")

  if [[ "$current_branch" != "$primary" ]]; then
    echo "   ⏭  on branch '$current_branch' (not $primary) — skipping (respecting in-progress work)"
    skip_count=$((skip_count + 1))
    continue
  fi

  # Compare local HEAD + index against origin/<primary>. Also detect untracked
  # files separately from tracked-dirt so the summary is meaningful.
  local_head=$(git -C "$entry" rev-parse HEAD)
  origin_head=$(git -C "$entry" rev-parse "origin/$primary")
  # `-uno` = don't list untracked; captures tracked-file dirt only
  tracked_lines=$(git -C "$entry" status --porcelain -uno | wc -l | tr -d ' ')
  untracked_lines=$(git -C "$entry" status --porcelain --untracked-files=normal | grep -c '^??' | tr -d ' ')

  # If everything matches AND no untracked files (or we're not purging them),
  # skip work.
  needs_reset=false
  needs_purge=false
  [[ "$local_head" != "$origin_head" || "$tracked_lines" -gt 0 ]] && needs_reset=true
  [[ "$PURGE_UNTRACKED" == true && "$untracked_lines" -gt 0 ]] && needs_purge=true

  if [[ "$needs_reset" != true && "$needs_purge" != true ]]; then
    if [[ "$untracked_lines" -gt 0 ]]; then
      echo "   ✓ tracked files clean at origin/$primary ($untracked_lines untracked ignored; use --purge-untracked to remove)"
    else
      echo "   ✓ already clean at origin/$primary"
    fi
    already_clean_count=$((already_clean_count + 1))
    continue
  fi

  # Report what will change
  if [[ "$local_head" != "$origin_head" ]]; then
    behind_ahead=$(git -C "$entry" rev-list --left-right --count "origin/$primary...HEAD" 2>/dev/null || echo "? ?")
    echo "   ↺ HEAD $local_head → origin/$primary $origin_head (behind/ahead: $behind_ahead)"
  fi
  if [[ "$tracked_lines" -gt 0 ]]; then
    echo "   ↺ discarding $tracked_lines dirty tracked entries"
  fi
  if [[ "$needs_purge" == true ]]; then
    echo "   🧹 removing $untracked_lines untracked entries"
    if [[ "$DRY_RUN" == true ]]; then
      # Preview what would be cleaned
      git -C "$entry" clean -nd | sed 's/^/      /' | head -15
    fi
  fi

  if [[ "$DRY_RUN" == true ]]; then
    if [[ "$needs_reset" == true ]]; then
      echo "   (dry-run: would run git reset --hard origin/$primary)"
    fi
    if [[ "$needs_purge" == true ]]; then
      echo "   (dry-run: would run git clean -fd)"
    fi
    reset_count=$((reset_count + 1))
    continue
  fi

  reset_ok=true
  if [[ "$needs_reset" == true ]]; then
    if ! git -C "$entry" reset --hard "origin/$primary" --quiet; then
      echo "   ❌ reset failed"
      reset_ok=false
    fi
  fi
  if [[ "$reset_ok" == true && "$needs_purge" == true ]]; then
    if ! git -C "$entry" clean -fd --quiet; then
      echo "   ❌ clean failed"
      reset_ok=false
    fi
  fi

  if [[ "$reset_ok" == true ]]; then
    echo "   ✓ reset to origin/$primary$([[ "$needs_purge" == true ]] && echo " + purged untracked")"
    reset_count=$((reset_count + 1))
  else
    error_count=$((error_count + 1))
  fi
done

echo ""
echo "Summary:"
echo "  reset:         $reset_count"
echo "  already clean: $already_clean_count"
echo "  skipped:       $skip_count"
echo "  errors:        $error_count"
