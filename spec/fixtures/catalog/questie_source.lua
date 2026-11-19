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
  -- reputationReward in QuestieDB order (1382's shape: Magram -500, then Gelkis +100).
  [1382] = { name = "Fixture Centaur Reward", startedBy = { { 2001 } }, finishedBy = { { 2002 } }, requiredLevel = 1,
    questLevel = 30, reputationReward = { { 93, -500 }, { 92, 100 } } },
  [1383] = { name = "Fixture Rep Gate", startedBy = { { 2001 } }, finishedBy = { { 2002 } }, requiredLevel = 1,
    questLevel = 30, requiredMinRep = { 72, 9000 }, requiredMaxRep = { 92, 3000 } },
  [1384] = { name = "Fixture Bad Rep Gate", startedBy = { { 2001 } }, finishedBy = { { 2002 } }, requiredLevel = 1,
    questLevel = 30, requiredMinRep = { 72 }, requiredMaxRep = { "92", 3000 } },
}

-- Counts from the objective text (1011: a number, and an item named bare with none) and a
-- text count the counts file overrides (1012).
QUESTS[1011] = { name = "Fixture Text Counts", requiredLevel = 1, questLevel = 5,
  objectives = { nil, nil, { { 5001, "Fixture Pelt" }, { 5002, "Fixture Fang" } } },
  objectivesText = { "Bring 8 Fixture Pelts and Fixture Fang to the Fixture Taker." } }
-- Named NPCs with no number: 2003 is elite (one of it), 2002 has no spawns on record (a guess).
QUESTS[1013] = { name = "Fixture Named Kills", requiredLevel = 1, questLevel = 5,
  objectives = { { { 2003, "Fixture Boss" }, { 2002, "Fixture Taker" } } },
  objectivesText = { "Kill Fixture Boss, then speak with Fixture Taker." } }
QUESTS[1012] = { name = "Fixture Text Overridden", requiredLevel = 1, questLevel = 5,
  objectives = { nil, nil, { { 5001, "Fixture Pelt" } } }, objectivesText = { "Bring 3 Fixture Pelts." } }

-- Item-started quests (QuestieDB startedBy = { creatures, objects, items }): the starter item is
-- the item objective (1201), is no objective (1202), comes with a sourceItemId (1203), or the
-- quest is refused for a Dwarf (1204, Human only).
QUESTS[1201] = { name = "Fixture Note Quest", startedBy = { nil, nil, { 5020 } }, finishedBy = { { 2002 } }, requiredLevel = 1,
  questLevel = 5, objectives = { nil, nil, { { 5020, "Fixture Note" } } } }
QUESTS[1202] = { name = "Fixture Map Quest", startedBy = { nil, nil, { 5021 } }, finishedBy = { { 2002 } }, requiredLevel = 1,
  questLevel = 5 }
QUESTS[1203] = { name = "Fixture Map And Fang", startedBy = { nil, nil, { 5021 } }, finishedBy = { { 2002 } }, requiredLevel = 1,
  questLevel = 5, sourceItemId = 5002 }
QUESTS[1204] = { name = "Fixture Human Note", startedBy = { nil, nil, { 5021 } }, finishedBy = { { 2002 } }, requiredLevel = 1,
  questLevel = 5, requiredRaces = 1 }

-- A same-name chain (1101 -> 1104), a branch off 1102 with another name, a cycle,
-- two same-name quests behind one predecessor, and a same-name pair that is not adjacent.
QUESTS[1101] = { name = "Fixture Chain", nextQuestInChain = 1102 }
QUESTS[1102] = { name = "Fixture Chain", preQuestSingle = { 1101 }, nextQuestInChain = 1103 }
QUESTS[1103] = { name = "Fixture Chain", preQuestSingle = { 1102 }, nextQuestInChain = 1104 }
QUESTS[1104] = { name = "Fixture Chain", preQuestGroup = { 1103 } }
QUESTS[1105] = { name = "Fixture Branch", preQuestSingle = { 1102 } }
QUESTS[1111] = { name = "Fixture Cycle", preQuestSingle = { 1112 }, nextQuestInChain = 1112 }
QUESTS[1112] = { name = "Fixture Cycle", preQuestSingle = { 1111 }, nextQuestInChain = 1111 }
QUESTS[1121] = { name = "Fixture Fork", nextQuestInChain = 1122 }
QUESTS[1122] = { name = "Fixture Fork", preQuestSingle = { 1121 } }
QUESTS[1123] = { name = "Fixture Fork", preQuestSingle = { 1121 } }
-- next_in_chain loops with no predecessor cycle: 1141 -> 1142 -> 1143 -> 1142.
QUESTS[1141] = { name = "Fixture Loop", nextQuestInChain = 1142 }
QUESTS[1142] = { name = "Fixture Loop", preQuestSingle = { 1141 }, nextQuestInChain = 1143 }
QUESTS[1143] = { name = "Fixture Loop", preQuestSingle = { 1142 }, nextQuestInChain = 1142 }
QUESTS[1131] = { name = "Fixture Solo" }
QUESTS[1132] = { name = "Fixture Solo", preQuestSingle = { 1105 } }

local NPCS = {
  [2001] = { name = "Fixture Giver", minLevel = 5, maxLevel = 5, rank = 0, spawns = { [12] = { { 10.5, 20.5 }, { 11, 21 } } },
    zoneID = 12 },
  [2002] = { name = "Fixture Taker", minLevel = 6, maxLevel = 6, rank = 0, zoneID = 12 },
  [1572] = { name = "Thorgrum Borrelson", minLevel = 0, maxLevel = 0, rank = 0, npcFlags = 11, zoneID = 38, spawns = { [38] = { { 33.94, 50.95 } } } },
  [2003] = { name = "Fixture Boss", minLevel = 11, maxLevel = 11, rank = 1, spawns = { [1] = { { 62.6, 46.1 } } }, zoneID = 1 },
}

-- 4990 is listed last on purpose: quest_rewards must sort, not keep row order.
local ITEMS = {
  [5001] = { name = "Fixture Pelt", npcDrops = { 2003 } },
  [5002] = { name = "Fixture Fang", npcDrops = { 2001, 2002 } },
  [5003] = { name = "Fixture Fang" },
  [5004] = { name = "Fixture Keg", questRewards = { 179 } },
  [5020] = { name = "Fixture Note" },
  [5021] = { name = "Fixture Map" },
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

-- QuestieDB Enum.factionIDs shape: constant name -> faction id (invented subset).
local FACTIONS = {
  STORMWIND = 72, GELKIS_CLAN_CENTAUR = 92, MAGRAM_CLAN_CENTAUR = 93, THE_LEAGUE_OF_ARATHOR = 509,
  BRAWLGAR_ARENA_SEASON_1 = 1374,
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

function Source:factions()
  local out = {}
  for k, v in pairs(FACTIONS) do out[k] = v end
  return out
end

function Source:item_ids()
  local ids = {}
  for id in pairs(ITEMS) do ids[#ids + 1] = id end
  table.sort(ids)
  return ids
end

return Source
