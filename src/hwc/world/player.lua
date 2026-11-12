-- Simulated player state (design spec §5). The stubs read this on every call.
local xp = require("hwc.world.xp")

local Player = {}
Player.__index = Player

-- Alliance races in scope (Plan 2 carry-over): race key -> { client display name, race token }.
-- Horde races are rejected by config.load until Horde is in scope.
Player.RACES = {
  Human = { name = "Human", token = "Human" },
  Dwarf = { name = "Dwarf", token = "Dwarf" },
  Gnome = { name = "Gnome", token = "Gnome" },
  NightElf = { name = "Night Elf", token = "NightElf" },
}

local function titlecase(s) return (s:sub(1, 1):upper() .. s:sub(2):lower()) end

-- record(kind, fields) appends a world-change record; supplied by the World.
function Player.new(cfg, record)
  local race = assert(Player.RACES[cfg.race], "hwc: race not in scope: " .. tostring(cfg.race))
  return setmetatable({
    name = "Hwc", realm = "HwcRealm", race = race.name, race_token = race.token,
    class = titlecase(cfg.class), class_token = cfg.class:upper(),
    faction = cfg.faction, sex = cfg.sex,
    level = 1, xp = 0, zone = "Dun Morogh", subzone = "", map_id = 1426, x = 0.3, y = 0.7,
    bind = nil, flight_points = {}, skills = {}, spells = {}, bags = {},
    _record = record or function() end,
  }, Player)
end

-- XP needed for the current level; 0 at the cap, where to_next is undefined.
function Player:xp_max()
  if self.level >= xp.CAP_LEVEL then return 0 end
  return xp.to_next(self.level)
end

-- Adds n XP, carrying the remainder across levels. XP is discarded once the cap level is reached.
-- Returns the number of levels gained.
function Player:add_xp(n)
  local gained, total = 0, n
  while n > 0 and self.level < xp.CAP_LEVEL do
    local need = xp.to_next(self.level) - self.xp
    if n < need then
      self.xp = self.xp + n
      n = 0
    else
      n = n - need
      self.level = self.level + 1
      self.xp = 0
      gained = gained + 1
    end
  end
  if self.level >= xp.CAP_LEVEL then self.xp = 0 end
  self._record("xp", { n = total, level = self.level, xp = self.xp, levels = gained })
  return gained
end

function Player:set_zone(zone, subzone, map_id, x, y)
  self.zone, self.subzone, self.map_id, self.x, self.y = zone, subzone, map_id, x, y
  self._record("zone", { zone = zone, subzone = subzone, map_id = map_id, x = x, y = y })
end

function Player:add_item(id, n)
  self.bags[id] = (self.bags[id] or 0) + n
  self._record("add_item", { id = id, n = n })
end

-- Removes n of item id; false (and no change) when the bags hold fewer.
function Player:remove_item(id, n)
  local have = self.bags[id] or 0
  if have < n then return false end
  self.bags[id] = have - n > 0 and have - n or nil
  self._record("remove_item", { id = id, n = n })
  return true
end

-- id_or_name: numeric id, numeric string, or item name (resolved by the catalog; no catalog or unknown name -> 0).
function Player:item_count(id_or_name)
  local id = tonumber(id_or_name)
  if not id then
    local catalog = self.catalog
    id = catalog and catalog:item_id(id_or_name)
  end
  return id and self.bags[id] or 0
end

function Player:learn_skill(name, rank, max)
  self.skills[name] = { rank = rank, max = max }
  self._record("learn_skill", { name = name, rank = rank, max = max })
end

function Player:knows_skill(name) return self.skills[name] ~= nil end

function Player:learn_spell(id)
  self.spells[id] = true
  self._record("learn_spell", { id = id })
end

function Player:learn_flight_point(name)
  self.flight_points[name] = true
  self._record("learn_flight_point", { name = name })
end

function Player:set_bind(name, map_id)
  self.bind = { name = name, map_id = map_id }
  self._record("set_bind", { name = name, map_id = map_id })
end

return Player
