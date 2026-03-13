local M = {}

local state = {
  buf      = nil,
  win      = nil,
  selected = nil, -- { year, month, day }
  view     = nil, -- { year, month } currently displayed
  callback = nil, -- function(date_str | nil)
  day_pos  = {},  -- day_number -> { line (1-indexed), col (0-indexed) }
}

local MONTH_NAMES = {
  "January", "February", "March",     "April",   "May",      "June",
  "July",    "August",   "September", "October", "November", "December",
}

local function days_in_month(year, month)
  local t = { 31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31 }
  if month == 2 and (year % 4 == 0 and (year % 100 ~= 0 or year % 400 == 0)) then
    return 29
  end
  return t[month]
end

-- Returns 0=Sun … 6=Sat for the first day of the given month
local function first_weekday(year, month)
  return tonumber(os.date("%w", os.time({ year = year, month = month, day = 1, hour = 12 })))
end

local function format_date(t)
  return string.format("%04d-%02d-%02d", t.year, t.month, t.day)
end

local function setup_highlights()
  vim.api.nvim_set_hl(0, "TaskdownCalHeader",   { fg = "#cba6f7", bold = true })
  vim.api.nvim_set_hl(0, "TaskdownCalDayNames", { fg = "#585b70" })
  vim.api.nvim_set_hl(0, "TaskdownCalToday",    { fg = "#a6e3a1", bold = true })
  vim.api.nvim_set_hl(0, "TaskdownCalSelected", { fg = "#1e1e2e", bg = "#cba6f7", bold = true })
end

local function render()
  local buf  = state.buf
  local year = state.view.year
  local month = state.view.month

  local today_str = os.date("%Y-%m-%d")
  local sel_str   = format_date(state.selected)

  local n_days   = days_in_month(year, month)
  local start_dow = first_weekday(year, month) -- 0=Sun

  local lines   = {}
  local day_pos = {}

  -- Line 1: month + year, centred in 20 chars
  local header = MONTH_NAMES[month] .. " " .. year
  local pad    = math.floor((20 - #header) / 2)
  table.insert(lines, string.rep(" ", pad) .. header)

  -- Line 2: day-of-week headers
  table.insert(lines, "Su Mo Tu We Th Fr Sa")

  -- Lines 3+: week rows
  local n_weeks = math.ceil((start_dow + n_days) / 7)
  for w = 0, n_weeks - 1 do
    local cells = {}
    for d = 0, 6 do
      local day_num = w * 7 + d - start_dow + 1
      if day_num < 1 or day_num > n_days then
        table.insert(cells, "  ")
      else
        day_pos[day_num] = { line = w + 3, col = d * 3 }
        table.insert(cells, string.format("%2d", day_num))
      end
    end
    table.insert(lines, table.concat(cells, " "))
  end

  state.day_pos = day_pos

  -- Write buffer
  vim.api.nvim_set_option_value("modifiable", true,  { buf = buf })
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.api.nvim_set_option_value("modifiable", false, { buf = buf })

  -- Highlights
  local ns = vim.api.nvim_create_namespace("taskdown-calendar")
  vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
  vim.api.nvim_buf_add_highlight(buf, ns, "TaskdownCalHeader",   0, 0, -1)
  vim.api.nvim_buf_add_highlight(buf, ns, "TaskdownCalDayNames", 1, 0, -1)

  for day_num, pos in pairs(day_pos) do
    local date_str = string.format("%04d-%02d-%02d", year, month, day_num)
    local hl
    if date_str == sel_str then
      hl = "TaskdownCalSelected"
    elseif date_str == today_str then
      hl = "TaskdownCalToday"
    end
    if hl then
      -- Highlight just the two-digit day number (col to col+2)
      vim.api.nvim_buf_add_highlight(buf, ns, hl, pos.line - 1, pos.col, pos.col + 2)
    end
  end

  -- Move cursor to selected day if it's in the viewed month
  if state.selected.year == year and state.selected.month == month then
    local pos = day_pos[state.selected.day]
    if pos and state.win and vim.api.nvim_win_is_valid(state.win) then
      vim.api.nvim_win_set_cursor(state.win, { pos.line, pos.col })
    end
  end
end

local function close(result)
  if state.win and vim.api.nvim_win_is_valid(state.win) then
    vim.api.nvim_win_close(state.win, true)
  end
  state.win = nil
  state.buf = nil
  state.day_pos = {}
  local cb = state.callback
  state.callback = nil
  if cb then cb(result) end
end

local function move_days(n)
  local s = state.selected
  local ts = os.time({ year = s.year, month = s.month, day = s.day, hour = 12 }) + n * 86400
  local nt = os.date("*t", ts)
  state.selected = { year = nt.year, month = nt.month, day = nt.day }
  state.view     = { year = nt.year, month = nt.month }
  render()
end

local function move_months(n)
  local v = state.view
  v.month = v.month + n
  if v.month > 12 then v.month = v.month - 12; v.year = v.year + 1 end
  if v.month < 1  then v.month = v.month + 12; v.year = v.year - 1 end
  -- Clamp selected day to valid range in the new month
  local max = days_in_month(v.year, v.month)
  state.selected = { year = v.year, month = v.month, day = math.min(state.selected.day, max) }
  render()
end

-- Open the calendar picker.
-- opts.callback(date_str) is called with "YYYY-MM-DD" on confirm, nil on cancel.
-- opts.default is an optional "YYYY-MM-DD" starting date.
function M.open(opts)
  opts = opts or {}

  setup_highlights()

  -- Resolve starting date
  local today = os.date("*t")
  local sel = { year = today.year, month = today.month, day = today.day }
  if opts.default then
    local y, m, d = opts.default:match("(%d%d%d%d)-(%d%d)-(%d%d)")
    if y then sel = { year = tonumber(y), month = tonumber(m), day = tonumber(d) } end
  end

  state.selected = sel
  state.view     = { year = sel.year, month = sel.month }
  state.callback = opts.callback

  -- Buffer
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_set_option_value("buftype",   "nofile", { buf = buf })
  vim.api.nvim_set_option_value("bufhidden", "wipe",   { buf = buf })

  -- Window: width=20 to fit "Su Mo Tu We Th Fr Sa", height placeholder (render resizes)
  local width  = 20
  local height = 8  -- max; render() will shrink to fit
  local row    = math.floor((vim.o.lines   - height) / 2)
  local col    = math.floor((vim.o.columns - width)  / 2)

  local win_config = {
    relative  = "editor",
    row       = row,
    col       = col,
    width     = width,
    height    = height,
    style     = "minimal",
    border    = "rounded",
    title     = " due date ",
    title_pos = "center",
  }

  -- footer requires nvim 0.10+
  if vim.fn.has("nvim-0.10") == 1 then
    win_config.footer     = " [H/L] month  [q] skip "
    win_config.footer_pos = "center"
  end

  local win = vim.api.nvim_open_win(buf, true, win_config)
  vim.api.nvim_set_option_value("cursorline", false, { win = win })
  vim.api.nvim_set_option_value("wrap",       false, { win = win })

  state.buf = buf
  state.win = win

  render()

  -- Keymaps
  local function map(lhs, fn)
    vim.keymap.set("n", lhs, fn, { buffer = buf, noremap = true, silent = true })
  end

  map("h",      function() move_days(-1)   end)
  map("l",      function() move_days(1)    end)
  map("k",      function() move_days(-7)   end)
  map("j",      function() move_days(7)    end)
  map("H",      function() move_months(-1) end)
  map("L",      function() move_months(1)  end)
  map("<CR>",   function() close(format_date(state.selected)) end)
  map("q",      function() close(nil) end)
  map("<Esc>",  function() close(nil) end)
end

return M
