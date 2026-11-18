-- hwc list [races | classes RACE | professions] (design §4.5). The one-per-line
-- forms are for shell loops; a bare `hwc list` prints a table for reading.
local Player = require("hwc.world.player")
local professions = require("hwc.world.professions")

local COOKING = "Cooking is learned from Camping 101: Cooking"

local function races()
  local out = {}
  for name in pairs(Player.RACES) do out[#out + 1] = name end
  table.sort(out)
  return out
end

-- RACE matched as --race is: case-insensitive, canonical spelling; or nil, message.
local function race_named(word)
  local all = races()
  for _, r in ipairs(all) do
    if r:lower() == word:lower() then return r end
  end
  return nil, word .. " is not a race; races: " .. table.concat(all, ", ")
end

-- CLI spellings (first-aid) of the primaries, sorted, and of the secondaries.
-- Cooking is in neither: no character starts with it.
local function profession_names()
  local primary, secondary = {}, {}
  for i, name in ipairs(professions.PRIMARY) do primary[i] = professions.token({ name }) end
  for i, name in ipairs(professions.SECONDARY) do secondary[i] = professions.token({ name }) end
  return primary, secondary
end

local function one_per_line(list) return table.concat(list, "\n") .. "\n" end

local function table_text()
  local out, width = { "Races:" }, 0
  local all = races()
  for _, r in ipairs(all) do width = math.max(width, #r) end
  for _, r in ipairs(all) do
    local info = Player.RACES[r]
    out[#out + 1] = string.format("  %-" .. width .. "s  %-8s  %s", r, info.faction,
      table.concat(Player.classes_for(r), ", "))
  end
  local primary, secondary = profession_names()
  out[#out + 1] = ""
  out[#out + 1] = "Professions (at most two primary):"
  out[#out + 1] = "  primary    " .. table.concat(primary, ", ")
  out[#out + 1] = "  secondary  " .. table.concat(secondary, ", ")
  out[#out + 1] = COOKING
  return table.concat(out, "\n") .. "\n"
end

return {
  name = "list",
  summary = "List the races, a race's classes, or the professions",
  usage = "[races | classes RACE | professions]",
  description = "List what hwc run accepts. With no argument, a table of races, their factions\n"
    .. "and classes, and the professions. The other forms print one name per line.",
  positionals = { min = 0, max = 2, noun = "arguments" },
  notes = { "Example: for c in $(hwc list classes Dwarf); do hwc run --race Dwarf --class \"$c\"; done" },
  check = function(opts)
    local form, arg = opts.positionals[1], opts.positionals[2]
    if form == "classes" then
      if not arg then return "hwc list classes needs a race" end
      local race, err = race_named(arg)
      if not race then return err end
      opts.race = race
    elseif form ~= nil and form ~= "races" and form ~= "professions" then
      return "hwc list has no " .. form .. "; use races, classes RACE or professions"
    elseif arg then
      return "hwc list " .. form .. " takes no argument"
    end
  end,
  run = function(ctx)
    local form = ctx.opts.positionals[1]
    local text
    if form == "races" then
      text = one_per_line(races())
    elseif form == "classes" then
      text = one_per_line(Player.classes_for(ctx.opts.race))
    elseif form == "professions" then
      local primary, secondary = profession_names()
      for _, name in ipairs(secondary) do primary[#primary + 1] = name end
      text = one_per_line(primary)
    else
      text = table_text()
    end
    ctx.ui:result(text)
    return 0
  end,
}
