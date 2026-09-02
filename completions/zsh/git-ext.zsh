# zsh setup for git-ext, meant to be sourced from ~/.zshrc.
#
# Symlink this into a directory your .zshrc sources, e.g.
#
#   ln -s <git-ext>/completions/zsh/git-ext.zsh ~/.zsh/zshrc_extensions/git-ext.zsh
#
# Some loaders only source executable files, so this file keeps its +x bit.
#
# .zshrc typically runs compinit before extensions like this are sourced, so
# rather than adding to fpath and re-running compinit, the completion function
# is autoloaded directly: zsh's _git dispatches `git worktree-add` to a
# function named `_git-worktree-add`, and compdef binds the standalone command.

_git_ext_root=${0:A:h:h:h}

fpath=($_git_ext_root/completions/zsh $fpath)
autoload -Uz _git-worktree-add
compdef _git-worktree-add git-worktree-add
autoload -Uz _git-worktree-remove
compdef _git-worktree-remove git-worktree-remove
autoload -Uz _git-worktree-setup
compdef _git-worktree-setup git-worktree-setup

# Offer the commands, with descriptions, when completing `git <TAB>`.
zstyle ':completion:*:*:git:*' user-commands \
    clone-bare:'clone a repo as a bare repo laid out for worktrees' \
    seed:'clone a repo and grow its first worktree in one step' \
    worktree-add:'add a worktree in that layout' \
    worktree-remove:'remove a worktree from that layout' \
    worktree-setup:'run the project .worktree/setup hook in a worktree'

unset _git_ext_root
