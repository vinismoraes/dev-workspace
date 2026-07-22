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
new-task.sh my-feature repo-a repo-b
```

The first argument is the **branch name** — it can be anything: a ticket number (`PCHAT-1234`), a feature name (`add-search`), or an experiment (`experiment-v2`).

This will:
1. Create a worktree for each repo at `$REPOS_ROOT/worktrees/my-feature/<repo>/`
2. Check out a new branch named `my-feature` in each worktree
3. Generate a `.code-workspace` file with all repos as roots
4. Open VS Code with the workspace

If no repos are specified, it defaults to `services`.

### Add a repo mid-task

```bash
add-repo.sh my-feature repo-c
```

Adds a new worktree to an existing task and updates the workspace file.

### Finish a task

```bash
done-task.sh my-feature
```

Removes the worktrees and workspace directory. Remote branches stay intact.

### Absorb latest `main` into an in-flight task

```bash
sync-task.sh my-feature              # rebase (default)
sync-task.sh my-feature --merge      # merge instead of rebase
sync-task.sh my-feature --dry-run    # show what would happen
```

For each worktree of the task: fetches origin, safely fast-forwards local `main`, then rebases (or merges) the task branch onto `origin/main`. Skips any worktree with uncommitted changes and aborts cleanly on conflicts.

### Keep every main clone fresh (background)

```bash
sync-main-clones.sh                  # one-shot, verbose
sync-main-clones.sh --quiet          # one-shot, silent (for launchd/cron)
```

Fetches origin on every top-level clone under `$REPOS_ROOT` and safely updates the local `main` ref (`git merge --ff-only` when clean, plain `update-ref` when `main` isn't checked out, skip-and-warn when the working tree is dirty). Never desyncs a working tree.

Run it periodically to keep `origin/main` fresh so `sync-task.sh` is instant. See [launchd example](#optional-run-sync-main-clonessh-every-30-minutes-via-launchd) below.

### Emergency: reset all main clones to origin

```bash
clean-clones.sh --dry-run            # show what would change
clean-clones.sh                      # reset every main clone to origin/<primary>
clean-clones.sh --purge-untracked    # also `git clean -fd` (destructive)
```

Nuclear option: for every main clone under `$REPOS_ROOT`, `git reset --hard origin/<primary>`. Skips clones that are on a non-primary branch (assumes an in-progress checkout you don't want nuked). Use this if `sync-main-clones.sh` isn't enough to clear up phantom or stuck state.

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
│   └── my-feature/
│       ├── services/            # Worktree on branch my-feature
│       ├── agent-orchestrator/  # Worktree on branch my-feature
│       └── my-feature.code-workspace
├── new-task.sh          → dev-workspace/new-task.sh
├── add-repo.sh          → dev-workspace/add-repo.sh
├── done-task.sh         → dev-workspace/done-task.sh
├── sync-task.sh         → dev-workspace/sync-task.sh
└── sync-main-clones.sh  → dev-workspace/sync-main-clones.sh
```

- Main clones at `$REPOS_ROOT/` are never modified by task scripts — all work happens in worktrees
- Each task gets an isolated directory under `worktrees/`
- The generated `.code-workspace` includes all task repos as workspace roots
- The `services` repo automatically gets `src/el` added as a second workspace root when present
- `sync-main-clones.sh` and the shared `safe_update_main` helper guarantee that fetching + updating `main` on a clone never leaves the working tree stale relative to `HEAD` (which used to produce hundreds of phantom "modifications" in any open VS Code window)

## Configuration

| Variable | Default | Description |
|---|---|---|
| `REPOS_ROOT` | `~/GoProjects` | Directory containing your repo clones |

## Copilot integration

If you use [copilot-prompts](https://github.com/vinismoraes/copilot-prompts), the `task-workflow.instructions.md` instruction teaches Copilot how to invoke these scripts automatically when you say "start a new task" or "I'm done with this task."

## Optional: run `sync-main-clones.sh` every 30 minutes via launchd

Keep every main clone's `origin/main` fresh in the background — so `sync-task.sh` never has to wait on a fetch and your `main`-checked-out windows quietly fast-forward as teammates land PRs.

Create `~/Library/LaunchAgents/com.vinismoraes.sync-main-clones.plist` (replace `PATH_TO_HOME` and the script path if `$REPOS_ROOT` isn't `~/GoProjects`):

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>com.vinismoraes.sync-main-clones</string>
  <key>ProgramArguments</key>
  <array>
    <string>/bin/zsh</string>
    <string>-c</string>
    <string>PATH_TO_HOME/GoProjects/sync-main-clones.sh --quiet</string>
  </array>
  <key>StartInterval</key>
  <integer>1800</integer>
  <key>RunAtLoad</key>
  <true/>
  <key>EnvironmentVariables</key>
  <dict>
    <key>PATH</key>
    <string>/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin</string>
    <key>HOME</key>
    <string>PATH_TO_HOME</string>
  </dict>
  <key>StandardOutPath</key>
  <string>PATH_TO_HOME/Library/Logs/sync-main-clones.log</string>
  <key>StandardErrorPath</key>
  <string>PATH_TO_HOME/Library/Logs/sync-main-clones.log</string>
</dict>
</plist>
```

Load it:

```bash
launchctl load ~/Library/LaunchAgents/com.vinismoraes.sync-main-clones.plist
```

Disable later with `launchctl unload`.

## License

MIT
