-- Simulated player state (design spec §5). The stubs read this on every call.
local xp = require("hwc.world.xp")
local PROFESSION_SPELLS = require("hwc.world.profession_spells")

local Player = {}
Player.__index = Player

-- Races in scope: race key -> {
--   name     client display name (UnitRace first return),
--   token    client file token (UnitRace second return; the engine keys
--            ForeverStartGuides by it, WoWPro_Leveling.lua:49-59, so Undead is Scourge),
--   faction  UnitFactionGroup,
--   classes  sorted class tokens the race can play in Forever,
--   start    { zone, uiMapID, x, y } where a new character spawns }.
-- Classes: Blizzard, "Create the Hero You Want to Be in World of Warcraft: Forever",
-- https://worldofwarcraft.blizzard.com/news/24304075/ (race/class tables, read 2026-11-18);
-- Gnome Priest also confirmed in game by the user (2026-11-17, 2026-11-18).
-- Start: the race's starting zone and its client uiMapID. x, y approximate the
-- starting area (its first quest giver, where the start guide's first M tag puts
-- them); only the first event sees them, because the driver moves the player to
-- each step's own M coordinates before acting.
-- Skyborne is two races in the client (ChrRaces 95 SKYBORNE_ALLIANCE and 96
-- SKYBORNE_HORDE, QuestieDB src/corrections/enum/expansions.lua:27-28), picked at
-- character creation, with different classes and display names. Both answer the
-- token "Skyborne" (user, in game 2026-11-18: UnitRace gives "High Order Skyborne",
-- "Skyborne", 95 and "Windshaper Skyborne", "Skyborne", 96):
-- the engine's single ForeverStartGuides key (WoWPro_Leveling.lua:58) loads a
-- start guide for either, and RegisterGuide's faction check
-- (WoWPro_GuideRegistry.lua:266) picks the Alliance or Horde Zephras Isle file.
Player.RACES = {
  Dwarf = { name = "Dwarf", token = "Dwarf", faction = "Alliance",
    classes = { "HUNTER", "PALADIN", "PRIEST", "ROGUE", "SHAMAN", "WARRIOR" },
    start = { "Dun Morogh", 1426, 0.3, 0.7 } },
  Gnome = { name = "Gnome", token = "Gnome", faction = "Alliance",
    classes = { "MAGE", "PRIEST", "ROGUE", "WARLOCK", "WARRIOR" },
    start = { "Dun Morogh", 1426, 0.3, 0.7 } },
  Human = { name = "Human", token = "Human", faction = "Alliance",
    classes = { "HUNTER", "MAGE", "PALADIN", "PRIEST", "ROGUE", "WARLOCK", "WARRIOR" },
    start = { "Elwynn Forest", 1429, 0.48, 0.42 } },
  NightElf = { name = "Night Elf", token = "NightElf", faction = "Alliance",
    classes = { "DRUID", "HUNTER", "PRIEST", "ROGUE", "WARRIOR" },
    start = { "Teldrassil", 1438, 0.59, 0.44 } },
  Orc = { name = "Orc", token = "Orc", faction = "Horde",
    classes = { "HUNTER", "MAGE", "ROGUE", "SHAMAN", "WARLOCK", "WARRIOR" },
    start = { "Durotar", 1411, 0.43, 0.69 } },
  Tauren = { name = "Tauren", token = "Tauren", faction = "Horde",
    classes = { "DRUID", "HUNTER", "SHAMAN", "WARRIOR" },
    start = { "Mulgore", 1412, 0.44, 0.77 } },
  Troll = { name = "Troll", token = "Troll", faction = "Horde",
    classes = { "HUNTER", "MAGE", "PRIEST", "ROGUE", "SHAMAN", "WARLOCK", "WARRIOR" },
    start = { "Durotar", 1411, 0.43, 0.69 } },
  Undead = { name = "Undead", token = "Scourge", faction = "Horde",
    classes = { "MAGE", "PALADIN", "PRIEST", "ROGUE", "WARLOCK", "WARRIOR" },
    start = { "Tirisfal Glades", 1420, 0.30, 0.71 } },
  SkyborneAlliance = { name = "High Order Skyborne", token = "Skyborne", faction = "Alliance",
    classes = { "DRUID", "HUNTER", "MAGE", "ROGUE", "WARRIOR" },
    start = { "Zephras Isle", 2521, 0.43, 0.23 } },
  SkyborneHorde = { name = "Windshaper Skyborne", token = "Skyborne", faction = "Horde",
    classes = { "DRUID", "HUNTER", "ROGUE", "SHAMAN", "WARRIOR" },
    start = { "Zephras Isle", 2521, 0.43, 0.23 } },
}

-- Can the race play the class (an upper-case token) in Forever?
function Player.can_play(race, class)
  local r = Player.RACES[race]
  if not r then return false end
  for _, c in ipairs(r.classes) do
    if c == class then return true end
  end
  return false
end

local function titlecase(s) return (s:sub(1, 1):upper() .. s:sub(2):lower()) end

-- record(kind, fields) appends a world-change record; supplied by the World.
function Player.new(cfg, record)
  local race = assert(Player.RACES[cfg.race], "hwc: race not in scope: " .. tostring(cfg.race))
  local start = race.start
  return setmetatable({
    name = "Hwc", realm = "HwcRealm", race = race.name, race_token = race.token, race_key = cfg.race,
    class = titlecase(cfg.class), class_token = cfg.class:upper(),
    faction = cfg.faction or race.faction, sex = cfg.sex,
    level = 1, xp = 0, zone = start[1], subzone = "", map_id = start[2], x = start[3], y = start[4],
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
  -- A profession comes with the spell that teaches it (hwc.world.profession_spells).
  local spell = PROFESSION_SPELLS[name]
  if spell and not self.spells[spell] then self:learn_spell(spell) end
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
