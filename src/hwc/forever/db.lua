-- Reads the installed Forever client tables (hwc.forever.install) and derives
-- what the arrival emulation needs: taxi nodes placed on their landing map,
-- the continent of a map, and the set of area names (design spec section 1).
local dkjson = require("dkjson")
local home = require("hwc.forever.home")
local convert = require("hwc.forever.convert")

local DB = {}
DB.__index = DB

local M = {}

local function read_json(path)
  local f = io.open(path, "rb")
  if not f then return nil, "hwc: forever: " .. path .. " is missing" end
  local text = f:read("*a")
  f:close()
  local value = dkjson.decode(text)
  if type(value) ~= "table" then return nil, "hwc: forever: " .. path .. " is not valid JSON" end
  return value
end

-- rows -> list of { [column] = value } records.
local function records(tbl)
  local out = {}
  for i, row in ipairs(tbl.rows) do
    local rec = {}
    for c, name in ipairs(tbl.columns) do rec[name] = row[c] end
    out[i] = rec
  end
  return out
end

-- db.open(dir) -> DB | nil, reason. `dir` is an installed build dir (may be nil).
function M.open(dir)
  if not dir then return nil, "none installed" end
  local release = read_json(dir .. "/" .. home.RELEASE_FILE)
  if not release then return nil, "none installed" end
  local self = setmetatable({ build = release.build, dir = dir }, DB)
  local t = {}
  for _, spec in ipairs(convert.TABLES) do
    local tbl, err = read_json(dir .. "/" .. spec.name .. ".json")
    if not tbl or type(tbl.rows) ~= "table" or type(tbl.columns) ~= "table" then
      return nil, err or ("hwc: forever: " .. spec.name .. ".json is not table JSON")
    end
    t[spec.name] = records(tbl)
  end
  self:_index(t)
  return self
end

function DB:_index(t)
  self._maps, self._area_name, self._first_assign, self._area_map = {}, {}, {}, {}
  self._names = {}
  for _, m in ipairs(t.UiMap) do
    self._maps[m.ID] = m
    self._names[m.Name_lang] = true
  end
  for _, a in ipairs(t.AreaTable) do
    self._area_name[a.ID] = a.AreaName_lang
    self._names[a.AreaName_lang] = true
  end
  for _, w in ipairs(t.WMOAreaTable) do self._names[w.AreaName_lang] = true end
  -- First file-order row wins for a UiMapID and for an AreaID.
  self._assignments = t.UiMapAssignment
  for _, a in ipairs(t.UiMapAssignment) do
    if self._first_assign[a.UiMapID] == nil then self._first_assign[a.UiMapID] = a end
    if a.AreaID ~= 0 and self._area_map[a.AreaID] == nil then self._area_map[a.AreaID] = a.UiMapID end
  end
  self._taxi = t.TaxiNodes
end

function DB:continent_of(ui_map_id)
  local seen = {}
  local id = ui_map_id
  while id and id ~= 0 and not seen[id] do
    seen[id] = true
    local m = self._maps[id]
    if not m then return nil end
    if m.Type == 2 then return m.ID end
    id = m.ParentUiMapID
  end
  return nil
end

function DB:zone_of_map(ui_map_id)
  local a = self._first_assign[ui_map_id]
  local name = a and self._area_name[a.AreaID]
  if name then return name end
  local m = self._maps[ui_map_id]
  return m and m.Name_lang or nil
end

function DB:ui_map_of_area(area_id)
  return self._area_map[area_id]
end

function DB:is_area_name(s)
  return self._names[s] == true
end

-- The assignment on the node's world map whose region holds it; the smallest
-- region wins so a zone beats its continent. World and cosmic maps (Type below
-- 2) are skipped: their regions overlap continents but are never a landing map.
local function placing_assignment(self, rec)
  local best, best_area
  for _, a in ipairs(self._assignments) do
    local map = self._maps[a.UiMapID]
    if map and map.Type >= 2 and a.MapID == rec.ContinentID then
      local lo0, hi0 = math.min(a.Region_0, a.Region_3), math.max(a.Region_0, a.Region_3)
      local lo1, hi1 = math.min(a.Region_1, a.Region_4), math.max(a.Region_1, a.Region_4)
      if rec.Pos_0 >= lo0 and rec.Pos_0 <= hi0 and rec.Pos_1 >= lo1 and rec.Pos_1 <= hi1 then
        local area = (hi0 - lo0) * (hi1 - lo1)
        if not best or area < best_area then best, best_area = a, area end
      end
    end
  end
  return best
end

function DB:_nodes()
  if self._node_list then return self._node_list end
  local list = {}
  for _, rec in ipairs(self._taxi) do
    local a = placing_assignment(self, rec)
    if a then
      list[#list + 1] = {
        id = rec.ID,
        name = rec.Name_lang,
        continent = self:continent_of(a.UiMapID),
        faction_bits = rec.Flags % 4,
        map_id = a.UiMapID,
        x = (a.Region_4 - rec.Pos_1) / (a.Region_4 - a.Region_1),
        y = (a.Region_3 - rec.Pos_0) / (a.Region_3 - a.Region_0),
        zone = self:zone_of_map(a.UiMapID),
      }
    end
  end
  table.sort(list, function(l, r) return l.id < r.id end)
  self._node_list = list
  return list
end

local FACTION_BIT = { Alliance = 1, Horde = 2 }

-- Nodes on a continent (UiMap id) usable by `faction`, in ID order.
function DB:taxi_nodes(continent_id, faction)
  local bit = FACTION_BIT[faction]
  if not bit then error("hwc: forever: unknown faction " .. tostring(faction), 0) end
  local out = {}
  for _, n in ipairs(self:_nodes()) do
    if n.continent == continent_id and (n.faction_bits == bit or n.faction_bits == 3) then
      out[#out + 1] = n
    end
  end
  return out
end

function DB:node(name)
  for _, n in ipairs(self:_nodes()) do
    if n.name == name then return n end
  end
  return nil
end

return M
