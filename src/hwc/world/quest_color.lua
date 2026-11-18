-- Quest difficulty colour by level difference (design 2026-11-18-quest-color).
-- The bands come from Classic GetQuestDifficultyColor (FrameXML QuestUtils): quest level minus
-- character level >= 5 red, 3-4 orange, yellow up to 2, the rest green. The grey line is the mob
-- grey level (xp.gray_level), a project choice and not taken from that API. Unverified for
-- Forever (Classic): none of it is checked in game.
local xp = require("hwc.world.xp")

local quest_color = {}

-- "red"|"orange"|"yellow"|"green"|"grey", or nil when either level is missing.
function quest_color.of(char_level, quest_level)
  if not (char_level and quest_level) then return nil end
  local d = quest_level - char_level
  if d >= 5 then return "red" end
  if d >= 3 then return "orange" end
  if quest_level <= xp.gray_level(char_level) then return "grey" end
  -- Yellow runs from 2 levels above down to 2 below; green below that.
  if d >= -2 then return "yellow" end
  return "green"
end

return quest_color
