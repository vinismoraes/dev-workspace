#!/bin/zsh
# Usage: ./quick-start-repo.sh REPO_NAME [--module module/path] [--no-commit]
# Creates a local Go repo scaffold under $REPOS_ROOT (default: ~/GoProjects).

set -e

REPOS_ROOT=${REPOS_ROOT:-~/GoProjects}

REPO_NAME=""
MODULE_PATH=""
NO_COMMIT=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --module)
      MODULE_PATH="$2"
      shift 2
      ;;
    --no-commit)
      NO_COMMIT=true
      shift
      ;;
    -h|--help)
      echo "Usage: $0 REPO_NAME [--module module/path] [--no-commit]"
      exit 0
      ;;
    *)
      if [[ -z "$REPO_NAME" ]]; then
        REPO_NAME="$1"
      else
        echo "Unknown argument: $1"
        echo "Usage: $0 REPO_NAME [--module module/path] [--no-commit]"
        exit 1
      fi
      shift
      ;;
  esac
done

if [[ -z "$REPO_NAME" ]]; then
  echo "Usage: $0 REPO_NAME [--module module/path] [--no-commit]"
  exit 1
fi

if [[ -z "$MODULE_PATH" ]]; then
  MODULE_PATH="example.com/$REPO_NAME"
fi

REPO_PATH="$REPOS_ROOT/$REPO_NAME"

if [[ -e "$REPO_PATH" && ! -d "$REPO_PATH/.git" ]]; then
  echo "❌ Path exists but is not a git repo: $REPO_PATH"
  exit 1
fi

mkdir -p "$REPO_PATH"
cd "$REPO_PATH"

if [[ ! -d .git ]]; then
  git init -b main
  echo "✓ Initialized git repository"
fi

if [[ ! -f .gitignore ]]; then
  cat > .gitignore <<'EOF'
bin/
dist/
*.log
.DS_Store
EOF
fi

if [[ ! -f README.md ]]; then
  cat > README.md <<EOF
# $REPO_NAME

Quick-start scaffold.
EOF
fi

if [[ ! -f go.mod ]]; then
  cat > go.mod <<EOF
module $MODULE_PATH

go 1.22
EOF
fi

if [[ ! -f main.go ]]; then
  cat > main.go <<'EOF'
package main

import "fmt"

func main() {
  fmt.Println("hello")
}
EOF
fi

if [[ "$NO_COMMIT" != true ]]; then
  if ! git rev-parse --verify HEAD >/dev/null 2>&1; then
    git add .
    git commit -m "init repo scaffold"
    echo "✓ Created initial commit"
  fi
fi

# Ensure origin/main exists for new-task.sh worktree creation.
if ! git remote get-url origin >/dev/null 2>&1; then
  git remote add origin "$REPO_PATH"
fi

git fetch origin --quiet --prune || true

echo ""
echo "✅ Repo ready: $REPO_PATH"
echo "   Module: $MODULE_PATH"
echo ""
echo "Next: ./new-task.sh TICKET-1234 $REPO_NAME"