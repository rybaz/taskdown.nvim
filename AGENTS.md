# taskdown.nvim — project context for coding agents

## What this is

A Neovim task management plugin written in Lua. Goals: markdown-native task
syntax, agenda view aggregating tasks across a directory, recurrence support.
No org-mode, no special file format.

## File structure

```
lua/taskdown/
  init.lua        -- setup(), user commands (:TaskAgenda/:TaskFind/:TaskNew), keymaps
  config.lua      -- default options; merged with user opts in setup()
  parser.lua      -- parse_file(), get_all_tasks(), build_line()
  recurrence.lua  -- parse_recur(), next_date(), today(), today_plus()
  agenda.lua      -- floating window UI; owns all window/buffer state
  calendar.lua    -- date picker floating window; M.open({ callback, default })
  telescope.lua   -- telescope picker (gracefully no-ops if telescope absent)
plugin/taskdown.lua    -- load guard only; no auto-setup
test/                  -- sample .md files for manual testing
README.md
```

## Task syntax

```markdown
- [ ] Task text @due(YYYY-MM-DD) @recur(pattern)
- [x] Completed task @due(YYYY-MM-DD) @recur(pattern) @done(YYYY-MM-DD)
- [w] Waiting task @due(YYYY-MM-DD)
- [/] In-progress task @due(YYYY-MM-DD)
- [-] Cancelled task @due(YYYY-MM-DD)
```

Checkbox states: `[ ]` open, `[x]` done, `[w]` waiting, `[/]` in-progress, `[-]` cancelled.

Recurrence patterns: `daily`, `weekly`, `monthly`, `yearly`,
`every N days/weeks/months/years`.

## Key design decisions

- `vault_dir` defaults to `vim.fn.getcwd()` at setup time (evaluated lazily
  inside `setup()` via `config.lua`, not at module load).
- Agenda sections: OVERDUE / TODAY / UPCOMING (configurable window). Only tasks
  with due dates appear. Done tasks stay in their due-date section
  (open/waiting first, cancelled next, done last within each section).
- Toggling a recurring task done inserts the next occurrence as a new line
  immediately after the completed task in the source file.
- Source file writes go through the buffer API if the file is already loaded in
  a buffer; otherwise direct `readfile`/`writefile`.
- which-key integration supports both v2 (`wk.register`) and v3 (`wk.add`).
- Lazy.nvim spec must include `cmd = { "TaskAgenda", "TaskFind", "TaskNew" }`
  (or `lazy = false`) — without a trigger the plugin never loads and commands
  are never registered.

## Agenda keymaps

| Key     | Action                                        |
|---------|-----------------------------------------------|
| `x`     | Toggle done/undone (recurring: inserts next)  |
| `w`     | Toggle waiting `[w]`                          |
| `i`     | Toggle in-progress `[/]`                      |
| `-`     | Toggle cancelled `[-]`                        |
| `e`     | Edit task text via `vim.ui.input` (pre-filled)|
| `d`     | Set due date via calendar picker              |
| `<CR>`  | Jump to task in source file, close agenda     |
| `r`     | Refresh (re-scans vault_dir)                  |
| `q`/`<Esc>` | Close                                    |

## Configuration (all defaults)

```lua
require("taskdown").setup({
  vault_dir         = vim.fn.getcwd(),
  agenda_days_ahead = 14,
  keymaps = {
    prefix = "<leader>t",
    agenda = "a",
    find   = "f",
    new    = "n",
  },
  float = {
    width_ratio  = 0.65,
    height_ratio = 0.70,
    border       = "rounded",
  },
})
```

## Dotfiles install location

`~/ryan/dotfiles/.config/nvim/lua/plugins/init.lua` — lazy.nvim plugin list.
Sourced from `rybaz/taskdown.nvim` on GitHub. The `vault_dir` currently points
at the `test/` subdirectory for development.

## Known limitations / not yet implemented

- No priority support (`@priority(...)`), should be numeric starting at 0
- No tag filtering in the agenda
- Agenda does not auto-refresh when source files change on disk
- No project/phase view (planned: `:TaskProject` command, section tracking in parser)
