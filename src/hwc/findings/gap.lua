-- The level gap, on one scale at every check that compares the character's level with
-- what the guide or a quest expects. A gap is fractional levels from real XP
-- (level + xp / xp.to_next(level)), rounded to one decimal. Pure: no I/O.
local gap = {}

-- Below this the gap is within what the simulation's missing XP explains (no incidental
-- kills or rested XP); from MEDIUM it is a real guide problem; from HIGH it is severe.
gap.MEDIUM = 2
gap.HIGH = 4

gap.MARGIN_SENTENCE = "Gaps under 2 levels are within what the simulation's missing XP explains "
  .. "(no incidental kills or rested XP)."

-- Round to one decimal.
function gap.round(g)
  return math.floor(g * 10 + 0.5) / 10
end

-- "low" under 2 levels, "medium" from 2, "high" from 4.
function gap.severity(g)
  if g >= gap.HIGH then return "high" end
  if g >= gap.MEDIUM then return "medium" end
  return "low"
end

-- "0.9", or "less than 0.1" for a gap that rounds to 0.0.
function gap.text(g)
  local out = string.format("%.1f", g)
  if out == "0.0" then return "less than 0.1" end
  return out
end

return gap
