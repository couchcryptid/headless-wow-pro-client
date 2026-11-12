-- The character matrix (design spec §3, §11): which races x classes x profession
-- variants `hwc matrix` plays. Classes come from the guides' own C| tags, read as
-- source text (the addon is never executed here), never from memory.
local lfs = require("lfs")

local matrix = {}

-- Spec §11 variants. Together they cover every "A Camping 101: <Prof>" quest in
-- the 1-25 guides (12 professions); each primary pair stays at two skills, as in
-- the client, and the secondaries ride the `secondary` variant only.
matrix.VARIANTS = {
  { name = "baseline", professions = {} },
  { name = "secondary", professions = { "Cooking", "First Aid", "Fishing" } },
  { name = "alch-herb", professions = { "Alchemy", "Herbalism" } },
  { name = "bs-mining", professions = { "Blacksmithing", "Mining" } },
  { name = "lw-skin", professions = { "Leatherworking", "Skinning" } },
  { name = "eng-ench", professions = { "Engineering", "Enchanting" } },
  { name = "tailoring", professions = { "Tailoring" } },
}

-- Spec §12: every skill starts known at rank 1 of max 75. nil for an unknown variant.
function matrix.professions(variant)
  for _, v in ipairs(matrix.VARIANTS) do
    if v.name == variant then
      local out = {}
      for i, name in ipairs(v.professions) do out[i] = { name = name, rank = 1, max = 75 } end
      return out
    end
  end
  return nil
end

local function read(path)
  local f = io.open(path, "r")
  if not f then return nil end
  local s = f:read("*a")
  f:close()
  return s
end

-- race -> start-guide name from the ForeverStartGuides table in
-- WoWPro_Leveling/WoWPro_Leveling.lua (source text, no execution).
local function start_guide_name(addon_path, race)
  local src = read(addon_path .. "/WoWPro_Leveling/WoWPro_Leveling.lua")
  if not src then error("hwc: cannot read WoWPro_Leveling.lua under " .. addon_path, 0) end
  local body = src:match("ForeverStartGuides%s*=%s*(%b{})")
  if not body then error("hwc: ForeverStartGuides not found in WoWPro_Leveling.lua", 0) end
  for key, value in body:gmatch("([%w_]+)%s*=%s*['\"]([^'\"]+)['\"]") do
    if key == race then return value end
  end
  error("hwc: no Forever start guide for race " .. tostring(race), 0)
end

-- Finds the guide file whose WoWPro:GuideName(guide, '<name>') is the start-guide
-- name, or whose WoWPro:RegisterGuide first argument (the GID) is it (some entries
-- of the table are GIDs). The files live under WoWPro_Leveling/Forever/<faction>/.
local function find_guide_file(addon_path, name)
  local root = addon_path .. "/WoWPro_Leveling/Forever"
  local dirs = {}
  for d in lfs.dir(root) do
    if d:sub(1, 1) ~= "." and lfs.attributes(root .. "/" .. d, "mode") == "directory" then dirs[#dirs + 1] = d end
  end
  table.sort(dirs)
  for _, d in ipairs(dirs) do
    local files = {}
    for f in lfs.dir(root .. "/" .. d) do
      if f:match("%.lua$") then files[#files + 1] = f end
    end
    table.sort(files)
    for _, f in ipairs(files) do
      local path = root .. "/" .. d .. "/" .. f
      local n = 0
      for line in io.lines(path) do
        n = n + 1
        local gid = line:match("RegisterGuide%(%s*['\"]([^'\"]+)['\"]")
        local gname = line:match("GuideName%(%s*guide%s*,%s*['\"]([^'\"]+)['\"]")
        if gid == name or gname == name then return path end
        if n >= 12 then break end
      end
    end
  end
  error("hwc: no guide file for start guide '" .. name .. "'", 0)
end

local function split_list(s)
  local out = {}
  for item in s:gmatch("[^,]+") do out[#out + 1] = (item:gsub("^%s+", ""):gsub("%s+$", "")) end
  return out
end

local function includes(list, v)
  for _, x in ipairs(list) do
    if x == v then return true end
  end
  return false
end

-- Does a line's R| value (a comma list, "-" negating) include the race? Compared
-- on names with the spaces removed (Night Elf / NightElf).
local function race_matches(rvalue, race)
  local want = race:gsub("%s", ""):lower()
  local positive, negative = {}, {}
  for _, r in ipairs(split_list(rvalue)) do
    r = r:gsub("%s", ""):lower()
    if r:sub(1, 1) == "-" then negative[#negative + 1] = r:sub(2) else positive[#positive + 1] = r end
  end
  if includes(negative, want) then return false end
  if #positive == 0 then return true end
  return includes(positive, want)
end

-- Classes the race's start guide names in C| tags, on lines whose R| tag names the
-- race. Ruling W (user, 2026-11-12): a class-only line (no R|) adds nothing, since
-- it would admit race/class pairs the game does not have (Gnome Shaman, Dwarf
-- Warlock, Gnome Hunter). Negated classes (C|-Druid) name no class.
-- Sorted upper-case tokens ("Priest" -> PRIEST).
function matrix.classes_for(addon_path, race)
  local path = find_guide_file(addon_path, start_guide_name(addon_path, race))
  local seen = {}
  for line in io.lines(path) do
    local fields = {}
    for field in line:gmatch("[^|]+") do fields[#fields + 1] = field end
    local classes, rvalue
    -- field 1 is "<action> <name>"; the tags follow as key, value pairs
    for i = 2, #fields - 1 do
      if fields[i] == "C" and not classes then classes = fields[i + 1] end
      if fields[i] == "R" and not rvalue then rvalue = fields[i + 1] end
    end
    if classes and rvalue and race_matches(rvalue, race) then
      for _, c in ipairs(split_list(classes)) do
        if c:sub(1, 1) ~= "-" then seen[(c:gsub("%s", ""):upper())] = true end
      end
    end
  end
  local out = {}
  for c in pairs(seen) do out[#out + 1] = c end
  table.sort(out)
  return out
end

-- Every class x baseline, plus each non-baseline variant on the race's first
-- class (Camping 101 quests are not class-gated, so one class covers them).
function matrix.combos(addon_path, races)
  local out = {}
  for _, race in ipairs(races) do
    local classes = matrix.classes_for(addon_path, race)
    for _, class in ipairs(classes) do
      out[#out + 1] = { race = race, class = class, variant = "baseline" }
    end
    for _, v in ipairs(matrix.VARIANTS) do
      if v.name ~= "baseline" and classes[1] then
        out[#out + 1] = { race = race, class = classes[1], variant = v.name }
      end
    end
  end
  return out
end

return matrix
