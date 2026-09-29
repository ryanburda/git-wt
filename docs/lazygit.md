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
    description: 'Create a worktree with a branch checked out (wt-add)'
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
