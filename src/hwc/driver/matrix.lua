-- The character matrix (design spec §3, §11): which races x classes x profession
-- variants `hwc matrix` plays. Classes come from Player.RACES, never from guide tags.
local Player = require("hwc.world.player")

local matrix = {}

-- Spec §11 variants. Together they cover every "A Camping 101: <Prof>" quest in
-- the 1-25 guides (12 professions); each primary pair stays at two skills, as in
-- the client, and the secondaries ride the `secondary` variant only.
matrix.VARIANTS = {
  { name = "baseline", professions = {} },
  { name = "secondary", professions = { "Cooking", "First Aid", "Fishing" } },
  { name = "alch-herb", professions = { "Alchemy", "Herbalism" } },
  { name = "bs-mining", professions = { "Blacksmithing", "Mining" } },
  { name = "lw-skin", professions = { "Leatherworking", "Skinning" } },
  { name = "eng-ench", professions = { "Engineering", "Enchanting" } },
  { name = "tailoring", professions = { "Tailoring" } },
}

-- Spec §12: every skill starts known at rank 1 of max 75. nil for an unknown variant.
function matrix.professions(variant)
  for _, v in ipairs(matrix.VARIANTS) do
    if v.name == variant then
      local out = {}
      for i, name in ipairs(v.professions) do out[i] = { name = name, rank = 1, max = 75 } end
      return out
    end
  end
  return nil
end

-- The race's Forever classes (Player.RACES, from Blizzard's race/class table), as a
-- copy. Never from guide tags: the guide is what's under test, and an upstream edit
-- once dropped Gnome Priest from the matrix that way (WoW-Pro 9310ff2ab).
function matrix.classes_for(race)
  local r = Player.RACES[race]
  if not r then error("hwc: race not in scope: " .. tostring(race), 0) end
  local out = {}
  for i, c in ipairs(r.classes) do out[i] = c end
  return out
end

-- Every class x baseline, plus each non-baseline variant on the race's first
-- class (Camping 101 quests are not class-gated, so one class covers them).
function matrix.combos(races)
  local out = {}
  for _, race in ipairs(races) do
    local classes = matrix.classes_for(race)
    for _, class in ipairs(classes) do
      out[#out + 1] = { race = race, class = class, variant = "baseline" }
    end
    for _, v in ipairs(matrix.VARIANTS) do
      if v.name ~= "baseline" and classes[1] then
        out[#out + 1] = { race = race, class = classes[1], variant = v.name }
      end
    end
  end
  return out
end

return matrix
