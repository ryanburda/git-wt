# git-wt

*Git external commands for a worktree-first workflow.*

Small wrappers around git that enforce a simple bare repo layout.

```sh
# `git seed` is a worktree-first `git clone`. Just pass it a URL.
git seed <url>

# `git wt-add` creates a new worktree.
git wt-add <worktree-name> <existing-branch> [<new-branch>]
```

Example usage:
```sh
git seed git@github.com:user/project.git
cd project
git wt-add wt1 main feature
```
The commands above produce the following repo layout:

```
./project/
├── .git/    <- bare repo              (created by `git seed`)
├── base/    <- worktree on `main`     (created by `git seed`)
└── wt1/     <- worktree on `feature`  (created by `git wt-add`)
```

`git seed` will:
- create the bare repo (`.git/`)
- create and lock your first worktree (called `base` by default)

Future `git wt-add` calls put your worktrees alongside the one created by `git seed`.

## Why enforce a flat repo layout

Git gives every worktree an internal name and keeps its metadata under the
bare repo at `.git/worktrees/<name>/`. The name is the last path segment of
the worktree. When two worktrees share a last segment, git appends a counter
rather than complaining:

```sh
git worktree add --detach ~/scratch/a/feature
git worktree add --detach ~/scratch/b/feature
```
```
.git/worktrees/
├── feature/     <- ~/scratch/a/feature
└── feature1/    <- ~/scratch/b/feature
```

Nothing breaks, but the short name is now ambiguous. This makes
other commands error out with unhelpful messages:

```sh
$ git worktree remove feature
fatal: 'feature' is not a working tree
```

The flat layout sidesteps all of this by construction. Every worktree is a
direct child of the project root. A directory can't hold two entries with the
same name, so last path segments, and therefore internal names, are unique.
Every worktree answers to its own directory name.

### Names, not paths

For the same reason, all of the commands in this project treat `<worktree_name>`
as a name joined onto the project root derived from the bare repo's location,
never onto the current directory. The same command run from a nested subdirectory,
or from a *different* worktree, acts on the same place.


## Install

```sh
curl -fsSL https://raw.githubusercontent.com/ryanburda/git-wt/main/install.sh | sh
```

The script clones this repo to `~/.local/share/git-wt` and symlinks the
commands into `~/.local/bin`. Re-running it updates the checkout in place.

The commands are zsh scripts, so zsh must be installed. The installer itself
is POSIX `sh`.

Make sure `~/.local/bin` is on your `PATH` (the installer warns if it isn't):

```sh
export PATH="$HOME/.local/bin:$PATH"
```

Verify by running any command with no arguments; it prints its usage:

```sh
git seed
```

Overrides:

| Variable | Default |
| --- | --- |
| `GIT_WT_HOME` | `~/.local/share/git-wt` (or `$XDG_DATA_HOME/git-wt`) |
| `BIN_DIR` | `~/.local/bin` |

```sh
curl -fsSL https://raw.githubusercontent.com/ryanburda/git-wt/main/install.sh | BIN_DIR=~/bin sh
```

### Uninstall

Delete the symlinks and the checkout, plus any completion links from the
section below:

```sh
rm ~/.local/bin/git-{seed,wt-add,wt-park,wt-setup}
rm -rf ~/.local/share/git-wt
```

## Usage

### `git seed`

A worktree-first `git clone`: clones a bare repo and creates its first
worktree in one step.

```
git seed [-b <branch>] [-w <worktree_name>] [-u] <repo_url> [<root_path>]
```

| Flag | Default | Meaning |
| --- | --- | --- |
| `-b <branch>` | the remote's default branch | branch to check out |
| `-w <name>` | `base` | worktree directory name |
| `-u` | lock | leave the worktree unlocked |

```sh
git seed git@github.com:user/project_a.git
```
```
project_a/
├── .git/          <- bare repo
└── base/          <- worktree, on the remote's default branch, locked
```

With no `<root_path>`, the project name is derived from the URL and created
under the current directory, matching `git clone`. The branch comes from the
remote's `HEAD`, so repos on `main` and repos on `master` both work without
being told which. The worktree is locked, marking it as the project's
"default" worktree.

The project's `.wt-setup/setup` hook is *not* run. See [`git wt-setup`](#git-wt-setup).

### `git wt-add`

```
git wt-add [-f] <worktree_name> <branch>               # check out an existing branch
git wt-add [-f] <worktree_name> <branch> <new_branch>  # create new_branch off branch
```

```sh
git wt-add wt1 main             # main checked out at <project_root>/wt1
git wt-add wt1 main feature     # branch "feature" off main at <project_root>/wt1
```

`<worktree_name>` is a name, not a path. It's joined onto the project root, so
you get the same worktree no matter where in the repo you run the command
from.

Calling `git wt-add` with a worktree name that already exists **does not** recreate it.
Instead the branch is checked out on the existing worktree. This is helpful when resurrecting
worktrees that were parked using [`git wt-park`](#git-wt-park).

### `git wt-park`

```
git wt-park [-n] [-f] [<worktree_name>]                  # park it at mainline
git wt-park [-n] [-f] -b <commit-ish> [<worktree_name>]  # park somewhere else
```

```sh
git wt-park            # park the worktree you're standing in
git wt-park wt1        # park <project_root>/wt1
git wt-park -n wt1     # no fetch; something else already did one
```

A branch can only be checked out in one worktree at a time, so a worktree
sitting idle on a branch holds that branch hostage. You can't check it out
elsewhere and you can't delete it. Removing the worktree frees the branch, but
it also throws away anything that was set up using [`git wt-setup`](#git-wt-setup).

For cases like these were you want to free the branch and not remove the worktree,
you can use `git wt-park`. This puts the worktree in a detached HEAD state, freeing
the branch while also preserving your set up worktree for later use.

```sh
git wt-park wt1          # wt1 keeps its files; its branch is free
git branch -d feature    # ...so this now works
git wt-add wt1 main feature
```

#### Arguments

`-n` skips the fetch, for callers that already did one — a lazygit binding that
fetches first, a loop over several worktrees — so the network is paid for once
rather than once per call.

`-f` covers modified or untracked files and discards them; without it, either
one is an error and nothing changes. A lock is irrelevant, since nothing is
being removed: the `base` worktree `git seed` locks parks like any other. Files
a setup hook drops in don't count as long as they're excluded — see
[design_decisions.md](design_decisions.md#keeping-files-next-to-the-hook).

`<worktree_name>` is optional. Without it, the command acts on the worktree
you're standing in, the same default `git wt-setup` uses. A worktree that isn't
there is an error rather than a no-op: there is nothing to park.

The worktree's own path is printed on stdout:

```sh
cd "$(git wt-park wt1)"
```

### `git wt-setup`

```
git wt-setup [<worktree_path>]
```

Runs `<project_root>/.wt-setup/setup` from inside the given worktree, or the
current one if no path is given.

The hook is yours to write. Nothing creates it for you, and since
`.wt-setup/` is untracked it doesn't arrive with a clone either. Until you put
a file there, the command is a successful no-op:

```
$ git wt-setup
No setup hook at /home/you/code/project_a/.wt-setup/setup; nothing to do.
```

Installing a hook is: make the directory, write the file, mark it executable.
For most projects the file is one line:

```sh
mkdir -p ~/code/project_a/.wt-setup
cat > ~/code/project_a/.wt-setup/setup <<'EOF'
#!/bin/sh
npm install
EOF
chmod +x ~/code/project_a/.wt-setup/setup
```

Every new worktree now gets its own `node_modules/` without you remembering to
install anything:

```sh
git wt-add wt1 main
git -C wt1 wt-setup
```

The hook runs with the worktree as its working directory, so relative paths
land inside it, and its exit status becomes the command's. Don't skip the
`chmod +x`: the hook is executed, not sourced, so a `setup` that isn't
executable is an error rather than an absent hook.

`.wt-setup/` is also a good home for the untracked files each worktree needs,
like a `.env` or a local config override, with the hook copying or symlinking
them in.

## Completions

`completions/` holds zsh and bash completions: `git wt-add` completes the
`<branch>` argument, and all three `wt-` commands complete the repo's
worktrees. Under zsh `git wt-add` groups the parked worktrees first, since
those are the ones waiting for a branch.

```
$ git wt-add wt <TAB>
feature/login  local-only  main  other  release-2.0
```

The installer leaves these files at `~/.local/share/git-wt/completions/`;
each shell needs one line to pick them up.

<details>
<summary>zsh</summary>

Source `git-wt.zsh` from `~/.zshrc`:

```zsh
source ~/.local/share/git-wt/completions/zsh/git-wt.zsh
```

This works even after `compinit` has run: instead of relying on `compinit` to
scan `fpath`, it autoloads the completion functions itself. It also registers
descriptions, so the commands show up in `git <TAB>`.

If your `.zshrc` sources a directory of extension scripts, symlink it in
instead:

```zsh
ln -s ~/.local/share/git-wt/completions/zsh/git-wt.zsh ~/.zsh/zshrc_extensions/git-wt.zsh
```

</details>

<details>
<summary>bash</summary>

With bash-completion installed, symlink the files into its user directory and
they are loaded on demand:

```sh
mkdir -p ~/.local/share/bash-completion/completions
for c in git-wt-add git-wt-park git-wt-setup; do
    ln -sfn ~/.local/share/git-wt/completions/bash/$c \
            ~/.local/share/bash-completion/completions/$c
done
```

Without bash-completion, source them from `~/.bashrc` after git's own
completion:

```sh
source ~/.local/share/git-wt/completions/bash/git-wt-add
source ~/.local/share/git-wt/completions/bash/git-wt-park
source ~/.local/share/git-wt/completions/bash/git-wt-setup
```

</details>
