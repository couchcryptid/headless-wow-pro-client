-- Profession lists for a character: parse the --professions flag, and label a list for
-- combo names, file stems and skills. Pure: no io, no os. Only `parse` validates; the
-- formatters take any names (Cooking included) so quest-learned skills can be labelled.
local SPELLS = require("hwc.world.profession_spells")

local professions = {}

local MAX_PRIMARY = 2

-- Names the CLI knows, lower case with `-` for a space, mapped to the canonical name.
local PRIMARY, CLI_NAMES = {}, {}
for name, info in pairs(SPELLS) do
  if info.primary then PRIMARY[#PRIMARY + 1] = name end
end
table.sort(PRIMARY)
professions.PRIMARY = PRIMARY
-- Accepted by --professions beyond the primaries. Cooking is quest-learned, so it is left out.
professions.SECONDARY = { "First Aid", "Fishing" }

local function cli(name) return (name:lower():gsub(" ", "-")) end

local is_primary = {}
for _, name in ipairs(PRIMARY) do is_primary[name] = true; CLI_NAMES[cli(name)] = name end
for _, name in ipairs(professions.SECONDARY) do CLI_NAMES[cli(name)] = name end

local function accepted_list()
  local names = {}
  for key in pairs(CLI_NAMES) do names[#names + 1] = key end
  table.sort(names)
  return table.concat(names, ", ")
end

-- "herbalism,skinning" -> { "Herbalism", "Skinning" } (sorted), or nil, err.
function professions.parse(text)
  local out, seen, primaries = {}, {}, 0
  -- Append a comma so every entry, including a trailing empty one, is matched.
  for raw in (text .. ","):gmatch("([^,]*),") do
    local key = raw:lower():gsub("^%s+", ""):gsub("%s+$", ""):gsub("%s+", "-")
    if key == "" then return nil, "empty profession in --professions" end
    if key == "cooking" then
      return nil, "cooking is learned from Camping 101: Cooking; leave it out of --professions"
    end
    local name = CLI_NAMES[key]
    if not name then
      return nil, "unknown profession " .. key .. "; professions: " .. accepted_list()
    end
    if seen[name] then return nil, key .. " is listed twice" end
    seen[name] = true
    if is_primary[name] then primaries = primaries + 1 end
    out[#out + 1] = name
  end
  if primaries > MAX_PRIMARY then
    return nil, string.format("--professions %s has %d primary professions; a character can know %d",
      text, primaries, MAX_PRIMARY)
  end
  table.sort(out)
  return out
end

local function cli_names(list)
  local out = {}
  for i, name in ipairs(list) do out[i] = cli(name) end
  return out
end

-- { "First Aid", "Herbalism" } -> "first-aid,herbalism"; "none" for no professions.
function professions.token(list)
  if #list == 0 then return "none" end
  return table.concat(cli_names(list), ",")
end

-- "First Aid, Herbalism"; nil for no professions.
function professions.label(list)
  if #list == 0 then return nil end
  return table.concat(list, ", ")
end

-- "first-aid-herbalism", for file names; nil for no professions.
function professions.stem(list)
  if #list == 0 then return nil end
  return table.concat(cli_names(list), "-")
end

-- Spec §12: every skill starts known at rank 1 of max 75.
function professions.skills(list)
  local out = {}
  for i, name in ipairs(list) do out[i] = { name = name, rank = 1, max = 75 } end
  return out
end

return professions
