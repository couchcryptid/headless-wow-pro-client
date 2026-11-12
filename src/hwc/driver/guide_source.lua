-- Maps engine guide steps back to the addon source: which file registers a
-- guide, and which line a step came from. Read-only over the addon checkout.
local lfs = require("lfs")

local M = {}

local LEVELING_DIR = "WoWPro_Leveling/Forever"

function M.read_lines(path)
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
    for _, line in ipairs(M.read_lines(path) or {}) do
      local gid = line:match("RegisterGuide%s*%(%s*'([^']+)'") or line:match('RegisterGuide%s*%(%s*"([^"]+)"')
      if gid and not out[gid] then out[gid] = path:sub(#addon_path + 2) end
    end
  end
  return out
end

local function trim(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end

-- Actions whose quest id falls back to ACTIVE when the line has no QID: the engine
-- adapter's own rule (Engine.ACTIVE_FALLBACK, Ruling Z). Kept here so a source line
-- gets the same quest id the adapter gives its engine step.
M.ACTIVE_FALLBACK = { C = true, K = true, l = true, B = true, U = true }

local function first_int(list)
  return list and tonumber(list:match("^%s*(%d+)")) or nil
end

-- Action char, step name and quest id of a guide source line, or nil for comments,
-- blanks and non-step lines. The quest id is the line's first QID (the engine splits
-- on "^&": WoWPro_Parser.lua:321, 1028); without a QID, its first ACTIVE id when the
-- engine fills QID from ACTIVE (a QO tag, WoWPro_Parser.lua:834-836) or the adapter
-- falls back to ACTIVE (M.ACTIVE_FALLBACK). Also returns the raw line for filters.
local function parse_line(line)
  line = trim(line)
  if line == "" or line:sub(1, 1) == ";" then return nil end
  local action, rest = line:match("^(%a)%s+(.*)$")
  if not action then return nil end
  local name = trim(rest:match("^([^|]*)") or "")
  local qid = first_int(rest:match("|QID|([^|]*)"))
  if not qid and (rest:find("|QO|", 1, true) or M.ACTIVE_FALLBACK[action]) then
    qid = first_int(rest:match("|ACTIVE|([^|]*)"))
  end
  return action, name, qid, line
end

-- WoWPro.SemiMatch (WoWPro_Parser.lua:1042-1066), ported: big is a "," list whose
-- entries may be negated with "-"; walked last to first, a plain entry equal to
-- little matches, a negated one equal to it refuses, and any other negated entry
-- makes the list match unless something decides first.
function M.semi_match(big, little)
  local parts = {}
  for p in (big .. ","):gmatch("([^,]*),") do parts[#parts + 1] = p end
  local lmatch = false
  for j = #parts, 1, -1 do
    local p, flip = parts[j], false
    if p:sub(1, 1) == "-" then flip, p = true, p:sub(2) end
    if not flip and p == tostring(little) then return true end
    if flip and p == tostring(little) then return false end
    if flip then lmatch = true end
  end
  return lmatch
end

-- Does the engine load this line for the character ({ race, class, faction }: race
-- and class tokens, faction name)? The parser's non-retail filter
-- (WoWPro_Parser.lua:1110-1173 reads and normalises C|, R|, FACTION|; :1209-1212
-- tests them): C| without spaces, upper-cased, SemiMatch against the class token;
-- R| without spaces, SemiMatch against the race token; FACTION| trimmed and
-- upper-cased, equal to the player's faction or NEUTRAL on either side. nil
-- character: every line.
function M.loads(line, character)
  if not character then return true end
  local class = line:match("|C|([^|]*)|?")
  if class and not M.semi_match(class:gsub(" ", ""):upper(), character.class) then return false end
  local race = line:match("|R|([^|]*)|?")
  if race and not M.semi_match((race:gsub(" ", "")), character.race) then return false end
  local faction = line:match("|FACTION|([^|]*)|?")
  if faction then
    faction = trim(faction):upper()
    local mine = tostring(character.faction or ""):upper()
    if not (mine == "NEUTRAL" or faction == "NEUTRAL" or faction == mine) then return false end
  end
  return true
end

-- Line n and its source ordinal for the `occurrence`-th (default 1) line the
-- character loads whose action char, step name and quest id (parse_line) match
-- `step` ({action, name, qids}); a line with no quest id matches only a step with
-- no qids. The source ordinal counts every line with that action, name and quest id
-- up to line n, whoever loads it: it does not depend on the character and survives
-- a guide edit that only moves lines (the findings key, Ruling AA). nil when none.
function M.line_in(lines, step, occurrence, character)
  if not lines or not step then return nil end
  local want = occurrence or 1
  local qid = step.qids and step.qids[1]
  local seen, ordinal = 0, 0
  for n, text in ipairs(lines) do
    local action, name, line_qid, line = parse_line(text)
    if action == step.action and name == (step.name or "") and line_qid == qid then
      ordinal = ordinal + 1
      if M.loads(line, character) then
        seen = seen + 1
        if seen == want then return n, ordinal end
      end
    end
  end
  return nil
end

-- line_in over a guide file read from the addon checkout.
function M.line_of(addon_path, rel_file, step, occurrence, character)
  return M.line_in(M.read_lines(addon_path .. "/" .. rel_file), step, occurrence, character)
end

-- The text of line n of a guide file, or nil.
function M.line_text(addon_path, rel_file, n)
  local lines = M.read_lines(addon_path .. "/" .. rel_file)
  return lines and lines[n] or nil
end

return M
