---@type QuestieDB
local QuestieDB = QuestieLoader:ImportModule("QuestieDB");

QuestieDB.npcKeys = {
    ['name'] = 1,
    ['minLevel'] = 2,
    ['maxLevel'] = 3,
    ['rank'] = 4,
    ['spawns'] = 5,
    ['zoneID'] = 6,
}

QuestieDB.npcData = [[return {
[2001] = {'Fixture Giver',5,5,0,{[12]={{10.5,20.5},{11,21}}},12},
[2002] = {'Fixture Taker',6,6,0,nil,12},
[2003] = {'Fixture Boss',11,11,1,{[1]={{62.6,46.1}}},1},
}]]
