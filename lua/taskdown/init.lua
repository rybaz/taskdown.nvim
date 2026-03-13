local M = {}

function M.setup(opts)
  local config = require("taskdown.config")
  config.setup(opts)

  -- User commands
  vim.api.nvim_create_user_command("TaskAgenda", function()
    require("taskdown.agenda").open()
  end, { desc = "Open task agenda" })

  vim.api.nvim_create_user_command("TaskFind", function()
    require("taskdown.telescope").find_tasks()
  end, { desc = "Find tasks with Telescope" })

  vim.api.nvim_create_user_command("TaskNew", function()
    local row    = vim.api.nvim_win_get_cursor(0)[1]
    local target = vim.api.nvim_get_current_buf()

    vim.ui.input({ prompt = "Task: " }, function(text)
      if not text or text == "" then return end

      vim.schedule(function()
        require("taskdown.calendar").open({
          callback = function(date_str)
            if date_str then
              vim.schedule(function()
                vim.ui.input({ prompt = "Recur (blank to skip): " }, function(recur_str)
                  local line = "- [ ] " .. text .. " @due(" .. date_str .. ")"
                  if recur_str and recur_str ~= "" then
                    local r = require("taskdown.recurrence")
                    if r.parse_recur(recur_str) then
                      line = line .. " @recur(" .. recur_str .. ")"
                    end
                  end
                  vim.api.nvim_buf_set_lines(target, row, row, false, { line })
                end)
              end)
            else
              local line = "- [ ] " .. text
              vim.api.nvim_buf_set_lines(target, row, row, false, { line })
            end
          end,
        })
      end)
    end)
  end, { desc = "Insert new task below cursor" })

  -- Global keymaps
  local km = config.options.keymaps
  local prefix = km.prefix
  local function map(key, cmd, desc)
    vim.keymap.set("n", prefix .. key, cmd, { silent = true, desc = desc })
  end

  map(km.agenda, "<cmd>TaskAgenda<CR>", "Task: open agenda")
  map(km.find,   "<cmd>TaskFind<CR>",   "Task: find tasks")
  map(km.new,    "<cmd>TaskNew<CR>",    "Task: new task")

  -- which-key registration (supports both v2 and v3)
  local wk_ok, wk = pcall(require, "which-key")
  if wk_ok then
    if wk.add then
      -- which-key v3
      wk.add({
        { prefix,             group = "Tasks" },
        { prefix .. km.agenda, desc = "Agenda" },
        { prefix .. km.find,   desc = "Find tasks" },
        { prefix .. km.new,    desc = "New task" },
      })
    else
      -- which-key v2
      wk.register({
        [prefix] = {
          name = "Tasks",
          [km.agenda] = { "<cmd>TaskAgenda<CR>", "Agenda" },
          [km.find]   = { "<cmd>TaskFind<CR>",   "Find tasks" },
          [km.new]    = { "<cmd>TaskNew<CR>",    "New task" },
        },
      })
    end
  end
end

-- Convenience accessors
M.agenda = function() require("taskdown.agenda").open() end
M.find   = function() require("taskdown.telescope").find_tasks() end

return M
