# git-wt

*Git external commands for a worktree-first workflow.*

Small wrappers around git that enforce one simple repo layout: a bare repo
with every worktree as a direct sibling.

```sh
# `git seed` is a worktree-first `git clone`. Just pass it a URL.
git seed git@github.com:user/project.git

# `git wt-bud` puts a branch in a worktree, growing one if it isn't there yet.
#
# worktree name      (optional) new branch created off existing
#           |          |
#           v          v
git wt-bud wt1 main feature
#               ^
#               |
#         existing branch to check out
```

Those two commands produce:

```
project/
├── .git/        <- bare repo  (created by `git seed`)
├── base/        <- worktree   (created by `git seed`)
└── wt1/         <- worktree   (created by `git wt-bud`)
```

| Command | Purpose |
| --- | --- |
| `git seed` | Clone a repo and grow its first worktree in one step |
| `git wt-bud` | Put a branch in a worktree, growing the worktree if needed |
| `git wt-clip` | Clip a worktree off, or with `-k` clip off only its branch |
| `git wt-sync` | Bring a parked worktree up to date with the default branch |
| `git wt-setup` | Run a project's `.wt-setup/setup` hook in a worktree |

`git wt-clip -k` is how you put a worktree on ice without tearing it down. A
worktree holds its branch hostage since a branch can only exist in one
worktree at a time. `-k` clips off the branch instead of the worktree,
leaving a detached HEAD, so the branch is free to check out elsewhere
or delete while everything created by `git wt-setup` stays around.
`git wt-bud` buds a branch back on:

```sh
git wt-clip -k wt1              # park it; its branch is free to delete
git wt-bud wt1 main feature     # months later, back to work in wt1
```

A parked worktree is frozen at the commit it was clipped at — a detached HEAD
is a commit, not a ref, so fetching never moves it. `git wt-sync` is what
brings one forward:

```sh
git wt-sync wt1                 # fetch, then advance wt1 to mainline
```

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
rm ~/.local/bin/git-{seed,wt-bud,wt-clip,wt-setup}
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

### `git wt-bud`

```
git wt-bud [-f] <worktree_name> <branch>               # check out an existing branch
git wt-bud [-f] <worktree_name> <branch> <new_branch>  # create new_branch off branch
```

```sh
git wt-bud wt1 main             # main checked out at <project_root>/wt1
git wt-bud wt1 main feature     # branch "feature" off main at <project_root>/wt1
```

`<worktree_name>` is a name, not a path: it's joined onto the project root, so
you get the same worktree no matter where in the repo you run the command
from. Afterwards the branch's upstream is set to `origin/<branch>` if that
remote branch exists.

A worktree that's already there is not created again — the branch is checked out
in it where it stands. That's what makes [`git wt-clip -k`](#git-wt-clip) worth
using: a parked worktree keeps its `node_modules`, its `.venv`, its `.env`, and
budding a branch back on costs nothing.

```sh
git wt-clip -k wt1              # park wt1, freeing its branch
git wt-bud wt1 main feature     # months later, back to work in wt1
```

Nothing has to be parked first. Budding onto a worktree that's on a branch
already is just a checkout, and budding the branch it's already on is a no-op
that prints the path and exits 0 — so re-running the same command is safe.

`-f` is only about an existing worktree: it checks out into one with modified or
untracked files, discarding them. Without it, either is an error and nothing
changes. A brand-new worktree has nothing to discard, so `-f` does nothing
there.

A branch checked out in *another* worktree is an error — git allows a branch in
only one worktree at a time. That's the restriction `git wt-clip -k` exists to
work around; park the other worktree first.

Growing the worktree is all this does; preparing it is `git wt-setup`. A
worktree that was parked rather than removed was already prepared, so there's
usually nothing left to run.

### `git wt-clip`

```
git wt-clip [-f] <worktree_name>                       # clip the worktree off
git wt-clip -k [-f] [-b <commit-ish>] <worktree_name>  # clip off only its branch
```

```sh
git wt-clip wt1        # remove <project_root>/wt1
git wt-clip -f base    # remove the locked base worktree
git wt-clip -k wt1     # keep wt1, free its branch
```

The counterpart to `git wt-bud`, taking a name the same way. Only the worktree
is removed; its branch is left alone.

`-f` is required for a worktree that is locked or has modified or untracked
files; without it, either is an error and nothing is removed. Since `git seed`
locks `base`, removing the default worktree takes `-f` on purpose.

The project root is printed on stdout, which is where you want to be if you
just removed the worktree you were standing in:

```sh
cd "$(git wt-clip wt1)"
```

#### `-k`: keep the worktree, clip off its branch

A branch can only be checked out in one worktree at a time, so a worktree
sitting idle on a branch holds that branch hostage: you can't check it out
elsewhere and you can't delete it. Removing the worktree frees the branch, but
it also throws away that worktree's `node_modules`, its `.venv`, its `.env` —
every slow thing `git wt-setup` did, which you then pay for again.

`-k` clips off the branch instead of the worktree. It detaches HEAD, so the
worktree keeps no branch checked out while the directory and everything in it
stays exactly where it is:

```sh
git wt-clip -k wt1       # wt1 keeps its files; its branch is free
git branch -d feature    # ...so this now works
git wt-bud wt1 main feature
```

The detach point defaults to the project's default branch, read from the bare
repo's `HEAD` so repos on `main` and repos on `master` both work without being
told which. `-b` overrides it with any commit-ish, and only means anything
alongside `-k`.

Under `-k`, `-f` covers modified or untracked files and discards them; a lock is
irrelevant, since nothing is being removed. Files a setup hook drops in don't
count as long as they're excluded — see
[design_decisions.md](design_decisions.md#keeping-files-next-to-the-hook).

Two things differ from a removal, because the worktree survives. Stdout is the
worktree's own path rather than the project root — there's no need to `cd` out
of a directory that still exists. And a worktree that isn't there is an error
rather than a no-op: there is nothing to keep. Clipping the branch off a
worktree that already has a detached HEAD is a no-op that prints the path and
exits 0.

The branch that was clipped off is reported with its short SHA, which is what
you need if you delete it and later want it back:

```
$ git wt-clip -k wt1
Worktree /home/you/code/project_a/wt1 kept; branch 'feature' (ff74ab3) is free.
  delete it:   git branch -d feature
  put it back: git wt-bud wt1 feature
```

`git worktree list` is how you see which worktrees are parked; they show up as
`(detached HEAD)`.

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
git wt-bud wt1 main
git -C wt1 wt-setup
```

The hook runs with the worktree as its working directory, so relative paths
land inside it, and its exit status becomes the command's. Don't skip the
`chmod +x`: the hook is executed, not sourced, so a `setup` that isn't
executable is an error rather than an absent hook.

`.wt-setup/` is also a good home for the untracked files each worktree needs,
like a `.env` or a local config override, with the hook copying or symlinking
them in. See [design_decisions.md](design_decisions.md#keeping-files-next-to-the-hook).

### `git wt-sync`

```
git wt-sync [-n] [-f] [<worktree_name>]                  # sync to the default branch
git wt-sync [-n] [-f] -b <commit-ish> [<worktree_name>]  # re-park somewhere else
```

```sh
git wt-sync         # sync the worktree you're standing in
git wt-sync wt1     # sync <project_root>/wt1
git wt-sync -n wt1  # no fetch; something else already did one
```

`git wt-clip -k` parks a worktree by detaching its HEAD at the default branch,
and a detached HEAD is a commit rather than a ref — it never moves again on its
own. Fetching `origin/main` a hundred times leaves a parked worktree exactly
where it stood the day it was clipped. This is the command that moves it
forward.

One worktree: the one you name, or the one you're standing in when you name
nothing, the same default `git wt-setup` uses. Nothing else in the project is
touched.

It syncs to `origin/<default branch>`, not the local one. In this layout the
local default branch is usually the stale copy: a plain fetch updates
`refs/remotes/origin/*` and nothing pulls the bare repo's own branches.

```
$ git wt-sync wt1
Worktree /home/you/code/project_a/wt1 synced: 3a4f2c1 -> 9b2e105 (origin/main).
```

A worktree with a branch checked out is live work, so it's reported and left
alone — `git wt-bud` and `git pull` are the commands for those. That plus
"already up to date" are the two no-ops, and both exit 0, so re-running this is
safe and pointing it at live work by mistake isn't a failure:

```
$ git wt-sync
Worktree /home/you/code/project_a/base is on branch 'main', not parked; nothing to sync.
```

Refusing to move a worktree *is* an error. A worktree is only ever advanced
along the target's own history, so one deliberately parked at a release tag
with `git wt-clip -k -b` stays put:

```
$ git wt-sync wt2
Error: /home/you/code/project_a/wt2 is parked at 7c13d80, which is not on origin/main
Use -b origin/main to move it there anyway.
```

`-f` discards a dirty worktree's files the way it does in `git wt-bud` and
`git wt-clip`, and `-b` re-parks somewhere else — which is also the only way to
move a worktree that is *already* parked, since `git wt-clip -k` on a worktree
with no branch is a no-op.

## Completions

`completions/` holds zsh and bash completions: `git wt-bud` completes the
`<branch>` argument, and all four commands complete the repo's worktrees.
`git wt-clip -k` narrows its list to worktrees that still have a branch to clip
off, `git wt-sync` narrows its list the other way, to the parked ones it can
act on, and under zsh `git wt-bud` groups the parked worktrees first, since
those are the ones waiting for a branch.

```
$ git wt-bud wt <TAB>
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
for c in git-wt-bud git-wt-clip git-wt-setup; do
    ln -sfn ~/.local/share/git-wt/completions/bash/$c \
            ~/.local/share/bash-completion/completions/$c
done
```

Without bash-completion, source them from `~/.bashrc` after git's own
completion:

```sh
source ~/.local/share/git-wt/completions/bash/git-wt-bud
source ~/.local/share/git-wt/completions/bash/git-wt-clip
source ~/.local/share/git-wt/completions/bash/git-wt-setup
```

</details>
