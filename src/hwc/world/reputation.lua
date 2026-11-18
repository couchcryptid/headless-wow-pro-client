-- Reputation rules (design spec 2026-11-18-reputation-design.md, sections 2, 4.1, 4.6).
-- Pure functions; no player state. WoW Forever is not Classic, so each fact names its evidence.
-- Evidence key: "Forever, in game" = checked in the Forever client on 2026-11-18;
-- "unverified for Forever" = a Classic source or an inference, not yet checked there.
--   Scale: points are cumulative and Neutral starts at 0.
--     Forever, in game (2026-11-18): Gelkis Clan Centaur at 2000 reads Neutral (0-3000);
--     Ironforge and Stormwind read Honored (9000-21000).
--   reaction numbers: 1 Hated ... 4 Neutral, 5 Friendly, 6 Honored, 7 Revered, 8 Exalted.
--     Forever, in game (2026-11-18): 4 at 2000, 5 at 3100 and 4000, 6 at 9475 and 16362.
--     Reactions 1-3, 7 and 8 are unverified for Forever (Classic numbering).
--   Other bands (Hated -42000..-6000, Hostile -6000..-3000, Unfriendly -3000..0,
--     Revered 21000..42000, Exalted 42000..42999): band widths from
--     https://warcraft.wiki.gg/wiki/Reputation; unverified for Forever.
--   Starting tables: see reputation.START below; each row names its evidence.
--   Met at: observed in Forever (level-29 Human, no centaur quests, 2026-11-18): Gelkis Clan
--     Centaur (92) 2000, Magram Clan Centaur (93) 2000. That a faction becomes known on its
--     first quest reward is inferred. Any other faction is met at 0: an assumption,
--     unverified for Forever.
--   Racial bonus: none (Human Diplomacy was removed in Forever; user, 2026-11-18).
local Player = require("hwc.world.player")

local reputation = {}

reputation.MIN = -42000
reputation.MAX = 42999

-- Reaction bands, Hated to Exalted. `lower` is inclusive, `upper` exclusive (Exalted's is the cap).
-- Only Neutral, Friendly and Honored are verified for Forever; the rest are unverified for Forever.
reputation.BANDS = {
  { reaction = 1, name = "Hated",      lower = -42000, upper = -6000, verified = false },
  { reaction = 2, name = "Hostile",    lower = -6000,  upper = -3000, verified = false },
  { reaction = 3, name = "Unfriendly", lower = -3000,  upper = 0,     verified = false },
  { reaction = 4, name = "Neutral",    lower = 0,      upper = 3000,  verified = true },
  { reaction = 5, name = "Friendly",   lower = 3000,   upper = 9000,  verified = true },
  { reaction = 6, name = "Honored",    lower = 9000,   upper = 21000, verified = true },
  { reaction = 7, name = "Revered",    lower = 21000,  upper = 42000, verified = false },
  { reaction = 8, name = "Exalted",    lower = 42000,  upper = 42999, verified = false },
}

-- The reaction and band bounds for a point value; a lower bound belongs to its own band.
-- Values outside the scale fall in Hated or Exalted.
function reputation.standing(points)
  for i = #reputation.BANDS, 1, -1 do
    local b = reputation.BANDS[i]
    if points >= b.lower then return b.reaction, b.lower, b.upper end
  end
  local b = reputation.BANDS[1]
  return b.reaction, b.lower, b.upper
end

function reputation.clamp(points)
  return math.max(reputation.MIN, math.min(reputation.MAX, points))
end

-- Faction ids: Stormwind 72, Ironforge 47, Gnomeregan Exiles 54, Darnassus 69, Alliance 469
-- (header); Orgrimmar 76, Thunder Bluff 81, Darkspear Trolls 530, Undercity 68, Horde 67 (header).
-- Forever, in game 2026-11-18: 469 and 67 report isHeader true, isHeaderWithRep false.
reputation.HEADERS = { [469] = true, [67] = true }

-- Fresh level-1 tables, { points = { [factionID] = points }, inferred }.
-- `inferred` is true when the table is not an in-game capture.
local START = {
  -- Forever, in game, fresh level-1 Dwarf, 2026-11-18 (verified).
  Dwarf = { points = { [47] = 4000, [54] = 3100, [69] = 3100, [72] = 3100, [469] = 3300 }, inferred = false },
  -- Forever, in game, fresh level-1 Orc, 2026-11-18 (verified).
  Orc = { points = { [76] = 4000, [81] = 3100, [530] = 3100, [68] = 500, [67] = 3500 }, inferred = false },
  -- Forever, in game, fresh level-1 Undead, 2026-11-18 (verified).
  Undead = { points = { [68] = 4000, [76] = 2000, [530] = 2000, [81] = 500, [67] = 3500 }, inferred = false },
  -- Inferred, unverified for Forever: the Dwarf table with the race's own home at 4000
  -- and Ironforge at 3100.
  Human = { points = { [72] = 4000, [47] = 3100, [54] = 3100, [69] = 3100, [469] = 3300 }, inferred = true },
  Gnome = { points = { [54] = 4000, [47] = 3100, [69] = 3100, [72] = 3100, [469] = 3300 }, inferred = true },
  NightElf = { points = { [69] = 4000, [47] = 3100, [54] = 3100, [72] = 3100, [469] = 3300 }, inferred = true },
  -- Inferred, unverified for Forever: the Orc table with the race's own home at 4000
  -- and Orgrimmar at 3100.
  Troll = { points = { [530] = 4000, [76] = 3100, [81] = 3100, [68] = 500, [67] = 3500 }, inferred = true },
  Tauren = { points = { [81] = 4000, [76] = 3100, [530] = 3100, [68] = 500, [67] = 3500 }, inferred = true },
  -- Inferred, unverified for Forever: Skyborne has no known home faction. Alliance: the
  -- four Alliance capitals at 3100 plus the header; Horde: the Orc table's Undercity and
  -- header rows with Orgrimmar, Thunder Bluff and Darkspear at 3100.
  SkyborneAlliance = { points = { [72] = 3100, [47] = 3100, [54] = 3100, [69] = 3100, [469] = 3300 }, inferred = true },
  SkyborneHorde = { points = { [76] = 3100, [81] = 3100, [530] = 3100, [68] = 500, [67] = 3500 }, inferred = true },
}

-- A fresh character's { [factionID] = points }, as a new table, and whether it is
-- inferred. Raises for a race out of scope.
function reputation.start(race_key)
  local t = Player.RACES[race_key] and START[race_key]
  if not t then error("hwc: race not in scope: " .. tostring(race_key), 2) end
  local out = {}
  for id, v in pairs(t.points) do out[id] = v end
  return out, t.inferred
end

local MET_AT = { [92] = 2000, [93] = 2000 }

-- The points a faction starts at when first met, and whether that is an assumption (0).
function reputation.met_at(faction_id)
  local v = MET_AT[faction_id]
  if v then return v, false end
  return 0, true
end

return reputation
