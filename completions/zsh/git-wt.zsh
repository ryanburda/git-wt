# zsh setup for git-wt, meant to be sourced from ~/.zshrc.
#
# Symlink this into a directory your .zshrc sources, e.g.
#
#   ln -s <git-wt>/completions/zsh/git-wt.zsh ~/.zsh/zshrc_extensions/git-wt.zsh
#
# Some loaders only source executable files, so this file keeps its +x bit.
#
# .zshrc typically runs compinit before extensions like this are sourced, so
# rather than adding to fpath and re-running compinit, the completion function
# is autoloaded directly: zsh's _git dispatches `git wt-bud` to a
# function named `_git-wt-bud`, and compdef binds the standalone command.

_git_wt_root=${0:A:h:h:h}

fpath=($_git_wt_root/completions/zsh $fpath)
autoload -Uz _git-wt-bud
compdef _git-wt-bud git-wt-bud
autoload -Uz _git-wt-clip
compdef _git-wt-clip git-wt-clip
autoload -Uz _git-wt-setup
compdef _git-wt-setup git-wt-setup

# Offer the commands, with descriptions, when completing `git <TAB>`.
zstyle ':completion:*:*:git:*' user-commands \
    seed:'clone a repo and grow its first worktree in one step' \
    wt-bud:'put a branch in a worktree, growing the worktree if needed' \
    wt-clip:'clip a worktree off, or with -k clip off only its branch' \
    wt-setup:'run the project .wt-setup/setup hook in a worktree'

unset _git_wt_root
