local M = {}

local function parse_date(s)
  local y, m, d = s:match("(%d%d%d%d)-(%d%d)-(%d%d)")
  if not y then return nil end
  return { year = tonumber(y), month = tonumber(m), day = tonumber(d) }
end

local function format_date(t)
  return string.format("%04d-%02d-%02d", t.year, t.month, t.day)
end

local function days_in_month(year, month)
  local days = { 31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31 }
  if month == 2 and (year % 4 == 0 and (year % 100 ~= 0 or year % 400 == 0)) then
    return 29
  end
  return days[month]
end

local function add_days(date_str, n)
  local t = parse_date(date_str)
  if not t then return nil end
  local ts = os.time({ year = t.year, month = t.month, day = t.day, hour = 12, min = 0, sec = 0 })
  local nt = os.date("*t", ts + n * 86400)
  return format_date(nt)
end

local function add_months(date_str, n)
  local t = parse_date(date_str)
  if not t then return nil end
  t.month = t.month + n
  while t.month > 12 do
    t.month = t.month - 12
    t.year = t.year + 1
  end
  while t.month < 1 do
    t.month = t.month + 12
    t.year = t.year - 1
  end
  local max_day = days_in_month(t.year, t.month)
  if t.day > max_day then t.day = max_day end
  return format_date(t)
end

-- Parse a recurrence string into { type, interval }
-- Supported patterns:
--   daily, weekly, monthly, yearly
--   every N days/weeks/months/years
function M.parse_recur(pattern)
  if not pattern then return nil end
  pattern = pattern:lower():gsub("^%s+", ""):gsub("%s+$", "")

  if pattern == "daily" then return { type = "days", interval = 1 } end
  if pattern == "weekly" then return { type = "days", interval = 7 } end
  if pattern == "monthly" then return { type = "months", interval = 1 } end
  if pattern == "yearly" then return { type = "years", interval = 1 } end

  local n, unit = pattern:match("every (%d+) (%a+)")
  if n then
    n = tonumber(n)
    unit = unit:gsub("s$", "")
    if unit == "day" then return { type = "days", interval = n } end
    if unit == "week" then return { type = "days", interval = n * 7 } end
    if unit == "month" then return { type = "months", interval = n } end
    if unit == "year" then return { type = "years", interval = n } end
  end

  return nil
end

-- Given a due date string and recurrence pattern, return the next due date string
function M.next_date(due_str, recur_pattern)
  local r = M.parse_recur(recur_pattern)
  if not r then return nil end
  local from = due_str or M.today()
  if r.type == "days" then
    return add_days(from, r.interval)
  elseif r.type == "months" then
    return add_months(from, r.interval)
  elseif r.type == "years" then
    return add_months(from, r.interval * 12)
  end
  return nil
end

function M.today()
  return os.date("%Y-%m-%d")
end

-- Return "YYYY-MM-DD" for today + n days
function M.today_plus(n)
  return add_days(M.today(), n)
end

return M
