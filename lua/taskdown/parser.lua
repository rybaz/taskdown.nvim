local M = {}

local config = require("taskdown.config")

-- Parse a single line into a task object, or return nil if not a task line.
-- Task format: [indent]- [ ] text @due(YYYY-MM-DD) @recur(pattern) @done(YYYY-MM-DD)
-- Checkbox states: [ ] open, [x] done, [w] waiting, [/] in-progress, [-] cancelled
local function parse_line(line, file, lnum)
  local indent, state, rest = line:match("^(%s*)%- %[([xw/ %-])%] (.+)$")
  if not indent then return nil end

  local done        = state == "x"
  local waiting     = state == "w"
  local in_progress = state == "/"
  local cancelled   = state == "-"
  local due = rest:match("@due%((%d%d%d%d%-%d%d%-%d%d)%)")
  local recur = rest:match("@recur%(([^%)]+)%)")
  local done_date = rest:match("@done%((%d%d%d%d%-%d%d%-%d%d)%)")

  -- Strip all markers to get clean task text
  local text = rest
    :gsub("%s*@due%([^%)]*%)", "")
    :gsub("%s*@recur%([^%)]*%)", "")
    :gsub("%s*@done%([^%)]*%)", "")
    :gsub("^%s+", "")
    :gsub("%s+$", "")

  return {
    text = text,
    done = done,
    waiting = waiting,
    in_progress = in_progress,
    cancelled = cancelled,
    due = due,
    recur = recur,
    done_date = done_date,
    file = file,
    lnum = lnum,
    raw = line,
    indent = indent,
  }
end

function M.parse_file(filepath)
  local lines
  local abs = vim.fn.fnamemodify(filepath, ":p")
  local file_buf = vim.fn.bufnr(abs)
  if file_buf ~= -1 and vim.api.nvim_buf_is_loaded(file_buf) then
    lines = vim.api.nvim_buf_get_lines(file_buf, 0, -1, false)
  else
    local ok, result = pcall(vim.fn.readfile, filepath)
    if not ok then return {} end
    lines = result
  end
  local tasks = {}
  for i, line in ipairs(lines) do
    local task = parse_line(line, filepath, i)
    if task then
      table.insert(tasks, task)
    end
  end
  return tasks
end

function M.get_all_tasks()
  local dir = config.options.vault_dir
  local files = vim.fn.globpath(dir, "**/*.md", false, true)
  local all_tasks = {}
  for _, file in ipairs(files) do
    for _, task in ipairs(M.parse_file(file)) do
      table.insert(all_tasks, task)
    end
  end
  return all_tasks
end

-- Build the canonical raw line for a task object
function M.build_line(task)
  local state = task.done and "x"
    or (task.waiting and "w")
    or (task.in_progress and "/")
    or (task.cancelled and "-")
    or " "
  local line = task.indent .. "- [" .. state .. "] " .. task.text
  if task.due then line = line .. " @due(" .. task.due .. ")" end
  if task.recur then line = line .. " @recur(" .. task.recur .. ")" end
  if task.done_date then line = line .. " @done(" .. task.done_date .. ")" end
  return line
end

return M
