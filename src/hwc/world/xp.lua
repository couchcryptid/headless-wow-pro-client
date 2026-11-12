-- Classic XP rules (design spec §5). Pure functions; no player state.
-- Sources:
--   XP to next level, levels 1-25: https://warcraft.wiki.gg/wiki/Experience_to_level (Vanilla / Classic table);
--     levels 1-23 also match the old simulator's TNL (wow-pro-leveling/sim/sim.py:31).
--   Mob XP (base, grey level, zero difference, elite x2, party modifier):
--     https://warcraft.wiki.gg/wiki/Mob_experience (Azeroth formula, pre-4.03a, as used in Vanilla);
--     the multiplier rules for quests mirror sim.py:362 (qmult), mob XP mirrors sim.py:347-360.
local xp = {}

-- Level at which XP stops accruing. add_xp can reach it; to_next is defined only below it.
xp.CAP_LEVEL = 26

local TO_NEXT = {
  400, 900, 1400, 2100, 2800, 3600, 4500, 5400, 6500, 7600, 8800, 10100, 11400,
  12900, 14400, 16000, 17700, 19400, 21300, 23200, 25200, 27300, 29400, 31700, 34000,
}

-- XP needed to advance from `level` to level + 1. Errors outside levels 1-25.
function xp.to_next(level)
  local v = TO_NEXT[level]
  if not v then error("hwc: no XP table entry for level " .. tostring(level), 2) end
  return v
end

-- Quest XP for a quest of quest_level, granted to a character of char_level.
-- Multipliers are held as integer percentages so the floored result is exact.
local QUEST_PCT = { [6] = 80, [7] = 60, [8] = 40, [9] = 20 }
function xp.quest_xp(base, char_level, quest_level)
  local d = char_level - quest_level
  local pct = d <= 5 and 100 or (QUEST_PCT[d] or 10)
  return math.floor(base * pct / 100)
end

-- Grey level: mobs at or below it give no XP.
function xp.gray_level(char_level)
  if char_level <= 5 then return 0 end
  return char_level - math.floor(char_level / 10) - 5
end

-- Zero-difference value (ZD) for the lower-level XP falloff. Correct for levels 1-29,
-- which covers the 1-25 range this sim supports.
function xp.zero_diff(char_level)
  local c = char_level
  if c <= 7 then return 5 end
  if c <= 9 then return 6 end
  if c <= 11 then return 7 end
  if c <= 15 then return 8 end
  if c <= 19 then return 9 end
  return 11
end

-- Party modifier by group size (Classic group XP). Each member's share is modifier / size.
local PARTY_MODIFIER = { [1] = 1.0, [2] = 1.0, [3] = 1.166, [4] = 1.3, [5] = 1.4 }

-- XP for killing a mob of mob_level. elite doubles it; party_size divides it by the group modifier.
-- Not floored: the caller decides rounding.
function xp.mob_xp(char_level, mob_level, elite, party_size)
  local c, m = char_level, mob_level
  local modifier = assert(PARTY_MODIFIER[party_size], "hwc: party size must be 1-5")
  local base = c * 5 + 45
  local v
  if m >= c then
    -- Integer-percent form keeps the common cases exact (95 * 110 / 100 == 104.5).
    v = base * (100 + 5 * math.min(m - c, 4)) / 100
  elseif m <= xp.gray_level(c) then
    v = 0
  else
    local zd = xp.zero_diff(c)
    v = base * (zd - (c - m)) / zd
  end
  -- Non-elite kills are always solo (sim.py:340-359): the party share applies only to elites.
  if elite then v = v * 2 * modifier / party_size end
  return v
end

return xp
