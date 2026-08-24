#!/bin/sh
# Install git-ext: symlink the git external commands into a directory on PATH
# so that git picks them up as subcommands.
#
#   curl -fsSL https://raw.githubusercontent.com/ryanburda/git-ext/main/install.sh | sh
#
# Environment overrides:
#   GIT_EXT_HOME  where the repo is cloned  (default: ~/.local/share/git-ext)
#   BIN_DIR       where symlinks are placed (default: ~/.local/bin)
#   GIT_EXT_REPO  clone URL                 (default: the GitHub HTTPS URL)

set -eu

REPO_URL=${GIT_EXT_REPO:-https://github.com/ryanburda/git-ext.git}
GIT_EXT_HOME=${GIT_EXT_HOME:-"${XDG_DATA_HOME:-$HOME/.local/share}/git-ext"}
BIN_DIR=${BIN_DIR:-"$HOME/.local/bin"}

COMMANDS="git-clone-bare git-worktree-add"

die() {
    echo "install.sh: $*" >&2
    exit 1
}

command -v git > /dev/null 2>&1 || die "git is required but was not found on PATH"

if ! command -v zsh > /dev/null 2>&1; then
    echo "install.sh: warning: zsh was not found on PATH; these commands require it." >&2
fi

# Fetch (or update) the source checkout that the symlinks point at.
if [ -d "$GIT_EXT_HOME/.git" ]; then
    echo "Updating existing checkout at $GIT_EXT_HOME"
    git -C "$GIT_EXT_HOME" fetch --quiet origin
    git -C "$GIT_EXT_HOME" reset --quiet --hard origin/HEAD
elif [ -e "$GIT_EXT_HOME" ]; then
    die "$GIT_EXT_HOME exists but is not a git checkout; move it aside and retry"
else
    echo "Cloning $REPO_URL into $GIT_EXT_HOME"
    mkdir -p "$(dirname "$GIT_EXT_HOME")"
    git clone --quiet "$REPO_URL" "$GIT_EXT_HOME"
fi

mkdir -p "$BIN_DIR"

for cmd in $COMMANDS; do
    src="$GIT_EXT_HOME/$cmd"
    dest="$BIN_DIR/$cmd"

    [ -f "$src" ] || die "expected $src to exist"
    chmod +x "$src"

    if [ -e "$dest" ] && [ ! -L "$dest" ]; then
        die "$dest exists and is not a symlink; remove it and retry"
    fi

    ln -sfn "$src" "$dest"
    echo "Linked $dest -> $src"
done

# The commands are only usable as `git <subcommand>` if BIN_DIR is on PATH.
case ":$PATH:" in
    *":$BIN_DIR:"*) ;;
    *)
        echo
        echo "install.sh: warning: $BIN_DIR is not on your PATH."
        echo "Add this to your shell profile (e.g. ~/.zshrc) and restart your shell:"
        echo
        echo "    export PATH=\"$BIN_DIR:\$PATH\""
        ;;
esac

echo
echo "Done. Run 'git clone-bare' with no arguments to see its usage."
