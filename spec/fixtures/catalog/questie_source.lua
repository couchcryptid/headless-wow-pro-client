-- A fixture QuestieDB Source (the interface of src/hwc/questie/source.lua),
-- built from plain tables. Invented rows, not real data; records use
-- QuestieDB's own field names. Fields a row leaves out are nil, as in a
-- real Source.
local QUESTS = {
  [1001] = { name = "Fixture Wolves", startedBy = { { 2001 } }, finishedBy = { { 2002 } }, requiredLevel = 3,
    questLevel = 18, requiredRaces = 77, objectives = { nil, nil, { { 5001, "Fixture Pelt" } } },
    preQuestSingle = { 1000 } },
  [1002] = { name = "Camping 101: First Aid", startedBy = { { 2001 } }, finishedBy = { { 2001 } }, requiredLevel = 1,
    questLevel = 1 },
  [1003] = { name = "Fixture Mask", startedBy = { { 2001 } }, finishedBy = { { 2002 } }, requiredLevel = 5,
    questLevel = 5, requiredRaces = 4294967373, preQuestGroup = { 1001, 1002 } },
  [1004] = { name = "Fixture Horde Only", startedBy = { { 2001 } }, finishedBy = { { 2002 } }, requiredLevel = 1,
    questLevel = 4, requiredRaces = 8589934770, requiredClasses = 64,
    objectives = { { { 2003, "Fixture Boss" } }, { { 3001 } } } },
  [1005] = { name = "Fixture Level From XP" },
  [1007] = { name = "Fixture Disagree", startedBy = { { 2001 } }, finishedBy = { { 2002 } }, requiredLevel = 1,
    questLevel = 2, requiredRaces = 1 },
  [1008] = { name = "Camping 101: Fishing", startedBy = { { 2001 } }, finishedBy = { { 2002 } }, requiredLevel = 1,
    questLevel = 5 },
  [1009] = { name = "Camping 101: Cooking", startedBy = { { 2001 } }, finishedBy = { { 2002 } }, requiredLevel = 1,
    questLevel = 5 },
  [1010] = { name = "Fixture Provided Item", startedBy = { { 2001 } }, finishedBy = { { 2002 } }, requiredLevel = 1,
    questLevel = 5, sourceItemId = 5002 },
}

local NPCS = {
  [2001] = { name = "Fixture Giver", minLevel = 5, maxLevel = 5, rank = 0, spawns = { [12] = { { 10.5, 20.5 }, { 11, 21 } } },
    zoneID = 12 },
  [2002] = { name = "Fixture Taker", minLevel = 6, maxLevel = 6, rank = 0, zoneID = 12 },
  [2003] = { name = "Fixture Boss", minLevel = 11, maxLevel = 11, rank = 1, spawns = { [1] = { { 62.6, 46.1 } } }, zoneID = 1 },
}

-- 4990 is listed last on purpose: quest_rewards must sort, not keep row order.
local ITEMS = {
  [5001] = { name = "Fixture Pelt", npcDrops = { 2003 } },
  [5002] = { name = "Fixture Fang", npcDrops = { 2001, 2002 } },
  [5003] = { name = "Fixture Fang" },
  [5004] = { name = "Fixture Keg", questRewards = { 179 } },
  [4990] = { name = "Fixture Mug", questRewards = { 179 } },
}

local OBJECTS = {
  [3001] = { name = "Fixture Chest", spawns = { [12] = { { 50, 50 } } } },
}

-- Drop tables (Source:drops shape, rate 0-1); 5002 has none, so npcDrops serves it.
local DROPS = {
  [5001] = { { npc = 2001, rate = 0.5 }, { npc = 2003, rate = 0.25 } },
}

-- QuestXP rows {level, xp}; 1006 is in no other table.
local XP = {
  [1001] = { 18, 700 },
  [1005] = { 9, 250 },
  [1006] = { 13, 450 },
}

local function record(pool, id)
  local row = pool[id]
  if not row then return nil end
  local out = { id = id }
  for k, v in pairs(row) do out[k] = v end
  return out
end

local Source = {
  info = { path = "spec/fixtures/catalog/questie_source.lua", tag = "v0.0.0", build = "fixture" },
}

function Source:quest(id) return record(QUESTS, id) end
function Source:npc(id) return record(NPCS, id) end
function Source:item(id) return record(ITEMS, id) end
function Source:object(id) return record(OBJECTS, id) end

function Source:xp(id)
  local e = XP[id]
  return e and { e[1], e[2] } or nil
end

function Source:drops(id)
  local d = DROPS[id]
  if not d then return nil end
  local out = {}
  for i, r in ipairs(d) do out[i] = { npc = r.npc, rate = r.rate } end
  return out
end

function Source:item_ids()
  local ids = {}
  for id in pairs(ITEMS) do ids[#ids + 1] = id end
  table.sort(ids)
  return ids
end

return Source
