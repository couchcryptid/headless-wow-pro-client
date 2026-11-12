---@type QuestieDB
local QuestieDB = QuestieLoader:ImportModule("QuestieDB");

QuestieDB.itemKeys = {
    ['name'] = 1,
    ['npcDrops'] = 2,
    ['questRewards'] = 6,
}

QuestieDB.itemData = [[return {
[5001] = {'Fixture Pelt',{2003}},
[5002] = {'Fixture Fang',{2001,2002}},
[5003] = {'Fixture Fang',nil},
[5004] = {'Fixture Keg',nil,nil,nil,nil,{179}},
}]]
