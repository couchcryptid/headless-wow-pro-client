-- Invented fixture rows in QuestieDB's layout (not real data). Field order differs from the real file on purpose.
---@type QuestieDB
local QuestieDB = QuestieLoader:ImportModule("QuestieDB");

QuestieDB.questKeys = {
    ['name'] = 1,
    ['startedBy'] = 2,
    ['finishedBy'] = 3,
    ['requiredLevel'] = 4,
    ['questLevel'] = 5,
    ['requiredRaces'] = 6,
    ['requiredClasses'] = 7,
    ['objectives'] = 8,
    ['preQuestGroup'] = 9,
    ['preQuestSingle'] = 10,
    ['sourceItemId'] = 11,
}

QuestieDB.questData = [[return {
[1001] = {"Fixture Wolves",{{2001}},{{2002}},3,18,77,nil,{nil,nil,{{5001,"Fixture Pelt"}}},nil,{1000}},
[1002] = {"Camping 101: First Aid",{{2001}},{{2001}},1,1,nil,nil,nil,nil,nil},
[1003] = {"Fixture Mask",{{2001}},{{2002}},5,5,4294967373,nil,nil,{1001,1002},nil},
[1004] = {"Fixture Horde Only",{{2001}},{{2002}},1,4,8589934770,64,{{{2003,"Fixture Boss"}},{{3001}}},nil,nil},
[1005] = {"Fixture Level From XP",nil,nil,nil,nil,nil,nil,nil,nil,nil},
[1007] = {"Fixture Disagree",{{2001}},{{2002}},1,2,1,nil,nil,nil,nil},
[1008] = {"Camping 101: Fishing",{{2001}},{{2002}},1,5,nil,nil,nil,nil,nil},
[1009] = {"Camping 101: Cooking",{{2001}},{{2002}},1,5,nil,nil,nil,nil,nil},
[1010] = {"Fixture Provided Item",{{2001}},{{2002}},1,5,nil,nil,nil,nil,nil,5002},
}]]
