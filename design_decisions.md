# Design decisions

## The flat repo layout

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

The flat layout sidesteps all of this by construction. Every worktree is a
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

So `git wt-add` requires a single path segment that can be thought of as a name:

```sh
$ git wt-add a/wt main
Error: <worktree_name> must be a directory name, not a path: 'a/wt'
```

`.` and `..` are refused for the same reason: `..` would put the worktree
outside the project root entirely. Every rejection exits 128 and creates
nothing.

This is a constraint of *this* command, not of git: plain `git worktree add`
still takes an arbitrary path.

### Names, not paths

For the same reason, `git wt-add`, `git wt-rm`, and the completions all treat
`<worktree_name>` as a name joined onto the project root derived from the bare
repo's location, never onto the current directory. The same command run from a
nested subdirectory, or from a *different* worktree, acts on the same place.

## Default worktree creation

The default worktree name `git seed` creates is called `base`.

The name `base` was chosen since it doesn't shadow other words
that already have a set meaning, unlike:

- `main`/`master` shadows default branch naming conventions
- `root` (of a tree) evokes the idea of a superuser
- `trunk` carries its own meaning from older version control systems

`base` is short, unclaimed in this context, and it says what it is:
the base worktree that all other worktrees get added alongside.

### Why it's locked

`git seed` locks the worktree it creates. The lock marks it as the project's
default worktree and protects it from `git worktree prune`. It also means
removing it is a deliberate act: `git wt-rm base` fails, and `git wt-rm -f
base` is the only way through.

## Why `git seed` reshapes the bare repo

A plain `git clone --bare` is built to be a server-side mirror: it maps every
upstream branch into `refs/heads/*` and has no local/remote distinction. That
is the wrong shape for a repo you work in. Every upstream branch would look
like a local branch of yours, and `git worktree add` would refuse the ones
already "checked out" elsewhere.

Before adding the worktree, `git seed` restores the ref layout of a normal
clone:

- sets `remote.origin.fetch` to the standard `+refs/heads/*:refs/remotes/origin/*`
- deletes every local branch except the default one
- re-fetches, populating `refs/remotes/origin/*`

The result is a bare repo where upstream branches are `origin/<branch>` and
local branches are yours.

The checked-out branch also comes from the remote's `HEAD` rather than a
hardcoded default, so repos on `main` and repos on `master` both work without
being told which.

## Why `wt-setup` is a separate command

`git seed` and `git wt-add` create worktrees and stop there. `git wt-setup` 
prepares a worktree by running project specific tasks like installing
dependencies or copying an `.env`. This is yours to customize to suit your needs.

Setup work is often slow, and not every new worktree needs it right away.
Keeping it out of the create path means adding a worktree stays instant and
setup stays opt-in, rather than a flag you have to remember to turn off.

## Why the hook is untracked and executed

The `.wt-setup/` directory sits next to the bare `.git` directory at the project
root, not inside a worktree, and therefore isn't tracked by the repo. It's meant
to be a per-clone, per-worktree configuration. This means you can use this directory
as a place for the untracked odds and ends a fresh checkout needs. One hook per
project shared by every worktree.

The hook is *executed*, not sourced. `wt-setup` relying on an executable means
that your setup can be written in the language of your choice. The shebang is
the only thing that decides which one. Here is the same hook written in two
different ways:

```zsh
#!/bin/zsh
# ~/code/project_a/.wt-setup/setup
set -e
python3 -m venv .venv
.venv/bin/pip install -r requirements.txt
```

```python
#!/usr/bin/env python3
# ~/code/project_a/.wt-setup/setup
import subprocess, venv
venv.create(".venv", with_pip=True)
subprocess.run([".venv/bin/pip", "install", "-r", "requirements.txt"], check=True)
```

Neither is more supported than the other. `git wt-setup` never looks inside the
file; it runs it and waits for an exit status, so a compiled binary at that path
works just as well.

Because execution is the mechanism, the executable bit is what makes the hook
run at all. A `setup` that exists but isn't executable is treated as a mistake
rather than as an absent hook, and is the one case where the command fails
instead of shrugging:

```
$ git wt-setup
Error: /home/you/code/project_a/.wt-setup/setup exists but is not executable
```

### How the hook runs

- **Working directory**: the worktree being set up, so relative paths in the
  hook land inside it. An `npm install` writes `node_modules/` into that
  worktree, not into the project root. This holds however you invoked the
  command, whether from the worktree, from a subdirectory of it, from a
  *different* worktree with an explicit `<worktree_path>`, or through `git -C`.
- **Arguments**: none. The worktree the hook is running in is `$PWD`.
- **Environment**: inherited from your shell. `GIT_DIR` and `GIT_WORK_TREE`
  are not exported, so a plain `git` call inside the hook resolves to the
  worktree it's running in, not to the bare repo.
- **Exit status**: the hook's becomes the command's, so a hook that fails
  fails `git wt-setup`. Nothing is retried and no other worktree is touched.

Setup hooks should idempotent. `git wt-setup` will happily run it again.
It is on you to make sure re-running is a safe operation.

### Keeping files next to the hook

`setup` is only one file in `.wt-setup/`, and everything beside it is untracked
and per-clone for the same reason the hook is. That makes the directory a good
home for the files/configuration every worktree needs but the repo doesn't carry.

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

### Version control your worktree setup

It is a good idea to keep your setup script and any other worktree specific files
version controlled in a separate repo. I personally have a private `repos` repo
that serves as a blueprint for how I want my repos laid out. This allows me to
symlink an entire `.wt-setup` directory in one shot, tracking changes to files
that otherwise would be ignored by the project:

```sh
ln -sfn ~/code/repos/project_a/.wt-setup ~/code/project_a/.wt-setup
```
