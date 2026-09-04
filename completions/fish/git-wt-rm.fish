# fish completion for `git wt-rm` and for the standalone
# `git-wt-rm` command.
#
# This registers completions for `git` itself, so it has to be loaded before
# you complete a git command. Install it into ~/.config/fish/conf.d/, not
# ~/.config/fish/completions/ (which is only loaded when completing a command
# of the same name).

function __git_wt_worktree_names --description 'Worktree names of the current repo, excluding the bare one'
    # `git wt-rm` takes a name, not a path, so report the last path
    # segment. The bare repo is skipped: it isn't a worktree to remove.
    command git worktree list --porcelain 2>/dev/null | awk '
        /^worktree /{wt = substr($0, 10); bare = 0}
        /^bare$/{bare = 1}
        /^$/{if (wt != "" && !bare) print wt; wt = ""}
        END{if (wt != "" && !bare) print wt}
    ' | sed 's|.*/||'
end

function __git_wt_rm_at --argument-names want \
    --description 'Test whether the non-option argument being completed is at the given position'
    set -l tokens (commandline --current-process --tokenize --cut-at-cursor)
    set -l idx 0

    # Find the sub-command so argument positions come out the same whether we
    # were reached as `git wt-rm` or as `git-wt-rm`.
    for i in (seq (count $tokens))
        switch $tokens[$i]
            case wt-rm git-wt-rm '*/git-wt-rm'
                set idx $i
                break
        end
    end

    test $idx -eq 0; and return 1

    # Count only the non-option tokens, so the name completes whether or not
    # -f was given.
    set -l args 0
    for i in (seq (math $idx + 1) (count $tokens))
        string match -q -- '-*' $tokens[$i]; or set args (math $args + 1)
    end
    test $args -eq (math $want - 1)
end

# [-f] <worktree_name>: the flags, plus the one name.
complete -c git-wt-rm -f
complete -c git-wt-rm -s f -d 'Remove a locked worktree, or one with modified or untracked files'
complete -c git-wt-rm -s h -d 'Print help and exit'
complete -c git-wt-rm -n '__git_wt_rm_at 1' \
    -a '(__git_wt_worktree_names)' -d Worktree
complete -c git -n '__git_wt_rm_at 1' \
    -a '(__git_wt_worktree_names)' -d Worktree
