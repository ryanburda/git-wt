# git-wt

*Git external commands for a worktree-first workflow.*

Small wrappers around git that enforce one simple repo layout: a bare repo
with every worktree as a direct sibling.

```sh
# `git seed` is a worktree-first `git clone`. Just pass it a URL.
git seed git@github.com:user/project.git

# `git wt-add` puts a branch in a worktree, creating one if it isn't there yet.
#
# worktree name      (optional) new branch created off existing
#           |          |
#           v          v
git wt-add wt1 main feature
#               ^
#               |
#         existing branch to check out
```

Those two commands produce:

```
project/
├── .git/        <- bare repo  (created by `git seed`)
├── base/        <- worktree   (created by `git seed`)
└── wt1/         <- worktree   (created by `git wt-add`)
```

| Command | Purpose |
| --- | --- |
| `git seed` | Clone a repo and create its first worktree in one step |
| `git wt-add` | Put a branch in a worktree, creating the worktree if needed |
| `git wt-park` | Park a worktree at the default branch, freeing its branch |
| `git wt-setup` | Run a project's `.wt-setup/setup` hook in a worktree |

`git wt-park` is how you put a worktree on ice without tearing it down. A
worktree holds its branch hostage since a branch can only exist in one
worktree at a time. Parking detaches HEAD at the latest commit on the default
branch rather than removing anything, so the branch is free to check out
elsewhere or delete while everything created by `git wt-setup` stays around.
`git wt-add` puts a branch back on:

```sh
git wt-park wt1                 # park it; its branch is free to delete
git wt-add wt1 main feature     # months later, back to work in wt1
```

Re-running it is also how a parked worktree moves forward. A detached HEAD is
a commit, not a ref, so fetching never moves one on its own:

```sh
git wt-park wt1                 # fetch, then advance wt1 to mainline
```

Removing a worktree outright is `git worktree remove`, which already does that
job well. The layout is the point: every worktree is a direct child of the
project root, so the path it wants is never ambiguous.

See the [design_decisions](design_decisions.md) doc for implementation
specific details.

See the [lazygit](docs/lazygit.md) doc to drive these commands from lazygit's
worktrees panel.

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

The project's `.wt-setup/setup` hook is *not* run; that's
[`git wt-setup`](#git-wt-setup).

### `git wt-add`

```
git wt-add [-f] <worktree_name> <branch>               # check out an existing branch
git wt-add [-f] <worktree_name> <branch> <new_branch>  # create new_branch off branch
```

```sh
git wt-add wt1 main             # main checked out at <project_root>/wt1
git wt-add wt1 main feature     # branch "feature" off main at <project_root>/wt1
```

`<worktree_name>` is a name, not a path: it's joined onto the project root, so
you get the same worktree no matter where in the repo you run the command
from. Afterwards the branch's upstream is set to `origin/<branch>` if that
remote branch exists.

A worktree that's already there is not created again — the branch is checked out
in it where it stands. That's what makes [`git wt-park`](#git-wt-park) worth
using: a parked worktree keeps its `node_modules`, its `.venv`, its `.env`, and
putting a branch back on costs nothing.

```sh
git wt-park wt1                 # park wt1, freeing its branch
git wt-add wt1 main feature     # months later, back to work in wt1
```

Nothing has to be parked first. Running it against a worktree that's on a branch
already is just a checkout, and naming the branch it's already on is a no-op
that prints the path and exits 0 — so re-running the same command is safe.

`-f` is only about an existing worktree: it checks out into one with modified or
untracked files, discarding them. Without it, either is an error and nothing
changes. A brand-new worktree has nothing to discard, so `-f` does nothing
there.

A branch checked out in *another* worktree is an error — git allows a branch in
only one worktree at a time. That's the restriction `git wt-park` exists to
work around; park the other worktree first.

Creating the worktree is all this does; preparing it is `git wt-setup`. A
worktree that was parked rather than removed was already prepared, so there's
usually nothing left to run.

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

The counterpart to `git wt-add`, taking a name the same way. Nothing is
removed — removing a worktree is `git worktree remove`, which already does
that job.

A branch can only be checked out in one worktree at a time, so a worktree
sitting idle on a branch holds that branch hostage: you can't check it out
elsewhere and you can't delete it. Removing the worktree frees the branch, but
it also throws away that worktree's `node_modules`, its `.venv`, its `.env` —
every slow thing `git wt-setup` did, which you then pay for again.

So it detaches HEAD instead. The worktree keeps no branch checked out while the
directory and everything in it stays exactly where it is:

```sh
git wt-park wt1          # wt1 keeps its files; its branch is free
git branch -d feature    # ...so this now works
git wt-add wt1 main feature
```

The branch that was freed is reported with its short SHA, which is what
you need if you delete it and later want it back:

```
$ git wt-park wt1
Worktree /home/you/code/project_a/wt1 kept; branch 'feature' (ff74ab3) is free.
  delete it:   git branch -d feature
  put it back: git wt-add wt1 feature
```

`git worktree list` is how you see which worktrees are parked; they show up as
`(detached HEAD)`.

#### Where it parks

At `origin/<default branch>` — the latest commit on mainline, fetched first
unless `-n` says not to. In this layout the local default branch is usually the
stale copy: a plain fetch updates `refs/remotes/origin/*` and nothing pulls the
bare repo's own branches. Which branch is the default is read from the bare
repo's `HEAD`, so repos on `main` and repos on `master` both work without being
told which. `-b` overrides the target with any commit-ish.

Re-running the command is how a parked worktree moves forward. A detached HEAD
is a commit rather than a ref, so it never advances on its own — fetching
`origin/main` a hundred times leaves a parked worktree exactly where it stood
the day it was parked:

```
$ git wt-park wt1
Worktree /home/you/code/project_a/wt1 moved: 3a4f2c1 -> 9b2e105 (origin/main).
```

That also means a worktree parked deliberately with `-b`, at a release tag or
an older commit, gets pulled onto mainline by a bare `git wt-park`. The command
always does what it says; `-b` is how you park it back.

A worktree already parked at the commit it would be moved to is a no-op that
prints the path and exits 0, so re-running this is safe.

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
them in. See [design_decisions.md](design_decisions.md#keeping-files-next-to-the-hook).

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
