#!/bin/zsh
# Usage: ./sync-main-clones.sh [--quiet]
# For every main clone under $REPOS_ROOT, fetch origin and safely update the
# local `main` ref (respects checked-out state — never desyncs a working tree).
#
# Intended to be run periodically (e.g. via launchd every 30 min) so your
# origin/main view is always fresh across all repos.
#
# Skips: `worktrees/` and `studies/` (those are worktrees, not main clones).

REPOS_ROOT=${REPOS_ROOT:-~/GoProjects}
QUIET=false
[[ "$1" == "--quiet" || "$1" == "-q" ]] && QUIET=true

source "${0:A:h}/lib/git-helpers.sh"

log() { [[ "$QUIET" != true ]] && echo "$@"; }

for entry in "$REPOS_ROOT"/*(/N); do
  repo_name=$(basename "$entry")
  [[ "$repo_name" == "worktrees" || "$repo_name" == "studies" ]] && continue
  [[ -d "$entry/.git" ]] || continue

  log "→ $repo_name"
  if ! git -C "$entry" fetch origin --quiet --prune 2>/dev/null; then
    log "  ⚠️  fetch failed (offline?) — skipping"
    continue
  fi
  # safe_update_main writes its own warnings; only silence success
  if [[ "$QUIET" == true ]]; then
    safe_update_main "$entry" "$repo_name" >/dev/null 2>&1
  else
    safe_update_main "$entry" "$repo_name"
  fi
done
