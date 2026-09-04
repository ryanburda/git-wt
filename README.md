# git-wt

*Git external commands for a worktree-first workflow.*

Small wrappers around git that enforce one simple repo layout: a bare repo
with every worktree as a direct sibling.

```sh
# `git seed` is a worktree-first `git clone`. Just pass it a URL.
git seed git@github.com:user/project.git

# `git wt-add` adds a worktree in the same layout.
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
| `git wt-add` | Add a worktree in that layout |
| `git wt-rm` | Remove a worktree from that layout |
| `git wt-setup` | Run a project's `.wt-setup/setup` hook in a worktree |

See the [design_decisions](design_decisions.md) doc for implementation
specific details.

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
rm ~/.local/bin/git-{seed,wt-add,wt-rm,wt-setup}
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
git wt-add <worktree_name> <branch>               # check out an existing branch
git wt-add <worktree_name> <branch> <new_branch>  # create new_branch off branch
```

```sh
git wt-add wt1 main             # main checked out at <project_root>/wt1
git wt-add wt1 main feature     # branch "feature" off main at <project_root>/wt1
```

`<worktree_name>` is a name, not a path: it's joined onto the project root, so
you get the same worktree no matter where in the repo you run the command
from. Afterwards the branch's upstream is set to `origin/<branch>` if that
remote branch exists.

Creating the worktree is all it does; preparing it is `git wt-setup`.

### `git wt-rm`

```
git wt-rm [-f] <worktree_name>
```

```sh
git wt-rm wt1        # remove <project_root>/wt1
git wt-rm -f base    # remove the locked base worktree
```

The counterpart to `git wt-add`, taking a name the same way. Only the worktree
is removed; its branch is left alone.

`-f` is required for a worktree that is locked or has modified or untracked
files; without it, either is an error and nothing is removed. Since `git seed`
locks `base`, removing the default worktree takes `-f` on purpose.

The project root is printed on stdout, which is where you want to be if you
just removed the worktree you were standing in:

```sh
cd "$(git wt-rm wt1)"
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
