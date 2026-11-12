-- Maps engine guide steps back to the addon source: which file registers a
-- guide, and which line a step came from. Read-only over the addon checkout.
local lfs = require("lfs")

local M = {}

local LEVELING_DIR = "WoWPro_Leveling/Forever"

local function read_lines(path)
  local f = io.open(path, "rb")
  if not f then return nil end
  local lines = {}
  for line in (f:read("*a") .. "\n"):gmatch("(.-)\r?\n") do lines[#lines + 1] = line end
  f:close()
  return lines
end

local function lua_files(dir, out)
  local names = {}
  for name in lfs.dir(dir) do
    if name ~= "." and name ~= ".." then names[#names + 1] = name end
  end
  table.sort(names)
  for _, name in ipairs(names) do
    local path = dir .. "/" .. name
    local mode = lfs.attributes(path, "mode")
    if mode == "directory" then lua_files(path, out)
    elseif mode == "file" and name:match("%.lua$") then out[#out + 1] = path end
  end
  return out
end

-- { [gid] = rel_file } from the RegisterGuide('<gid>' calls under `dir`
-- (default WoWPro_Leveling/Forever), rel_file relative to addon_path.
function M.index(addon_path, dir)
  local root = addon_path .. "/" .. (dir or LEVELING_DIR)
  local out = {}
  if lfs.attributes(root, "mode") ~= "directory" then return out end
  for _, path in ipairs(lua_files(root, {})) do
    for _, line in ipairs(read_lines(path) or {}) do
      local gid = line:match("RegisterGuide%s*%(%s*'([^']+)'") or line:match('RegisterGuide%s*%(%s*"([^"]+)"')
      if gid and not out[gid] then out[gid] = path:sub(#addon_path + 2) end
    end
  end
  return out
end

local function trim(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end

-- Action char, step name and first QID of a guide source line, or nil for
-- comments, blanks and non-step lines. The QID separators are ^ and & (the
-- engine splits on "^&": WoWPro_Parser.lua:321, 1028).
local function parse_line(line)
  line = trim(line)
  if line == "" or line:sub(1, 1) == ";" then return nil end
  local action, rest = line:match("^(%a)%s+(.*)$")
  if not action then return nil end
  local name = trim(rest:match("^([^|]*)") or "")
  local qids = rest:match("|QID|([^|]*)")
  local first = qids and tonumber(qids:match("^%s*(%d+)"))
  return action, name, first
end

-- The source line of the `occurrence`-th line (default 1) whose action char,
-- step name and first QID match `step` ({action, name, qids}), or nil. A line with
-- no |QID| (ACTIVE-only K/C steps: the engine fills QID from ACTIVE, so the step
-- has a qid the line does not) matches on action and name alone (Ruling Q).
function M.line_of(addon_path, rel_file, step, occurrence)
  local lines = read_lines(addon_path .. "/" .. rel_file)
  if not lines or not step then return nil end
  local want = occurrence or 1
  local seen = 0
  for n, line in ipairs(lines) do
    local action, name, first = parse_line(line)
    if action == step.action and name == (step.name or "")
      and (first == nil or first == (step.qids and step.qids[1])) then
      seen = seen + 1
      if seen == want then return n end
    end
  end
  return nil
end

-- The text of line n of a guide file, or nil.
function M.line_text(addon_path, rel_file, n)
  local lines = read_lines(addon_path .. "/" .. rel_file)
  return lines and lines[n] or nil
end

return M
