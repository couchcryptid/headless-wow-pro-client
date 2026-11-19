-- The driver specs' invented quests (spec/helpers/driver_fixtures.lua), as QuestieDB rows
-- on top of questie_source.lua. Each objective's count is in the quest's objectivesText,
-- the way real QuestieDB quests carry it ("8 pieces of Tough Wolf Meat").
local QUESTS, XP = {}, {}

QUESTS[179] = { name = "Fixture Outfitters", questLevel = 1, requiredLevel = 1, objectives = { nil, nil, { { 5001, "Fixture Pelt" } } }, objectivesText = { "Get 2 Fixture Pelt." } }
XP[179] = { 1, 80 }
QUESTS[180] = { name = "Fixture Outfitters Alt", questLevel = 1, requiredLevel = 1 }
XP[180] = { 1, 80 }
QUESTS[92001] = { name = "Fixture Human Only", questLevel = 1, requiredLevel = 1, requiredRaces = 1 }
XP[92001] = { 1, 50 }
QUESTS[92002] = { name = "Fixture Level Three", questLevel = 3, requiredLevel = 3 }
XP[92002] = { 3, 50 }
QUESTS[92003] = { name = "Fixture Two Kills", questLevel = 1, requiredLevel = 1, objectives = { { { 2001, "Fixture Giver" }, { 2002, "Fixture Taker" } } }, objectivesText = { "Get 2 Fixture Giver, 6 Fixture Taker." } }
XP[92003] = { 1, 50 }
QUESTS[92004] = { name = "Fixture Big Reward", questLevel = 1, requiredLevel = 1 }
XP[92004] = { 1, 2000 }
QUESTS[92005] = { name = "Fixture Errand", questLevel = 1, requiredLevel = 1, objectives = { nil, nil, nil, nil, nil, { { 0, "Do it" } } } }
XP[92005] = { 1, 50 }
QUESTS[92006] = { name = "Fixture Mage Only", questLevel = 1, requiredLevel = 1, requiredClasses = 128 }
XP[92006] = { 1, 50 }
QUESTS[92007] = { name = "Fixture Needs Prior", questLevel = 1, requiredLevel = 1, preQuestSingle = { 92004 } }
XP[92007] = { 1, 50 }
QUESTS[92008] = { name = "Fixture Pack Run", questLevel = 1, requiredLevel = 1, objectives = { nil, nil, { { 5002, "Fixture Fang" } } }, objectivesText = { "Get 8 Fixture Fang." } }
XP[92008] = { 1, 50 }
QUESTS[92009] = { name = "Fixture Human Level Three", questLevel = 3, requiredLevel = 3, requiredRaces = 1 }
XP[92009] = { 3, 50 }
QUESTS[92010] = { name = "Fixture Ribs And Malt", questLevel = 1, requiredLevel = 1, objectives = { nil, nil, { { 5010, "Fixture Rib" }, { 5011, "Fixture Malt" } } }, objectivesText = { "Get 6 Fixture Rib, 1 Fixture Malt." } }
XP[92010] = { 1, 50 }
QUESTS[92011] = { name = "Fixture Find The Body", questLevel = 1, requiredLevel = 1, objectives = { { { 2003, "Fixture Body" } } }, objectivesText = { "Get 1 Fixture Body." } }
XP[92011] = { 1, 50 }
QUESTS[98319] = { name = "Secure the Mountain", questLevel = 1, requiredLevel = 1, objectives = { { { 278166, "Mountaineer Cornelius' body located" } } }, objectivesText = { "Get 1 Mountaineer Cornelius' body located." } }
XP[98319] = { 1, 50 }

return { quests = QUESTS, xp = XP }
