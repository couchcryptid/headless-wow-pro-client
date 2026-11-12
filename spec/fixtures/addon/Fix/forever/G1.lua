-- fixture
local guide = WoWPro:RegisterGuide('FixG1', 'Leveling', 'Fix', 'Tester', 'Alliance', 1)
WoWPro:GuideSteps(guide, function()
return [[
A Foo|QID|5|
; a comment
C Foo|QID|5|
C Foo|QID|5|
T Bar|QID|7^8|
K Baz|ACTIVE|9|QO|1|
F Ironforge|AVAILABLE|3681|C|Paladin|
F Ironforge|ACTIVE|301|
F Stormwind|ACTIVE|301|R|NightElf|C|-Druid|
F Stormwind|ACTIVE|301|
C Qux|QID|11|FACTION|Horde|
C Qux|QID|11|
N Note|
N Note|QID|12|
K Vagash|ACTIVE|314|L|3627|
F Stormwind|ACTIVE|301|R|Dwarf,Gnome|C|Warrior, Mage|
]]
end)
