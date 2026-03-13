local M = {}

local config = require("taskdown.config")
local parser = require("taskdown.parser")
local recurrence = require("taskdown.recurrence")

-- Window/buffer state
local state = {
  buf = nil,
  win = nil,
  line_tasks = {}, -- lnum (1-indexed) → task object
}

local function is_valid()
  return state.win ~= nil and vim.api.nvim_win_is_valid(state.win)
end

local function close()
  if is_valid() then
    vim.api.nvim_win_close(state.win, true)
  end
  state.win = nil
  state.buf = nil
  state.line_tasks = {}
end

local function setup_highlights()
  vim.api.nvim_set_hl(0, "TaskdownOverdue",  { fg = "#f38ba8", bold = true })
  vim.api.nvim_set_hl(0, "TaskdownToday",    { fg = "#a6e3a1", bold = true })
  vim.api.nvim_set_hl(0, "TaskdownUpcoming", { fg = "#89b4fa" })
  vim.api.nvim_set_hl(0, "TaskdownWaiting",    { fg = "#f9e2af" })
  vim.api.nvim_set_hl(0, "TaskdownInProgress", { fg = "#89dceb" })
  vim.api.nvim_set_hl(0, "TaskdownCancelled",  { fg = "#6c7086", strikethrough = true })
  vim.api.nvim_set_hl(0, "TaskdownDone",       { fg = "#585b70", strikethrough = true })
  vim.api.nvim_set_hl(0, "TaskdownFileRef",  { fg = "#45475a" })
  vim.api.nvim_set_hl(0, "TaskdownSection",  { fg = "#cba6f7", bold = true })
  vim.api.nvim_set_hl(0, "TaskdownHeader",   { fg = "#cdd6f4", bold = true })
  vim.api.nvim_set_hl(0, "TaskdownSep",      { fg = "#313244" })
  vim.api.nvim_set_hl(0, "TaskdownHint",     { fg = "#585b70" })
end

-- Relative path from vault_dir
local function rel_path(file)
  local vault = config.options.vault_dir
  return file:gsub("^" .. vim.pesc(vault) .. "/", "")
end

-- Format "YYYY-MM-DD" as "Mar 09"
local function fmt_date(date_str)
  if not date_str then return "" end
  local y, m, d = date_str:match("(%d%d%d%d)-(%d%d)-(%d%d)")
  if not y then return date_str end
  return os.date("%b %d", os.time({ year = tonumber(y), month = tonumber(m), day = tonumber(d), hour = 12 }))
end

local function categorize(tasks)
  local today  = recurrence.today()
  local cutoff = recurrence.today_plus(config.options.agenda_days_ahead)
  local overdue, todays, upcoming = {}, {}, {}

  for _, t in ipairs(tasks) do
    if not t.due then
      -- no due date: omit from agenda
    elseif t.due < today then
      table.insert(overdue, t)
    elseif t.due == today then
      table.insert(todays, t)
    elseif t.due <= cutoff then
      table.insert(upcoming, t)
    end
    -- beyond cutoff: omit
  end

  -- Within each section: active (open/waiting/in-progress) first,
  -- then cancelled, then done; stable by due date within each group
  local function sort_section(s)
    local function rank(t)
      if t.done      then return 3 end
      if t.cancelled then return 2 end
      return 1
    end
    table.sort(s, function(a, b)
      local ra, rb = rank(a), rank(b)
      if ra ~= rb then return ra < rb end
      return a.due < b.due
    end)
  end

  sort_section(overdue)
  sort_section(upcoming)

  return overdue, todays, upcoming
end

local function render(tasks)
  local buf = state.buf
  local win = state.win
  local win_width = vim.api.nvim_win_get_width(win) - 2

  local lines = {}
  local line_tasks = {}
  local hls = {} -- { lnum0, col_s, col_e, hl }

  local function push(text, hl, task)
    table.insert(lines, text)
    local lnum0 = #lines - 1
    if hl then table.insert(hls, { lnum0, 0, -1, hl }) end
    if task then line_tasks[#lines] = task end
  end

  local function separator()
    push(string.rep("─", win_width), "TaskdownSep")
  end

  local function task_line(task)
    local bullet = task.done and "✓"
      or (task.cancelled   and "-")
      or (task.in_progress and "/")
      or (task.waiting     and "~")
      or "○"
    local ref = rel_path(task.file) .. ":" .. task.lnum
    local date_part = (not task.done and task.due and task.due ~= recurrence.today())
      and fmt_date(task.due) or ""

    -- Build line: "  ○ <text>   <date>   <ref>"
    local fixed = 2 + #bullet + 1 + (date_part ~= "" and #date_part + 2 or 0) + #ref + 2
    local max_text = win_width - fixed
    local text = task.text
    if #text > max_text then text = text:sub(1, max_text - 1) .. "…" end

    local middle
    if date_part ~= "" then
      local gap = win_width - 2 - #bullet - 1 - #text - #date_part - #ref - 2
      middle = text .. string.rep(" ", math.max(1, gap)) .. date_part .. "  " .. ref
    else
      local gap = win_width - 2 - #bullet - 1 - #text - #ref
      middle = text .. string.rep(" ", math.max(1, gap)) .. ref
    end

    local line = "  " .. bullet .. " " .. middle

    local hl
    if task.done then
      hl = "TaskdownDone"
    elseif task.cancelled then
      hl = "TaskdownCancelled"
    elseif task.in_progress then
      hl = "TaskdownInProgress"
    elseif task.waiting then
      hl = "TaskdownWaiting"
    elseif task.due and task.due < recurrence.today() then
      hl = "TaskdownOverdue"
    elseif task.due and task.due == recurrence.today() then
      hl = "TaskdownToday"
    else
      hl = "TaskdownUpcoming"
    end

    push(line, hl, task)
  end

  local function section(title, items)
    if #items == 0 then return end
    push(" " .. title, "TaskdownSection")
    for _, t in ipairs(items) do task_line(t) end
    separator()
  end

  -- Header
  local hint = "[x] done  [w] wait  [i] wip  [-] cancel  [e] edit  [<CR>] jump  [d] date  [r] refresh  [q] quit"
  local gap = math.max(1, win_width - #hint - 1)
  push(" taskdown" .. string.rep(" ", gap) .. hint, "TaskdownHeader")
  push(" " .. config.options.vault_dir, "TaskdownHint")
  separator()

  local overdue, todays, upcoming = categorize(tasks)

  -- Overdue
  if #overdue > 0 then
    section("OVERDUE (" .. #overdue .. ")", overdue)
  end

  -- Today
  local today_title = os.date("TODAY  %a %b %d", os.time())
  if #todays > 0 then
    section(today_title, todays)
  else
    push(" " .. today_title, "TaskdownSection")
    push("   nothing scheduled", "TaskdownHint")
    separator()
  end

  -- Upcoming
  if #upcoming > 0 then
    section("UPCOMING — next " .. config.options.agenda_days_ahead .. " days", upcoming)
  end

  -- Write to buffer
  vim.api.nvim_set_option_value("modifiable", true, { buf = buf })
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.api.nvim_set_option_value("modifiable", false, { buf = buf })

  -- Apply highlights
  local ns = vim.api.nvim_create_namespace("taskdown")
  vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
  for _, h in ipairs(hls) do
    vim.api.nvim_buf_add_highlight(buf, ns, h[4], h[1], h[2], h[3])
  end

  state.line_tasks = line_tasks
end

-- Write a modified line (and optional new line) back to the source
local function write_to_source(task, new_raw, insert_before)
  local file_buf = vim.fn.bufnr(vim.fn.fnamemodify(task.file, ":p"))
  local lnum0 = task.lnum - 1

  if file_buf ~= -1 and vim.api.nvim_buf_is_loaded(file_buf) then
    local replacement = insert_before and { insert_before, new_raw } or { new_raw }
    vim.api.nvim_buf_set_lines(file_buf, lnum0, lnum0 + 1, false, replacement)
  else
    local lines = vim.fn.readfile(task.file)
    lines[task.lnum] = new_raw
    if insert_before then
      table.insert(lines, task.lnum, insert_before)
    end
    vim.fn.writefile(lines, task.file)
  end
end

local function toggle_waiting(task)
  if task.done then return end
  local new_raw
  if task.waiting then
    new_raw = task.raw:gsub("%[w%]", "[ ]", 1)
  else
    new_raw = task.raw:gsub("%[ %]", "[w]", 1)
  end
  write_to_source(task, new_raw)
end

local function toggle_in_progress(task)
  if task.done then return end
  local new_raw
  if task.in_progress then
    new_raw = task.raw:gsub("%[/%]", "[ ]", 1)
  else
    new_raw = task.raw:gsub("%[[ w%-]%]", "[/]", 1)
  end
  write_to_source(task, new_raw)
end

local function toggle_cancelled(task)
  if task.done then return end
  local new_raw
  if task.cancelled then
    new_raw = task.raw:gsub("%[%-%]", "[ ]", 1)
  else
    new_raw = task.raw:gsub("%[[ w/]%]", "[-]", 1)
  end
  write_to_source(task, new_raw)
end

local function set_due(task)
  require("taskdown.calendar").open({
    default = task.due,
    callback = function(date_str)
      if not date_str then return end
      local new_raw
      if task.due then
        new_raw = task.raw:gsub("@due%([^%)]*%)", "@due(" .. date_str .. ")", 1)
      else
        new_raw = task.raw .. " @due(" .. date_str .. ")"
      end
      write_to_source(task, new_raw)
      M.refresh()
    end,
  })
end

local function edit_task(task)
  vim.ui.input({ prompt = "Edit task: ", default = task.text }, function(new_text)
    if not new_text or new_text == "" or new_text == task.text then return end
    local updated = vim.tbl_extend("force", task, { text = new_text })
    local new_raw = require("taskdown.parser").build_line(updated)
    write_to_source(task, new_raw)
    M.refresh()
  end)
end

local function toggle_task(task)
  if task.done then
    -- Mark undone: restore [ ], remove @done
    local new_raw = task.raw
      :gsub("%[x%]", "[ ]", 1)
      :gsub("%s*@done%([^%)]*%)", "")
    write_to_source(task, new_raw)
  else
    -- Mark done: set [x], add @done (handles all active states)
    local today = recurrence.today()
    local new_raw = task.raw:gsub("%[[ w/%-]%]", "[x]", 1)
    if not new_raw:match("@done%(") then
      new_raw = new_raw .. " @done(" .. today .. ")"
    end

    -- If recurring, insert next occurrence above the completed task
    local insert_before = nil
    if task.recur then
      local next_due = recurrence.next_date(task.due, task.recur)
      if next_due then
        insert_before = task.indent .. "- [ ] " .. task.text
          .. " @due(" .. next_due .. ")"
          .. " @recur(" .. task.recur .. ")"
      end
    end

    write_to_source(task, new_raw, insert_before)
  end
end

function M.refresh()
  if not is_valid() then return end
  render(parser.get_all_tasks())
end

local function setup_keymaps()
  local buf = state.buf
  local map = function(lhs, fn, desc)
    vim.keymap.set("n", lhs, fn, { buffer = buf, noremap = true, silent = true, desc = desc })
  end

  map("q",     close, "Close agenda")
  map("<Esc>", close, "Close agenda")
  map("r",     M.refresh, "Refresh agenda")

  map("<CR>", function()
    local lnum = vim.api.nvim_win_get_cursor(state.win)[1]
    local task = state.line_tasks[lnum]
    if not task then return end
    close()
    vim.cmd("edit " .. vim.fn.fnameescape(task.file))
    vim.api.nvim_win_set_cursor(0, { task.lnum, 0 })
  end, "Jump to task source")

  map("x", function()
    local lnum = vim.api.nvim_win_get_cursor(state.win)[1]
    local task = state.line_tasks[lnum]
    if not task then return end
    toggle_task(task)
    M.refresh()
  end, "Toggle task done")

  map("w", function()
    local lnum = vim.api.nvim_win_get_cursor(state.win)[1]
    local task = state.line_tasks[lnum]
    if not task then return end
    toggle_waiting(task)
    M.refresh()
  end, "Toggle task waiting")

  map("i", function()
    local lnum = vim.api.nvim_win_get_cursor(state.win)[1]
    local task = state.line_tasks[lnum]
    if not task then return end
    toggle_in_progress(task)
    M.refresh()
  end, "Toggle task in-progress")

  map("-", function()
    local lnum = vim.api.nvim_win_get_cursor(state.win)[1]
    local task = state.line_tasks[lnum]
    if not task then return end
    toggle_cancelled(task)
    M.refresh()
  end, "Toggle task cancelled")

  map("d", function()
    local lnum = vim.api.nvim_win_get_cursor(state.win)[1]
    local task = state.line_tasks[lnum]
    if not task then return end
    set_due(task)
  end, "Set due date")

  map("e", function()
    local lnum = vim.api.nvim_win_get_cursor(state.win)[1]
    local task = state.line_tasks[lnum]
    if not task then return end
    edit_task(task)
  end, "Edit task text")
end

function M.open()
  if is_valid() then
    vim.api.nvim_set_current_win(state.win)
    return
  end

  setup_highlights()

  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_set_option_value("buftype",   "nofile", { buf = buf })
  vim.api.nvim_set_option_value("bufhidden", "wipe",   { buf = buf })
  vim.api.nvim_set_option_value("filetype",  "taskdown-agenda", { buf = buf })

  local width  = math.floor(vim.o.columns * config.options.float.width_ratio)
  local height = math.floor(vim.o.lines   * config.options.float.height_ratio)
  local row    = math.floor((vim.o.lines   - height) / 2)
  local col    = math.floor((vim.o.columns - width)  / 2)

  local win = vim.api.nvim_open_win(buf, true, {
    relative   = "editor",
    row        = row,
    col        = col,
    width      = width,
    height     = height,
    style      = "minimal",
    border     = config.options.float.border,
    title      = " Task Agenda ",
    title_pos  = "center",
  })

  vim.api.nvim_set_option_value("cursorline", true,  { win = win })
  vim.api.nvim_set_option_value("wrap",       false, { win = win })

  state.buf = buf
  state.win = win

  render(parser.get_all_tasks())
  setup_keymaps()

  -- Place cursor on first task line (line 4, after header/path/sep)
  vim.api.nvim_win_set_cursor(win, { 4, 0 })
end

return M
