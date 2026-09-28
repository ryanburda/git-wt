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

`git wt-bud` takes a *name* and joins it onto the project root. A name
containing `/` is a relative path, and plain `git worktree add` would happily
create the intermediate directories, undoing the guarantee above:

```
project/
├── .git/
├── a/wt/      <- .git/worktrees/wt
└── b/wt/      <- .git/worktrees/wt1     <- collision is back
```

So `git wt-bud` requires a single path segment that can be thought of as a name:

```sh
$ git wt-bud a/wt main
Error: <worktree_name> must be a directory name, not a path: 'a/wt'
```

`.` and `..` are refused for the same reason: `..` would put the worktree
outside the project root entirely. Every rejection exits 128 and creates
nothing.

This is a constraint of *this* command, not of git: plain `git worktree add`
still takes an arbitrary path.

### Names, not paths

For the same reason, `git wt-bud`, `git wt-clip`, and the completions all treat
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
removing it is a deliberate act: `git wt-clip base` fails, and `git wt-clip -f
base` is the only way through. `git wt-clip -k base` needs no `-f`: it removes
nothing, so the lock has nothing to protect against.

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

`git seed` and `git wt-bud` create worktrees and stop there. `git wt-setup` 
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
up as untracked, and `git wt-clip` then refuses to remove that worktree without
`-f`:

```
$ git wt-clip wt1
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

## The command names

Three of the four are a bonsai -- a tree you keep deliberately small, and go on
shaping for years:

- **`seed`** starts one: a worktree-first `git clone`.
- **`bud`** is where new growth appears on an existing tree, which is both
  things the command does -- it grows a new worktree, and it puts a new branch
  on one that is already there.
- **`clip`** is cutting growth off: the whole worktree, or with `-k` just the
  branch, leaving the worktree behind.

`git wt-setup` is the fourth, and it deliberately isn't one of them. See
[below](#why-wt-setup-isnt-a-gardening-verb).

Names that were considered and rejected:

- `prune` for the removing half, whose symmetry with `graft` is perfect and
  whose horticulture is real. `git worktree prune` already exists and means
  something unrelated -- deleting the metadata of worktrees whose directories
  are gone -- so `git prune` sitting next to it would read as a wrapper around
  it. (`git prune` is also a real git command, on objects.)
- `freeze`/`thaw` for the parking pair. Accurate, and attached to no theme.
- `root` for the default worktree, back when it was being named. It reads as
  superuser, or as the root of the repo. `base` won that one.

### Why the `wt-` prefix

`git wt-bud` and `git wt-clip` were `git bud` and `git clip` for a while. The
argument for the bare names was that the prefix is a tax on every use of the
commands, which is where you actually spend the time: `git bud wt1 main feature`
reads as a sentence, and the theme only works if the words are allowed to be
words.

That is true, and it is still the wrong trade. `bud` and `clip` are exactly the
names some other tool, alias, or future git will want, and a bare verb in your
shell history says nothing about worktrees to anyone reading it later -- you
included. Against a few keystrokes, the prefix buys a tab-completion stem that
groups the family, and it keeps these names out of the way of every other
`git-*` extension on your PATH.

The prefix is also already everywhere the commands aren't. The project is
`git-wt`, so the repo, `GIT_WT_HOME`, and the zsh loader carry the name, and the
shell completion helpers live in a `__git_wt_*` namespace. That last one is not
cosmetic -- `__git_<noun>` belongs to bash-completion's own git module
(`__git_refs`, `__git_heads`, `__git_find_on_cmdline`), and a private helper has
no business in it. Having the part you type match the project it comes from is
the consistent end of that, not an exception to it.

The verbs survive the prefix intact. `wt-bud` and `wt-clip` still say bud and
clip; they just say which tree first.

### Why `wt-setup` isn't a gardening verb

`git wt-setup` shares the prefix but not the theme, and that is not an
oversight.

It is the only one of the commands that isn't a gardening act. `seed`, `bud`,
and `clip` all do something to the tree, and each word says which. `wt-setup`
runs a hook you wrote, in a worktree, to install whatever that project needs --
plumbing, named after the `.wt-setup/` directory it runs. A bonsai verb over the
top of that would be decoration, not description. `pot` was the candidate, and
it read well -- potting gives a plant the soil it needs to live, and it is where
a bonsai's roots get worked on, which is what `git wt-clip -k` preserves -- but
it named the metaphor rather than the job, and the job is "run the setup hook".

So `wt-setup` is the worktree-setup command, it reads the `.wt-setup/`
directory, and the two names matching is the point. The odd name out marks the
odd command out, which is the useful thing for it to do.

## Putting a worktree on ice

A worktree holds its branch hostage. Git allows a branch to be checked out in
exactly one worktree at a time, so an idle worktree isn't just sitting on disk
doing nothing -- it's sitting on a branch name:

```
$ git wt-bud wt2 feature
fatal: 'feature' is already used by worktree at '/home/you/code/project_a/wt1'
```

Removing the worktree frees the branch, and that is the expensive way to do it.
It also removes the worktree's `node_modules`, its `.venv`, its `.env` -- every
slow thing [`git wt-setup`](#why-wt-setup-is-a-separate-command) did. You pay
for that again next time you want the worktree back, and you paid it just to
free up a branch name.

Detaching HEAD frees the branch and costs nothing. A worktree with a detached
HEAD has no current branch, so nothing is claimed, and the directory is
untouched. That is `git wt-clip -k`, and `git wt-bud` is the other direction:
it checks a branch back out in a worktree that already exists.

```sh
git wt-clip -k wt1    # wt1 keeps its files; branch 'feature' is free
git branch -d feature # ...so this now works
git wt-bud wt1 main other-feature
```

The pair turns "remove the worktree" into "park the worktree", which is what you
actually wanted whenever the setup was the expensive part.

### Why budding and growing are one command

`git wt-bud` creates a worktree when there isn't one and checks the branch out
in place when there is. Those were briefly two commands taking identical
arguments, which is a sign they were one command: at the call site you know the
worktree name and the branch you want in it, and whether the directory happens
to exist already is not a thing you should have to have tracked.

Merging them keeps one promise worth being careful about. `git wt-add` was
documented as safe to re-run -- adding a worktree that already existed was a
no-op. That still holds, because it is the *same arguments* that stay a no-op:
budding the branch a worktree is already on reports and exits 0. Only a
*different* branch causes a checkout, which is a different command line, and one
that can't have been a no-op under the old behavior either, since it would have
been an add of a worktree that wasn't there.

What it won't do is create a worktree that isn't there when you plainly meant an
existing one -- there's no way to tell those apart from the arguments, so it
doesn't try. It creates, and the worst case is a worktree you then clip.

### Why `-k` rather than a third command

Clipping a worktree off the tree and clipping a branch off a worktree are the
same gesture at two depths, they take the same argument, and you pick between
them for one reason: whether the setup inside the worktree is worth keeping.
A flag on one command puts that choice where it is made. A separate command
would have been a third name for "get this worktree out of my way".

`-k` is for *keep*, and it reads as the exception it is: clip, but keep the
worktree.

Two things do differ between the two modes, both because the worktree survives:

- **Stdout.** A removal prints the project root, because the directory you were
  standing in may be gone and you need somewhere to `cd`. With `-k` the worktree
  is still there, so its own path is printed. Both are "where you want to be
  afterwards", which is the rule the command actually follows.
- **A missing worktree.** For a removal that's an already-done no-op. For `-k`
  it's an error: you asked to keep a worktree that isn't there, which is a typo
  rather than a state something else reached. There's nothing to keep, and
  succeeding would hide the mistake.

`-b` only means anything with `-k`, so `-b` without it is rejected rather than
ignored -- silently ignoring it would remove a worktree the caller expected to
keep.

### Why it detaches at the default branch

`git wt-clip -k` parks HEAD at the project's default branch, not at the tip of
the branch it is clipping off.

Either one frees the branch, so this is a choice about what a parked worktree
should contain. The default branch is the useful answer: a worktree you come
back to months later is more useful at mainline than frozen at a feature tip you
no longer remember, and the working tree matching mainline is what keeps the
surviving setup valid. It also means a parked worktree carries no trace of the
branch it used to hold, so deleting that branch leaves nothing inconsistent
behind.

The branch is read from the bare repo's `HEAD`, the same source
[`git seed`](#why-git-seed-reshapes-the-bare-repo) uses, so `main` and `master`
both work without being told which. `HEAD` is per-worktree, so it has to be read
from the common dir: the current worktree's `HEAD` names the branch being
clipped off, which is the one thing it can't be.

`-b <commit-ish>` overrides the parking spot for the cases where mainline isn't
what you want -- a release tag, an older commit the worktree is pinned to.

### Why syncing is a separate command

Parking at the default branch fixes where a worktree sits on the day it is
clipped, and nothing moves it afterwards. A detached HEAD is a commit, not a
ref: `refs/remotes/origin/main` advances on every fetch and the parked worktree
stays exactly where it was. Come back in a month and the "parked at mainline"
worktree is parked at last month's mainline.

The tempting fix is to make `git wt-clip -k` resolve something that keeps
moving, but there is nothing to resolve. Git has no symbolic detached HEAD --
that is what a branch is, and a branch is the one thing a parked worktree must
not hold. So the update has to be an action someone takes, which is
[`git wt-sync`](README.md#git-wt-sync).

It syncs one worktree -- the one named, or the one the caller is standing in,
the same default [`wt-setup`](#why-wt-setup-is-a-separate-command) uses. A
sweep over every parked worktree in the project is the obvious alternative and
the wrong one: it moves directories nobody was looking at, on the strength of a
single keystroke, and the thing being moved is a working tree rather than a
ref. Naming one worktree, or standing in it, is a small enough price for
knowing what a run is going to touch. Syncing several is a loop in a shell,
which is where a loop belongs.

It targets `origin/<default branch>` where `wt-clip -k` prefers the local one,
and the inversion is deliberate. Clip parks at the default branch *as this repo
knows it*; sync exists to chase upstream, and in this layout `refs/heads/main`
is the stale copy -- a fetch writes `refs/remotes/origin/*` and nothing pulls
the bare repo's own branches, so a local `main` only moves if some worktree
checks it out and pulls.

Sync only fast-forwards. A worktree is advanced when its commit is an ancestor
of the target and refused otherwise, which is what keeps `-b` honest: a
worktree parked on a release tag was parked there on purpose, and a command
that quietly moved it to mainline would make `-b` untrustworthy. The rule
misses a tag that sits on mainline's own history -- it is an ancestor like any
other commit -- and `-b` is the way back.

Refusing is an error; the two no-ops are not. A worktree already at the target,
and one on a branch rather than parked, both exit 0: the first is what
re-running looks like, and the second is what pointing the command at live work
by mistake looks like. Neither is worth failing over, and both print the path
like every other command here. A worktree this command *won't* move -- parked
off mainline, or dirty without `-f` -- exits 128 having changed nothing, the
same line `wt-bud` and `wt-clip` draw.

`git wt-sync -b` is also the only way to move a worktree that is already
parked. `git wt-clip -k` won't: clipping the branch off a worktree that has no
branch is a no-op, by the rule above about not moving a parked worktree out
from under whatever it is parked on.

### Why it doesn't delete the branch

Freeing the branch is the point, and deleting it is the obvious next step, but
`git wt-clip -k` stops at freeing it. This is the same line the removing half
draws: these commands manage worktrees and leave branches to `git branch`. A
command that deletes a branch as a side effect of parking a directory is one you
have to think twice before running.

So it prints what you need instead, including the SHA, which is what makes
deleting the branch recoverable rather than final:

```
$ git wt-clip -k wt1
Worktree /home/you/code/project_a/wt1 kept; branch 'feature' (ff74ab3) is free.
  delete it:   git branch -d feature
  put it back: git wt-bud wt1 feature
```
