# git-wt

*Git external commands for a worktree-first workflow.*

Small wrappers around git that enforce a simple bare repo layout.

```sh
# A worktree-first version of `git clone`. Just pass it a URL.
git seed <url>
# Create a new worktree.
git wt-add <worktree-name> <existing-branch> [<new-branch>]
# Run the setup hook against a worktree.
git wt-setup <worktree-name>
# Park a worktree, releasing the branch it was on.
git wt-park <worktree-name>
```

Example usage:
```sh
# clone the repo and create first worktree.
git seed git@github.com:user/project.git
cd project

# create wt1 and set it up.
git wt-add wt1 main feature
git wt-setup wt1

# create wt2 and park it, releasing the branch.
git wt-add wt2 main bugfix
git wt-park wt2
```
The commands above produce the following repo layout:

```
./project/
├── .git/    <- bare repo                   (created by `git seed`)
├── base/    <- worktree on `main`          (created by `git seed`)
├── wt1/     <- worktree on `feature`       (created by `git wt-add`)
└── wt2/     <- worktree with detached HEAD (created by `git wt-add`)
```

- `git seed` creates the bare repo (`.git/`) and first locked worktree (`base`).
- `git wt-add` creates worktrees `wt1` and `wt2`.
- `git wt-setup` runs the setup hook against `wt1`.
- `git wt-park` puts `wt2` in a detached HEAD state, freeing the `bugfix` branch.

### Usage

For full usage instructions run each command with the `-h` flag.

```sh
git seed -h
git wt-add -h
git wt-setup -h
git wt-park -h
```


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


## Completions

`completions/` holds zsh and bash completions. `git wt-add` completes the
`<branch>` argument, and `git wt-park` and `git wt-setup` complete the repo's
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


## Lazygit

See [lazygit](./docs/lazygit.md) for instructions on integrating `git-wt` commands into lazygit.
