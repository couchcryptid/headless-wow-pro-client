---@type QuestieDB
local QuestieDB = QuestieLoader:ImportModule("QuestieDB");

QuestieDB.objectKeys = {
    ['name'] = 1,
    ['spawns'] = 2,
}

QuestieDB.objectData = [[return {
[3001] = {"Fixture Chest",{[12]={{50,50}}}},
}]]
