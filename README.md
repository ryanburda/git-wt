# git-ext

*Git external commands for a worktree-first workflow.*

If you're reading this you already know why worktrees are nice. These are just some small
wrappers around the git commands it make it easier to enforce a simple repo layout.

``` sh
# `git seed` is a worktree-first version of `git clone`.
# Just pass it a URL
#                 |
#                 v
git seed git@github.com:user/project.git

# `git worktree-add` wraps `git worktree add` to enforce the repo structure.
#
#       worktree name     (optional) new branch name created off existing
#                 |         |
#                 v         v
git worktree-add wt1 main feature
#                      ^
#                      |
#                existing branch to check out 
```

Running the commands above results in the folder structure below.

```
../project/
├── .git/        <- bare repo  (created by `git seed`)
├── base/        <- worktree   (created by `git seed`)
└── wt1/         <- worktree   (created by `git worktree-add`)
```

- Similar to `git clone`, the project name is inferred by the URL and is used
to create the top level directory of the repo.
- the `.git` folder contains the bare repo
- the `base` worktree was created and locked by `git seed` to act as your "default" worktree
- the `wt1` worktree exists along side the bare repo and the `base` worktree

### Command overview

| Command | Purpose |
| --- | --- |
| `git seed` | Clone a repo and grow its first worktree in one step |
| `git clone-bare` | Clone a repo as a bare repo laid out for worktrees |
| `git worktree-add` | Add a worktree in that layout |
| `git worktree-setup` | Run a project's `.worktree/setup` hook in a worktree |

## Install

```sh
curl -fsSL https://raw.githubusercontent.com/ryanburda/git-ext/main/install.sh | sh
```

The script clones this repo to `~/.local/share/git-ext` and symlinks the
commands into `~/.local/bin`. Re-running it updates the checkout in place.

Make sure `~/.local/bin` is on your `PATH`. The installer warns you if it isn't:

```sh
export PATH="$HOME/.local/bin:$PATH"
```

Verify:

```sh
git seed            # prints usage
git clone-bare      # prints usage
git worktree-add    # prints usage
git worktree-setup  # runs the hook, if any
```

The commands themselves are zsh scripts, so zsh must be installed. The
installer is POSIX `sh`, so it runs under whatever shell you pipe it to.

Overrides, if the defaults don't suit you:

| Variable | Default |
| --- | --- |
| `GIT_EXT_HOME` | `~/.local/share/git-ext` (or `$XDG_DATA_HOME/git-ext`) |
| `BIN_DIR` | `~/.local/bin` |
| `GIT_EXT_REPO` | `https://github.com/ryanburda/git-ext.git` |

```sh
curl -fsSL https://raw.githubusercontent.com/ryanburda/git-ext/main/install.sh | BIN_DIR=~/bin sh
```

## Uninstall

To uninstall, delete the symlinks and the checkout, plus any completion links from the section below:

```sh
rm ~/.local/bin/git-{clone-bare,worktree-add,worktree-setup,seed}
rm -rf ~/.local/share/git-ext
```

## Completions

`completions/` holds shell completions for these git extensions.
For example, `git worktree-add` completes the `<branch>` argument, and
`git worktree-setup` completes the repo's worktrees.

```
$ git worktree-add wt <TAB>
feature/login  local-only  main  other  release-2.0
```

The installer leaves these files at `~/.local/share/git-ext/completions/`; each
shell needs one line to pick them up.

<details>
<summary>zsh</summary>

Source `git-ext.zsh` from `~/.zshrc`:

```zsh
source ~/.local/share/git-ext/completions/zsh/git-ext.zsh
```

It works wherever you put that line, including after `compinit` has already
run: rather than relying on `compinit` to scan `fpath`, it autoloads the
completion function itself. zsh dispatches an unknown git sub-command to a
function named `_git-<sub-command>`, so `_git-worktree-add` has to keep its
name but it does not have to be on `fpath` before `compinit`.

It also registers descriptions, so the commands show up in `git <TAB>`.

If your `.zshrc` sources a directory of extension scripts, symlink it in instead:

```zsh
ln -s ~/.local/share/git-ext/completions/zsh/git-ext.zsh ~/.zsh/zshrc_extensions/git-ext.zsh
```

</details>

<details>
<summary>bash</summary>

With bash-completion installed, symlink the file into its user directory and it is loaded on demand:

```sh
mkdir -p ~/.local/share/bash-completion/completions
for c in git-worktree-add git-worktree-setup; do
    ln -sfn ~/.local/share/git-ext/completions/bash/$c \
            ~/.local/share/bash-completion/completions/$c
done
```

Without bash-completion, source it from `~/.bashrc` after git's own
completion:

```sh
source ~/.local/share/git-ext/completions/bash/git-worktree-add
source ~/.local/share/git-ext/completions/bash/git-worktree-setup
```

</details>

<details>
<summary>fish</summary>

This file registers completions for `git` itself, so it has to be loaded
before you complete a git command. `conf.d/` should be used instead of
`completions/` (which fish only loads when completing a command of the same name):

```fish
for c in git-worktree-add git-worktree-setup
    ln -sfn ~/.local/share/git-ext/completions/fish/$c.fish \
            ~/.config/fish/conf.d/$c.fish
end
```

</details>

## Usage

### `git seed`

A worktree-first version of `git clone`

```
git seed [-b <branch>] [-w <worktree_name>] [-n] <repo_url> [<root_path>]
```

| Flag | Default | Meaning |
| --- | --- | --- |
| `-b <branch>` | the remote's default branch | branch to check out |
| `-w <name>` | `base` | worktree directory name |
| `-n` | lock | don't lock the worktree |

**Example**:
```sh
git seed git@github.com:user/project_a.git
```
**Produces**:
```
../project_a/
├── .git/          <- bare repo
└── base/          <- worktree, on the remote's default branch, locked
```
**Explaination**:
- With no `<root_path>`, the project name is derived from the URL and created
under the current directory, matching `git clone`'s behavior.
- The branch comes from the remote's `HEAD`, so repos on `main` and repos on
`master` both work without being told which.
- The worktree directory is called `base` rather than being named after the branch.
- The worktree is locked by default enforcing that at least one worktree be thought of
as the "default" worktree. Locking prevents `git worktree prune` from removing it.

Safe to re-run: an existing bare repo, worktree, or lock is each left alone, so
a setup script can call it on every bootstrap. Only `<root_path>/.git` and the
worktree directory are written, so an existing project root is fine.

The project's `.worktree/setup` hook is *not* run — that is
[`git worktree-setup`](#git-worktree-setup), kept separate so that slow setup
work stays opt-in.

### `git clone-bare`

```
git clone-bare <repo_url> [<root_path>]
```

Clones into `<root_path>/.git` as a bare repo. With no `<root_path>`, the
project name is derived from the URL and created under the current directory,
matching `git clone`'s behavior.

A plain `git clone --bare` isn't ideal for day-to-day development since it's built
to be a server-side mirror. This means it maps every upstream branch into
`refs/heads/*` and has no local/remote distinction. This command restores it:

- sets `remote.origin.fetch` to the standard `+refs/heads/*:refs/remotes/origin/*`
- deletes every local branch except the default one
- re-fetches, populating `refs/remotes/origin/*`

The result is a bare repo whose refs look like a normal clone's, so upstream
branches are `origin/<branch>` and local branches are yours.

### `git worktree-add`

```
git worktree-add <worktree_name> <branch>               # check out an existing branch
git worktree-add <worktree_name> <branch> <new_branch>  # create new_branch off branch
```

```sh
git worktree-add wt1 main             # main checked out at $REPO_ROOT/wt1
git worktree-add wt1 main feature     # branch "feature" off main at $REPO_ROOT/wt1
```

The worktree is always created as a sibling of the bare `.git` directory,
regardless of where in the repo you run the command from.

After creating it, the command sets the branch's upstream to `origin/<branch>` if
that remote branch exists.

Creating the worktree is all it does. Preparing that worktree is
`git worktree-setup`, deliberately a separate command: setup can be slow, and
adding a worktree shouldn't drag that along every time.

### `git worktree-setup`

```
git worktree-setup [<worktree_path>]
```

Runs `<project_root>/.worktree/setup` from inside the given worktree, or the
current one if no path is given. Does nothing, successfully, when the project
has no hook -- so it's safe to call unconditionally.

```sh
WT=$(git seed git@github.com:user/project_a.git ~/code/project_a)
ln -sfn ~/repos/project_a ~/code/project_a/.worktree
git -C "$WT" worktree-setup
```

#### Worktree setup hook

`git worktree-setup` runs `<project_root>/.worktree/setup` from inside a
worktree, if the project has one.

Note the location: `.worktree/` sits next to the bare `.git` directory, at the
project root, *not* inside a worktree, and therefore not tracked by the repo.
It's per-clone, per-machine configuration, which is what makes it the right
place for the untracked odds and ends a fresh checkout needs:

```
~/code/project_a/
├── .git/
├── .worktree/
│   └── setup      <- runs in each new worktree
├── wt1/
└── wt2/
```

```sh
#!/bin/sh
# ~/code/project_a/.worktree/setup
cp ~/code/project_a/.worktree/.env .env
npm install
```

## Keeping your setup reproducible

The `.worktree/` directory is deliberately outside the project's own repo,
which means nothing is tracking it. Left alone, the setup script you wrote
only exists on this machine and vanishes if anything were to happen to it.

Therefore, it is a good idea to keep repo setup scripts in a dedicated private
repo instead. A `repos` repo, holding one directory per project, plus a top-level
script that recreates every clone from scratch is an easy, version controlled, way
to setup all of your projects on a fresh machine:

```
~/repos/                  <- private git repo
├── setup                 <- recreates every project below
├── project_a/
│   ├── setup             <- becomes project_a's .worktree/setup
│   └── .env
└── project_b/
    └── setup
```

Symlink each project directory into place as its `.worktree`, so the setup
script and the untracked files it copies travel together:

```sh
ln -s ~/repos/project_a ~/code/project_a/.worktree
```

The top-level `~/repos/setup` then does the whole job end to end of cloning,
linking, and creating the first worktree:

```sh
#!/bin/sh
# ~/repos/setup
set -e

WT=$(git seed git@github.com:user/project_a.git ~/code/project_a)
ln -sfn ~/repos/project_a ~/code/project_a/.worktree
git -C "$WT" worktree-setup
```

Because setup is its own step, the hook only has to be linked before
`git worktree-setup` runs -- the order of the first two lines doesn't matter.
