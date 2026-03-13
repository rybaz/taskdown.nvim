# taskdown.nvim

A task management plugin for Neovim. Tasks live as standard markdown checkboxes
inside any prose — no special file formats, no GUI lock-in.

## Task syntax

```markdown
- [ ] Task text @due(YYYY-MM-DD) @recur(pattern)
- [x] Completed task @due(YYYY-MM-DD) @done(YYYY-MM-DD)
- [w] Waiting task @due(YYYY-MM-DD)
- [/] In-progress task @due(YYYY-MM-DD)
- [-] Cancelled task @due(YYYY-MM-DD)
```

Tasks can appear anywhere in a markdown file, mixed with regular writing. The
only requirement is the standard `- [ ]` checkbox prefix.

Checkbox states: `[ ]` open, `[x]` done, `[w]` waiting, `[/]` in-progress, `[-]` cancelled.

### Recurrence patterns

| Pattern          | Meaning         |
|------------------|-----------------|
| `daily`          | Every day       |
| `weekly`         | Every 7 days    |
| `monthly`        | Every 1 month   |
| `yearly`         | Every 1 year    |
| `every N days`   | Every N days    |
| `every N weeks`  | Every N weeks   |
| `every N months` | Every N months  |

When a recurring task is marked done, a new open task is automatically inserted
after it with the next due date.

## Installation

Using lazy.nvim with a local directory:

```lua
{
  dir = "~/path/to/taskdown.nvim",
  cmd = { "TaskAgenda", "TaskFind", "TaskNew" },
  keys = {
    { "<leader>ta", "<cmd>TaskAgenda<CR>", desc = "Task: agenda" },
    { "<leader>tf", "<cmd>TaskFind<CR>",   desc = "Task: find" },
    { "<leader>tn", "<cmd>TaskNew<CR>",    desc = "Task: new" },
  },
  config = function()
    require("taskdown").setup({
      vault_dir = vim.fn.expand("~/notes"),
    })
  end,
}
```

## Configuration

All options and their defaults:

```lua
require("taskdown").setup({
  -- Directory to scan for markdown files (recursive).
  vault_dir = vim.fn.getcwd(),

  -- How many days ahead to show in the UPCOMING section.
  agenda_days_ahead = 14,

  -- Keymap prefix and individual keys.
  keymaps = {
    prefix = "<leader>t",
    agenda = "a",   -- <leader>ta
    find   = "f",   -- <leader>tf
    new    = "n",   -- <leader>tn
  },

  -- Agenda floating window dimensions (as a ratio of the editor size).
  float = {
    width_ratio  = 0.65,
    height_ratio = 0.70,
    border       = "rounded",
  },
})
```

## Commands

| Command       | Description                                      |
|---------------|--------------------------------------------------|
| `:TaskAgenda` | Open the agenda floating window                  |
| `:TaskFind`   | Open a Telescope picker of all open tasks        |
| `:TaskNew`    | Insert a new task below the cursor               |

## Agenda

The agenda scans `vault_dir` recursively for all `.md` files and groups tasks
into sections:

- **OVERDUE** — tasks with a due date in the past
- **TODAY** — tasks due today
- **UPCOMING** — tasks due within the next `agenda_days_ahead` days

Only tasks with due dates appear. Tasks beyond the upcoming window are omitted.
Within each section, active tasks sort before cancelled, then done.

### Agenda keybindings

| Key     | Action                              |
|---------|-------------------------------------|
| `x`     | Toggle task done/undone             |
| `w`     | Toggle waiting state                |
| `i`     | Toggle in-progress state            |
| `-`     | Toggle cancelled state              |
| `e`     | Edit task text (inline prompt)      |
| `d`     | Set due date (calendar picker)      |
| `<CR>`  | Jump to the task in its source file |
| `r`     | Refresh the agenda                  |
| `q`     | Close                               |
| `<Esc>` | Close                               |

## Integrations

**Telescope** — `:TaskFind` opens a picker of all open tasks sorted by due date.
Selecting an entry jumps to the task in its source file. Requires
`nvim-telescope/telescope.nvim`.

**which-key** — if `which-key.nvim` is installed, the `<leader>t` prefix is
registered with descriptions automatically. Both v2 and v3 are supported.
