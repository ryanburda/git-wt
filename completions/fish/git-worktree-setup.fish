# fish completion for `git worktree-setup` and for the standalone
# `git-worktree-setup` command.
#
# This registers completions for `git` itself, so it has to be loaded before
# you complete a git command — install it into ~/.config/fish/conf.d/, not
# ~/.config/fish/completions/ (which is only loaded when completing a command
# of the same name).

function __git_ext_worktrees --description 'Worktrees of the current repo, excluding the bare one'
    command git worktree list --porcelain 2>/dev/null | awk '
        /^worktree /{wt = substr($0, 10); bare = 0}
        /^bare$/{bare = 1}
        /^$/{if (wt != "" && !bare) print wt; wt = ""}
        END{if (wt != "" && !bare) print wt}
    '
end

function __git_ext_worktree_setup_at --argument-names want \
    --description 'Test whether the argument being completed is at the given position'
    set -l tokens (commandline --current-process --tokenize --cut-at-cursor)
    set -l idx 0

    # Find the sub-command so argument positions come out the same whether we
    # were reached as `git worktree-setup` or as `git-worktree-setup`.
    for i in (seq (count $tokens))
        switch $tokens[$i]
            case worktree-setup git-worktree-setup '*/git-worktree-setup'
                set idx $i
                break
        end
    end

    test $idx -eq 0; and return 1
    test (math (count $tokens) - $idx + 1) -eq $want
end

# [<worktree_path>] — the one optional argument.
complete -c git-worktree-setup -f
complete -c git-worktree-setup -n '__git_ext_worktree_setup_at 1' \
    -a '(__git_ext_worktrees)' -d Worktree
complete -c git -n '__git_ext_worktree_setup_at 1' \
    -a '(__git_ext_worktrees)' -d Worktree
