# dev-workspace

Git worktree and VS Code multi-root workspace manager for cross-repo tasks.

Start a task across multiple repos with one command — each repo gets its own worktree branch, and VS Code opens a workspace with all of them as roots. When you're done, clean up with another command.

## Quick start

```bash
git clone git@github.com:vinismoraes/dev-workspace.git ~/GoProjects/dev-workspace
cd ~/GoProjects/dev-workspace && ./install.sh
```

This symlinks the scripts into `$REPOS_ROOT` (default: `~/GoProjects`) so they're available from anywhere.

## Usage

### Start a task

```bash
new-task.sh TICKET-1234 repo-a repo-b
```

This will:
1. Create a worktree for each repo at `$REPOS_ROOT/worktrees/TICKET-1234/<repo>/`
2. Check out a new branch named `TICKET-1234` in each worktree
3. Generate a `.code-workspace` file with all repos as roots
4. Open VS Code with the workspace

If no repos are specified, it defaults to `services`.

### Add a repo mid-task

```bash
add-repo.sh TICKET-1234 repo-c
```

Adds a new worktree to an existing task and updates the workspace file.

### Finish a task

```bash
done-task.sh TICKET-1234
```

Removes the worktrees and workspace directory. Remote branches stay intact.

### Bootstrap a new repo

```bash
quick-start-repo.sh my-new-repo --module github.com/user/my-new-repo
```

Creates a local Git repo with an initial `main` branch, `go.mod`, and `main.go`. Then use `new-task.sh` to start working on it.

## How it works

```
~/GoProjects/                    # $REPOS_ROOT
├── services/                    # Main clone (never modified)
├── agent-orchestrator/          # Main clone (never modified)
├── worktrees/
│   └── TICKET-1234/
│       ├── services/            # Worktree on branch TICKET-1234
│       ├── agent-orchestrator/  # Worktree on branch TICKET-1234
│       └── TICKET-1234.code-workspace
├── new-task.sh → dev-workspace/new-task.sh
├── add-repo.sh → dev-workspace/add-repo.sh
└── done-task.sh → dev-workspace/done-task.sh
```

- Main clones at `$REPOS_ROOT/` are never modified — all work happens in worktrees
- Each task gets an isolated directory under `worktrees/`
- The generated `.code-workspace` includes all task repos as workspace roots
- The `services` repo automatically gets `src/el` added as a second workspace root when present

## Configuration

| Variable | Default | Description |
|---|---|---|
| `REPOS_ROOT` | `~/GoProjects` | Directory containing your repo clones |

## Copilot integration

If you use [copilot-prompts](https://github.com/vinismoraes/copilot-prompts), the `task-workflow.instructions.md` instruction teaches Copilot how to invoke these scripts automatically when you say "start a new task" or "I'm done with this task."

## License

MIT
