# git-wt

*Git external commands for a worktree-first workflow.*

Small wrappers around git commands that enforce a simple repo layout: a bare
repo with every worktree as a direct sibling.

```sh
# `git seed` is a worktree-first `git clone`. Just pass it a URL.
git seed git@github.com:user/project.git

# `git wt-add` adds a worktree in the same layout.
#
# worktree name      (optional) new branch name created off existing
#           |          |
#           v          v
git wt-add wt1 main feature
#               ^
#               |
#         existing branch to check out
```

The commands above produce:

```
project/
├── .git/        <- bare repo  (created by `git seed`)
├── base/        <- worktree   (created by `git seed`)
└── wt1/         <- worktree   (created by `git wt-add`)
```

- As with `git clone`, the project name is inferred from the URL and becomes
  the top-level directory.
- `base` is created and locked by `git seed` to act as your "default" worktree.
- Keeping every worktree a direct child of the project root keeps git's
  [internal worktree names](#worktree-names-and-the-flat-layout) unique.

| Command | Purpose |
| --- | --- |
| `git seed` | Clone a repo and create its first worktree in one step |
| `git wt-add` | Add a worktree in that layout |
| `git wt-rm` | Remove a worktree from that layout |
| `git wt-setup` | Run a project's `.wt-setup/setup` hook in a worktree |

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
| `GIT_WT_REPO` | `https://github.com/ryanburda/git-wt.git` |

```sh
curl -fsSL https://raw.githubusercontent.com/ryanburda/git-wt/main/install.sh | BIN_DIR=~/bin sh
```

## Uninstall

Delete the symlinks and the checkout, plus any completion links from the
section below:

```sh
rm ~/.local/bin/git-{seed,wt-add,wt-rm,wt-setup}
rm -rf ~/.local/share/git-wt
```

## Completions

`completions/` holds shell completions: `git wt-add` completes the
`<branch>` argument, and `git wt-rm` and `git wt-setup` complete the repo's
worktrees.

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
for c in git-wt-add git-wt-rm git-wt-setup; do
    ln -sfn ~/.local/share/git-wt/completions/bash/$c \
            ~/.local/share/bash-completion/completions/$c
done
```

Without bash-completion, source them from `~/.bashrc` after git's own
completion:

```sh
source ~/.local/share/git-wt/completions/bash/git-wt-add
source ~/.local/share/git-wt/completions/bash/git-wt-rm
source ~/.local/share/git-wt/completions/bash/git-wt-setup
```

</details>

<details>
<summary>fish</summary>

These files register completions for `git` itself, so they belong in
`conf.d/`, not `completions/` (which fish only loads when completing a command
of the same name):

```fish
for c in git-wt-add git-wt-rm git-wt-setup
    ln -sfn ~/.local/share/git-wt/completions/fish/$c.fish \
            ~/.config/fish/conf.d/$c.fish
end
```

</details>

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

- With no `<root_path>`, the project name is derived from the URL and created
  under the current directory, matching `git clone`.
- The branch comes from the remote's `HEAD`, so repos on `main` and repos on
  `master` both work without being told which.
- The worktree is locked by default, marking it as the "default" worktree and
  protecting it from `git worktree prune`.

Safe to re-run: an existing bare repo, worktree, or lock is left alone, so a
setup script can call it on every bootstrap.

The project's `.wt-setup/setup` hook is *not* run; that job belongs to
[`git wt-setup`](#git-wt-setup), kept separate so that slow setup work stays
opt-in.

#### The bare repo

A plain `git clone --bare` is built to be a server-side mirror: it maps every
upstream branch into `refs/heads/*` and has no local/remote distinction. Before
adding the worktree, `git seed` restores the ref layout of a normal clone:

- sets `remote.origin.fetch` to the standard `+refs/heads/*:refs/remotes/origin/*`
- deletes every local branch except the default one
- re-fetches, populating `refs/remotes/origin/*`

The result is a bare repo where upstream branches are `origin/<branch>` and
local branches are yours.

### `git wt-add`

```
git wt-add <worktree_name> <branch>               # check out an existing branch
git wt-add <worktree_name> <branch> <new_branch>  # create new_branch off branch
```

```sh
git wt-add wt1 main             # main checked out at $REPO_ROOT/wt1
git wt-add wt1 main feature     # branch "feature" off main at $REPO_ROOT/wt1
```

The worktree is always created as a sibling of the bare `.git` directory,
regardless of where in the repo you run the command from. After creating it,
the command sets the branch's upstream to `origin/<branch>` if that remote
branch exists.

Creating the worktree is all it does. Preparing it is `git wt-setup`,
deliberately separate so slow setup work stays opt-in.

### `git wt-rm`

```
git wt-rm [-f] <worktree_name>
```

```sh
git wt-rm wt1        # remove $REPO_ROOT/wt1
git wt-rm -f base    # remove the locked base worktree
```

The counterpart to `git wt-add`: `<worktree_name>` is a name, not a path,
joined onto the project root, so it removes the same worktree no matter where
in the repo you run it from.

Only the worktree is removed; its branch is left alone. `-f` is required for a
worktree that is locked or has modified or untracked files; without it,
either is an error and nothing is removed. Since `git seed` locks `base`,
removing the default worktree takes `-f` on purpose.

The project root is printed on stdout, which is where you want to be if you
just removed the worktree you were standing in:

```sh
cd "$(git wt-rm wt1)"
```

Safe to re-run: removing a worktree that isn't there prints the root and exits
0. A path that exists but is not a worktree of this repo is never deleted.

### `git wt-setup`

```
git wt-setup [<worktree_path>]
```

Runs `<project_root>/.wt-setup/setup` from inside the given worktree, or the
current one if no path is given. Does nothing, successfully, when the project
has no hook, so it's safe to call unconditionally.

```sh
WT=$(git seed git@github.com:user/project_a.git ~/code/project_a)
ln -sfn ~/repos/project_a ~/code/project_a/.wt-setup
git -C "$WT" wt-setup
```

#### Worktree setup hook

`.wt-setup/` sits next to the bare `.git` directory at the project root, not
inside a worktree, and therefore not tracked by the repo. It's per-clone,
per-machine configuration: the right place for the untracked odds and ends a
fresh checkout needs.

```
~/code/project_a/
├── .git/
├── .wt-setup/
│   └── setup      <- runs in each new worktree
├── wt1/
└── wt2/
```

There is one hook per project, shared by every worktree under it. `git
wt-setup` always looks it up from the project root, so it doesn't matter which
worktree you run the command from, only which worktree it runs *against*.

#### Writing the hook

Nothing creates the hook for you. `git seed` and `git wt-add` never write one,
and since `.wt-setup/` is untracked it doesn't arrive with a clone either. On a
fresh project `git wt-setup` is a successful no-op until you put a file at that
path yourself:

```
$ git wt-setup
No setup hook at /home/you/code/project_a/.wt-setup/setup; nothing to do.
```

So the whole of "installing" a hook is: make the directory, write the file,
mark it executable. For most projects the file is one line:

```sh
mkdir -p ~/code/project_a/.wt-setup
cat > ~/code/project_a/.wt-setup/setup <<'EOF'
#!/bin/sh
npm install
EOF
chmod +x ~/code/project_a/.wt-setup/setup
```

That's a complete hook. Every new worktree now gets its own `node_modules/`
without you remembering to install anything.

The `chmod +x` is the step that's easy to skip. `git wt-setup` doesn't source
the file or hand it to a shell; it *executes* it, so the executable bit is
what makes it run at all. A `setup` that exists but isn't executable is treated
as a mistake rather than as an absent hook, and is the one case where the
command fails instead of shrugging:

```
$ git wt-setup
Error: /home/you/code/project_a/.wt-setup/setup exists but is not executable
```

Because the file is executed, it can be *any* executable: the shebang picks
the language, and a compiled binary works just as well as a script:

```python
#!/usr/bin/env python3
# ~/code/project_a/.wt-setup/setup
import subprocess, venv
venv.create(".venv", with_pip=True)
subprocess.run([".venv/bin/pip", "install", "-r", "requirements.txt"], check=True)
```

#### How the hook runs

- **Working directory**: the worktree being set up, so relative paths in the
  hook land inside it. The `npm install` above writes `node_modules/` into
  that worktree, not into the project root. This holds however you invoked the
  command, whether from the worktree, from a subdirectory of it, from a
  *different* worktree with an explicit `<worktree_path>`, or through `git -C`.
- **Arguments**: none. The worktree the hook is running in is `$PWD`.
- **Environment**: inherited from your shell. `GIT_DIR` and `GIT_WORK_TREE`
  are not exported, so a plain `git` call inside the hook resolves to the
  worktree it's running in, not to the bare repo.
- **Exit status**: the hook's becomes the command's, so a hook that fails
  fails `git wt-setup`. Nothing is retried and no other worktree is touched.

A hook that may run against an already-prepared worktree should be written to
tolerate that; `git wt-setup` will happily run it again.

#### Keeping files next to the hook

`setup` is only one file in `.wt-setup/`, and everything beside it is untracked
and per-clone for the same reason the hook is. That makes the directory a good
home for the files every worktree needs but the repo doesn't carry: the
`.env` that never gets committed, a local config override, a scratch database
seed:

```
~/code/project_a/
├── .git/
├── .wt-setup/
│   ├── setup           <- the hook
│   ├── .env            <- files the hook puts into each worktree
│   └── config.local.json
├── wt1/
└── wt2/
```

The hook is what gets them into a worktree. Since it runs with the worktree as
its working directory, the destination is just a relative path:

```sh
#!/bin/sh
# ~/code/project_a/.wt-setup/setup
WT_DIR=$(git rev-parse --git-common-dir)/../.wt-setup

cp "$WT_DIR/.env" .env                       # a private copy per worktree
ln -sfn "$WT_DIR/config.local.json" .        # one shared file, linked in

npm install
```

Copy or symlink is a real choice: a copy lets each worktree drift
independently, while a symlink means editing the file in one worktree changes
it for all of them and for the next worktree you create.

Whichever you pick, make sure the result is ignored. These files land *inside*
the worktree, so anything the repo's `.gitignore` doesn't already cover shows
up as untracked, and `git wt-rm` then refuses to remove that worktree without
`-f`:

```
$ git wt-rm wt1
fatal: '/home/you/code/project_a/wt1' contains modified or untracked files, use --force to delete it
```

`.git/info/exclude` is the natural place to list them: it lives in the bare
repo, applies to every worktree, and is untracked itself.

```sh
echo '.env' >> ~/code/project_a/.git/info/exclude
```

If you'd rather keep this whole directory under version control somewhere of
your own, point `.wt-setup/` at it with a symlink instead of creating it.
That's what the `ln -sfn` in the first example does:

```sh
ln -sfn ~/repos/project_a ~/code/project_a/.wt-setup
```

## Worktree names and the flat layout

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

Nothing breaks, but the short name is now ambiguous, and the error doesn't say
so:

```sh
$ git worktree remove feature
fatal: 'feature' is not a working tree
```

Git resolves a worktree argument by matching it against the tail of each
worktree path; two matches count the same as none, so you have to disambiguate
with more of the path. And there is no porcelain for these names:
`git worktree list --porcelain` reports path, HEAD, and branch, never the
name, so the only way to see them is to read them off disk:

```sh
# every worktree's internal name, mapped to its path
for d in "$(git rev-parse --git-common-dir)"/worktrees/*/; do
    printf '%-20s %s\n' "$(basename "$d")" "$(sed 's|/\.git$||' "$d/gitdir")"
done

# just the current worktree's name
basename "$(git rev-parse --git-dir)"
```

The flat layout sidesteps all of this by construction: every worktree is a
direct child of the project root, a directory can't hold two entries with the
same name, so last path segments, and therefore internal names, are unique.
Every worktree answers to its own directory name.

### Why nested names are rejected

`git wt-add` takes a *name* and joins it onto the project root. A name
containing `/` is a relative path, and plain `git worktree add` would happily
create the intermediate directories, undoing the guarantee above:

```
project/
├── .git/
├── a/wt/      <- .git/worktrees/wt
└── b/wt/      <- .git/worktrees/wt1     <- collision is back
```

So `git wt-add` requires a single path segment:

```sh
$ git wt-add a/wt main
Error: <worktree_name> must be a directory name, not a path: 'a/wt'
```

`.` and `..` are refused for the same reason: `..` would put the worktree
outside the project root entirely. Every rejection exits 128 and creates
nothing.

This is a constraint of *this* command, not of git: plain `git worktree add`
still takes an arbitrary path.
