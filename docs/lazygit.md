# lazygit

[lazygit](https://github.com/jesseduffield/lazygit) has a worktrees panel, and
these commands are worktree-shaped, so they wire up as custom commands with no
glue. The panel becomes the whole cycle: create a worktree, prepare it, park it,
keep it current, remove it.

**Worktrees panel**

| Key | Command | What it does |
| --- | --- | --- |
| `a` | `git wt-add` | Prompts for worktree name, base branch, and an optional new branch |
| `s` | `git wt-setup` | Runs the project's `.wt-setup/setup` hook in the selected worktree |
| `p` | `git wt-park` | Parks the selected worktree at mainline: keeps the directory, frees its branch |
| `d` | *(built-in)* | Removes the worktree — lazygit already runs `git worktree remove` |

Removal has no custom binding because it needs none: lazygit's own `d` runs
`git worktree remove`, which is the whole of that job. `p` is the one lazygit
has no equivalent for — parking a worktree without tearing it down, and
bringing an already-parked one up to mainline.

Nothing installs these. `install.sh` only touches `~/.local/bin` and the
completions; this is a snippet you paste into your own lazygit config.

## Config

Add to `customCommands` in `~/.config/lazygit/config.yml`:

```yaml
customCommands:
  - key: 'a'
    command: 'git wt-add "{{index .PromptResponses 0}}" "{{index .PromptResponses 1}}"{{if index .PromptResponses 2}} "{{index .PromptResponses 2}}"{{end}}'
    context: 'worktrees'
    description: 'Put a branch in a worktree, creating the worktree if needed (wt-add)'
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
  - key: 'p'
    command: 'git wt-park "$(basename "{{.SelectedWorktree.Path}}")"'
    context: 'worktrees'
    description: 'Park the worktree at the default branch, freeing its branch (wt-park)'
    output: popup
```

## Why it's written this way

**`basename` on two of the three.** `git wt-add` and `git wt-park` take a
worktree *name*, which they join onto the project root; `git wt-setup` takes a
*path*. lazygit only offers `{{.SelectedWorktree.Path}}`, so the first two run
it through `basename` and `wt-setup` uses it as-is.

`{{.SelectedWorktree.Name}}` looks like the tidier spelling, but `Name` is a
method on lazygit's worktree model rather than a struct field, and `Path` is
the field their own docs use. `basename` doesn't depend on which.

**The optional third prompt.** lazygit templates are Go `text/template`, so a
blank answer can drop the argument entirely:

```
["wt1", "main", ""]         ->  git wt-add "wt1" "main"
["wt1", "main", "feature"]  ->  git wt-add "wt1" "main" "feature"
```

An empty string is falsy in Go templates, so `{{if index .PromptResponses 2}}`
is all it takes. That maps the blank case onto `wt-add`'s two-argument form —
check out the base branch as it stands rather than branching off it.

**`PromptResponses`, not `Form`.** Newer lazygit lets a prompt carry a `key`
and be read back as `{{.Form.<key>}}`. That is not available in 0.65.1 —
`{{index .PromptResponses N}}` is, and works across versions, at the cost of
being positional. If you add or reorder prompts, renumber the indices.

**`preset: 'refs'` on the base branch.** `wt-add` documents its second argument
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

**`output: popup` on `s`.** `a` has nothing to say on success, and `none` keeps
it to a spinner and a refresh. `wt-setup` is the command whose *silence* is a
real result:

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
separate from `wt-add` in the first place — so if you'd rather watch an
`npm install` scroll, use `output: terminal`, or `output: logWithPty` together
with `gui.showCommandLog: true`.

**`output: popup` on `p`, not `none`.** `wt-park` has something to say on every
outcome, and two of them change nothing:

```
Worktree /home/you/code/project_a/wt1 kept; branch 'feature' (ff74ab3) is free.
Worktree /home/you/code/project_a/wt1 moved: 3a4f2c1 -> 9b2e105 (origin/main).
Worktree /home/you/code/project_a/wt1 is already parked at origin/main (9b2e105), skipping.
```

All three exit 0, so under `output: none` they're indistinguishable — the panel
just blinks and refreshes whether the worktree moved or not. The first one also
carries the freed branch's short SHA, which is the thing you want in front of
you if you're about to delete that branch.

**No binding in the local branches panel.** An earlier version of this doc bound
`S` there to sync the *current* worktree. That binding existed because
`wt-sync` was a no-op on a worktree that still had a branch checked out — safe
to fire from anywhere. `wt-park` is not: run bare in a worktree you're actively
working in, it detaches HEAD from that branch, which is exactly what it's for
and exactly what you don't want from a stray keypress. Name the worktree from
the worktrees panel instead, where you can see what you're pointing at.

**No `-n`.** The binding fetches. `-n` exists for the case where something else
just did — chaining `wt-park` onto lazygit's own fetch key, or looping over
several worktrees — and this binding isn't that case.

**Errors surface either way.** A non-zero exit returns an error to lazygit,
which shows it in the usual error popup, so the guard rails — a dirty worktree,
an unknown ref, a worktree that isn't there — don't fail quietly under
`output: none`.

## Notes

Custom commands take precedence over built-in keybindings, so `a`, `s`, and `p`
win in the worktrees panel even if a future lazygit binds them.

`p` on the worktree lazygit is currently running in is fine — the directory
survives, that's the point. The same is not true of `d`, which removes the
directory out from under the running instance.

Neither `a` nor `p` passes `-f`, so a worktree with modified or untracked files
is an error rather than a silent discard. Run the forced variant from a shell
when you actually mean it.
