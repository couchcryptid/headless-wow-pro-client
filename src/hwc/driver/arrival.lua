-- Pure matching helpers for arrival emulation (design spec §3, §9). No world,
-- no engine: callers pass the landing and candidate lists in.
local M = {}

M.RADIUS = 0.05

-- The arrival-data-gap every travel step records when the Forever tables aren't
-- installed (spec section 10). Read only.
M.NO_TABLES = { reason = "tables-missing", key = "no-tables" }

-- A gap key naming the step itself: "<gid>:<line>" (the engine index when the source
-- line is unknown). gid defaults the step's own.
function M.step_key(step, gid)
  return string.format("%s:%s", tostring(step.gid or gid), tostring(step.line or step.index))
end

local function trim(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end

-- Closest item on map_id within RADIUS of (x, y); a tie keeps the earlier item.
-- pos_of(item) -> map_id, x, y.
function M.nearest(list, map_id, x, y, pos_of)
  local best, best_d
  for _, item in ipairs(list) do
    local m, ix, iy = pos_of(item)
    if m == map_id and ix and iy then
      local d = math.sqrt((ix - x) ^ 2 + (iy - y) ^ 2)
      if d <= M.RADIUS and (best_d == nil or d < best_d) then
        best, best_d = item, d
      end
    end
  end
  return best
end

-- Mirrors WoWPro.AutoCompleteZone (WoWPro_AutoComplete.lua:515-526). A nil
-- subzone is unknown and never matches.
function M.exact(landing, text)
  if text == nil then return false end
  if text == landing.zone then return true end
  if landing.subzone ~= nil and text == landing.subzone then return true end
  local n = tonumber(text)
  return n ~= nil and n == landing.map_id
end

function M.location(name)
  return trim((name:match("^([^,]*)")))
end

local function tz_part(tz)
  if not tz then return nil end
  return trim((tz:match("^([^;]*)")))
end

M.tz_part = tz_part

local TIERS = {
  function(a, b) return a == b end,
  function(a, b) return a:sub(1, #b) == b end,
  function(a, b) return a:find(b, 1, true) ~= nil end,
}

local function search(candidates, probe)
  probe = trim(probe):lower()
  if probe == "" then return nil end
  for _, tier in ipairs(TIERS) do
    local hits = {}
    for _, c in ipairs(candidates) do
      local fields = { M.location(c.name or ""), c.zone or "", c.subzone or "" }
      for _, f in ipairs(fields) do
        if f ~= "" and tier(trim(f):lower(), probe) then
          hits[#hits + 1] = c
          break
        end
      end
    end
    if #hits > 0 then return hits end
  end
  return nil
end

-- Loose pick by step name, then the first TZ part. Returns item, or nil plus
-- "none" or "ambiguous".
function M.loose(candidates, name, tz)
  local probes = { name, tz_part(tz) }
  local ambiguous = false
  for _, probe in ipairs(probes) do
    local hits = probe and search(candidates, probe)
    if hits then
      if #hits == 1 then return hits[1] end
      ambiguous = true
      break
    end
  end
  return nil, ambiguous and "ambiguous" or "none"
end

local function area_or_number(db, s)
  return db:is_area_name(s) or tonumber(s) ~= nil
end

-- True when neither the step name nor the TZ part is an area name in the build or a map
-- id: the step can never complete by zone anywhere (spec section 3), whatever the landing.
function M.names_no_area(db, name, tz)
  local part = tz_part(tz)
  if part == "" then part = nil end
  return not ((name and area_or_number(db, name)) or (part and area_or_number(db, part)))
end

-- Why a travel step that may not complete is (or is not) the guide's fault.
function M.classify(db, landing, name, tz)
  if M.names_no_area(db, name, tz) then return "name-not-an-area" end
  local part = tz_part(tz)
  if part == "" then part = nil end
  if M.exact(landing, name) or M.exact(landing, part) then return "advances" end
  if landing.subzone ~= nil then return "subzone-known" end
  return "subzone-unknown"
end

return M
