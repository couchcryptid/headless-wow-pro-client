-- fixture
local guide = WoWPro:RegisterGuide('FixG1', 'Leveling', 'Fix', 'Tester', 'Alliance', 1)
WoWPro:GuideSteps(guide, function()
return [[
A Foo|QID|5|
; a comment
C Foo|QID|5|
C Foo|QID|5|
T Bar|QID|7^8|
]]
end)
