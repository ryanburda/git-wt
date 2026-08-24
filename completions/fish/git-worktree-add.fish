# fish completion for `git worktree-add` and for the standalone
# `git-worktree-add` command.
#
# This registers completions for `git` itself, so it has to be loaded before
# you complete a git command — install it into ~/.config/fish/conf.d/, not
# ~/.config/fish/completions/ (which is only loaded when completing a command
# of the same name).

function __git_ext_worktree_add_branches --description 'Branches accepted by git worktree-add'
    # Local branches, plus remote branches with the remote name stripped:
    # `git worktree add` resolves a bare `topic` to `origin/topic` itself.
    begin
        command git for-each-ref --format='%(refname:short)' refs/heads
        command git for-each-ref --format='%(refname:strip=3)' refs/remotes
    end 2>/dev/null | string match --invert HEAD | sort -u
end

function __git_ext_worktree_add_at --argument-names want \
    --description 'Test whether the argument being completed is at the given position'
    set -l tokens (commandline --current-process --tokenize --cut-at-cursor)
    set -l idx 0

    # Find the sub-command so argument positions come out the same whether we
    # were reached as `git worktree-add` or as `git-worktree-add`.
    for i in (seq (count $tokens))
        switch $tokens[$i]
            case worktree-add git-worktree-add '*/git-worktree-add'
                set idx $i
                break
        end
    end

    test $idx -eq 0; and return 1
    test (math (count $tokens) - $idx + 1) -eq $want
end

# <worktree_name> <branch> [<new_branch>] — only <branch> is completable.
complete -c git-worktree-add -f
complete -c git-worktree-add -n '__git_ext_worktree_add_at 2' \
    -a '(__git_ext_worktree_add_branches)' -d Branch
complete -c git -n '__git_ext_worktree_add_at 2' \
    -a '(__git_ext_worktree_add_branches)' -d Branch
