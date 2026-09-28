# lazygit

[lazygit](https://github.com/jesseduffield/lazygit) has a worktrees panel, and
these commands are worktree-shaped, so they wire up as custom commands with no
glue. The panel becomes the whole cycle: grow a worktree, prepare it, park it,
keep it current, remove it.

**Worktrees panel**

| Key | Command | What it does |
| --- | --- | --- |
| `b` | `git wt-bud` | Prompts for worktree name, base branch, and an optional new branch |
| `s` | `git wt-setup` | Runs the project's `.wt-setup/setup` hook in the selected worktree |
| `c` | `git wt-clip -k` | Parks the selected worktree: keeps the directory, frees its branch |
| `S` | `git wt-sync` | Fetches, then brings the selected parked worktree up to mainline |
| `d` | *(built-in)* | Removes the worktree — lazygit already runs `git worktree remove` |

**Local branches panel**

| Key | Command | What it does |
| --- | --- | --- |
| `S` | `git wt-sync` | Fetches, then brings *every* parked worktree up to mainline |
| `f` | *(built-in)* | Fast-forwards the selected branch from its upstream |

There's deliberately no binding for plain `git wt-clip`. lazygit's own `d` does
the same `git worktree remove`, so the only clip worth a key is `-k`, which
lazygit has no equivalent for.

Nothing installs these. `install.sh` only touches `~/.local/bin` and the
completions; this is a snippet you paste into your own lazygit config.

## Config

Add to `customCommands` in `~/.config/lazygit/config.yml`:

```yaml
customCommands:
  - key: 'b'
    command: 'git wt-bud "{{index .PromptResponses 0}}" "{{index .PromptResponses 1}}"{{if index .PromptResponses 2}} "{{index .PromptResponses 2}}"{{end}}'
    context: 'worktrees'
    description: 'Bud a branch onto a worktree, growing the worktree if needed (wt-bud)'
    output: none
    prompts:
      - type: 'input'
        title: 'Worktree name'
      - type: 'input'
        title: 'Base branch'
        suggestions:
          preset: 'refs'
      - type: 'input'
        title: 'New branch name (blank to check out the base branch as-is)'
  - key: 's'
    command: 'git wt-setup "{{.SelectedWorktree.Path}}"'
    context: 'worktrees'
    description: "Run the project's setup hook against the worktree (wt-setup)"
    output: popup
  - key: 'c'
    command: 'git wt-clip -k "$(basename "{{.SelectedWorktree.Path}}")"'
    context: 'worktrees'
    description: 'Clip the branch off the worktree, keeping the directory (wt-clip -k)'
    output: none
  - key: 'S'
    command: 'git wt-sync "$(basename "{{.SelectedWorktree.Path}}")"'
    context: 'worktrees'
    description: 'Bring the parked worktree up to date with the default branch (wt-sync)'
    output: popup
  - key: 'S'
    command: 'git wt-sync'
    context: 'localBranches'
    description: 'Bring every parked worktree up to date with the default branch (wt-sync)'
    output: popup
```

## Why it's written this way

**`basename` on three of the four.** `git wt-bud`, `git wt-clip` and
`git wt-sync` take a worktree *name*, which they join onto the project root;
`git wt-setup` takes a *path*. lazygit only offers `{{.SelectedWorktree.Path}}`,
so the first three run it through `basename` and `wt-setup` uses it as-is.

`{{.SelectedWorktree.Name}}` looks like the tidier spelling, but `Name` is a
method on lazygit's worktree model rather than a struct field, and `Path` is
the field their own docs use. `basename` doesn't depend on which.

**The optional third prompt.** lazygit templates are Go `text/template`, so a
blank answer can drop the argument entirely:

```
["wt1", "main", ""]         ->  git wt-bud "wt1" "main"
["wt1", "main", "feature"]  ->  git wt-bud "wt1" "main" "feature"
```

An empty string is falsy in Go templates, so `{{if index .PromptResponses 2}}`
is all it takes. That maps the blank case onto `wt-bud`'s two-argument form —
check out the base branch as it stands rather than branching off it.

**`PromptResponses`, not `Form`.** Newer lazygit lets a prompt carry a `key`
and be read back as `{{.Form.<key>}}`. That is not available in 0.65.1 —
`{{index .PromptResponses N}}` is, and works across versions, at the cost of
being positional. If you add or reorder prompts, renumber the indices.

**`preset: 'refs'` on the base branch.** `wt-bud` documents its second argument
as a branch *or any commit-ish*, so tags and remote branches are legitimate
start points; `refs` completes all of them, where `branches` would hide two
thirds. The list filters as you type. Whether that filtering is fuzzy or
substring is not a per-prompt setting — it's global:

```yaml
gui:
  filterMode: 'fuzzy'    # default is 'substring'
```

Substring mode already matches space-separated fragments, so `feat auth` finds
`feature/auth-fix`. Fuzzy also gets you `fauth`, and applies to `/` filtering
in every other panel too. lazygit moved the default away from fuzzy in 0.41
because it matched too loosely, so try substring before changing it.

**`output: popup` on `s`.** `b` and `c` have nothing to say on success, and
`none` keeps them to a spinner and a refresh. `wt-setup` is the command whose
*silence* is a real result:

```
No setup hook at /home/you/code/project_a/.wt-setup/setup; nothing to do.
```

That's an exit `0` — the hook is optional, and its absence is the normal state
for most repos. A popup shows it as the ordinary output it is, and still
distinguishes it from `Error: … exists but is not executable`, which is a
genuine misconfiguration. Under `output: none` both cases look identical from
the panel.

The tradeoff is that a real hook's output also lands in the popup, after the
fact. Setup hooks are the slow command of the set — that's why `wt-setup` is
separate from `wt-bud` in the first place — so if you'd rather watch an
`npm install` scroll, use `output: terminal`, or `output: logWithPty` together
with `gui.showCommandLog: true`.

**`S` in two panels, doing two things.** `wt-sync` with a name syncs that one
worktree; with no argument it syncs all of them. The worktrees panel always has
a worktree selected, so it gets the first form; the local branches panel has no
worktree to select, so it gets the second. Same key, same command, and the
panel you're standing in decides the scope.

**Why not `f`.** `f` is the obvious mnemonic, and in the local branches panel
it's already `fastForward` — lazygit fast-forwards the selected branch from its
upstream without checking it out. That is the branch-level version of what
`wt-sync` does for parked worktrees, so the two belong side by side rather than
one shadowing the other. `S` is free in both panels, and your remotes panel may
already use it for `git fetch -p`, which keeps the letter meaning roughly the
same thing everywhere.

**`output: popup` on both.** Like `wt-setup`, `wt-sync`'s report *is* its
result — which worktrees moved, which were skipped and why:

```
Syncing to origin/main (9b2e105):
  wt1: 3a4f2c1 -> 9b2e105 (origin/main)
  wt2: skipped, parked at 7c13d80, which is not on origin/main
  wt3: skipped, modified or untracked files
Synced 1 of 3 parked worktrees, 2 skipped.
```

Under `output: none` a run where everything was skipped looks exactly like one
where everything worked. Selecting a live worktree by mistake is the same
story: `wt-sync` says the worktree is on a branch and exits 0, which you want
to actually see.

**No `-n`.** Both bindings fetch. `-n` exists for the case where something else
just did — chaining `wt-sync` onto lazygit's own fetch key, or looping over
several repos — and neither binding is that case.

**Errors surface either way.** A non-zero exit returns an error to lazygit,
which shows it in the usual error popup, so the guard rails — a dirty worktree,
a locked worktree, an unknown ref — don't fail quietly under `output: none`.

## Notes

Custom commands take precedence over built-in keybindings, so `b`, `s`, and `c`
win in the worktrees panel even if a future lazygit binds them.

`c` on the worktree lazygit is currently running in is fine — the directory
survives, that's the point of `-k`. The same is not true of `d`, which removes
the directory out from under the running instance.

Neither `b` nor `c` passes `-f`, so a worktree with modified or untracked files
is an error rather than a silent discard. Run the forced variant from a shell
when you actually mean it. `S` doesn't pass `-f` either, but it skips such a
worktree instead of failing, and still syncs the rest.
