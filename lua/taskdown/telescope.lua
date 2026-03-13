local M = {}

function M.find_tasks()
  local ok, _ = pcall(require, "telescope")
  if not ok then
    vim.notify("taskdown: telescope.nvim not found", vim.log.levels.WARN)
    return
  end

  local pickers      = require("telescope.pickers")
  local finders      = require("telescope.finders")
  local conf         = require("telescope.config").values
  local actions      = require("telescope.actions")
  local action_state = require("telescope.actions.state")
  local entry_disp   = require("telescope.pickers.entry_display")

  local parser     = require("taskdown.parser")
  local recurrence = require("taskdown.recurrence")
  local config     = require("taskdown.config")

  local today = recurrence.today()
  local tasks = vim.tbl_filter(
    function(t) return not t.done end,
    parser.get_all_tasks()
  )

  -- Sort: overdue first, then by due date, then no-date
  table.sort(tasks, function(a, b)
    local a_due = a.due or "9999-99-99"
    local b_due = b.due or "9999-99-99"
    return a_due < b_due
  end)

  local displayer = entry_disp.create({
    separator = "  ",
    items = {
      { width = 2 },   -- bullet
      { width = 36 },  -- task text
      { width = 10 },  -- due date
      { remaining = true }, -- file ref
    },
  })

  local function hl_for(task)
    if task.due and task.due < today then return "TaskdownOverdue"
    elseif task.due and task.due == today then return "TaskdownToday"
    elseif task.due then return "TaskdownUpcoming"
    else return "TaskdownNoDate"
    end
  end

  local function make_display(entry)
    local task = entry.value
    local ref = task.file:gsub("^" .. vim.pesc(config.options.vault_dir) .. "/", "")
      .. ":" .. task.lnum
    local due_str = task.due or ""
    local hl = hl_for(task)
    return displayer({
      { "○", hl },
      { task.text, "Normal" },
      { due_str, "TaskdownNoDate" },
      { ref, "TaskdownFileRef" },
    })
  end

  pickers.new({}, {
    prompt_title = "Tasks",
    finder = finders.new_table({
      results = tasks,
      entry_maker = function(task)
        return {
          value   = task,
          display = make_display,
          ordinal = (task.due or "9999") .. " " .. task.text,
        }
      end,
    }),
    sorter = conf.generic_sorter({}),
    attach_mappings = function(prompt_bufnr, _)
      actions.select_default:replace(function()
        actions.close(prompt_bufnr)
        local sel = action_state.get_selected_entry()
        if sel then
          local task = sel.value
          vim.cmd("edit " .. vim.fn.fnameescape(task.file))
          vim.api.nvim_win_set_cursor(0, { task.lnum, 0 })
        end
      end)
      return true
    end,
  }):find()
end

return M
