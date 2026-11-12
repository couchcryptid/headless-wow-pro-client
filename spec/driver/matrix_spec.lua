-- Character matrix (design spec §3, §11): classes come from the start guide's own
-- C| tags, never from memory. Real-guide cases assert stable facts only and pend
-- without the addon checkout.
local lfs = require("lfs")
local matrix = require("hwc.driver.matrix")

local ADDON = os.getenv("HOME") .. "/Projects/WoW-Pro-Guides"
local present = lfs.attributes(ADDON .. "/WoWPro/WoWPro.toc", "mode") ~= nil

local function has(list, v)
  for _, x in ipairs(list) do if x == v then return true end end
  return false
end

local function write(path, text)
  local f = assert(io.open(path, "w"))
  f:write(text)
  f:close()
end

local function mkdirs(path)
  local cur = ""
  for part in path:gmatch("[^/]+") do
    cur = cur .. "/" .. part
    lfs.mkdir(cur)
  end
end

-- a throwaway addon tree: a ForeverStartGuides table plus one start guide
local function fixture(guide_lines)
  local root = os.tmpname()
  os.remove(root)
  mkdirs(root .. "/WoWPro_Leveling/Forever/Alliance")
  write(root .. "/WoWPro_Leveling/WoWPro_Leveling.lua", [[
WoWPro.Leveling.ForeverStartGuides = {
    Dwarf = 'Fix Start 1-12',
    Gnome = 'Fix Start 1-12',
}
]])
  write(root .. "/WoWPro_Leveling/Forever/Alliance/01_12_Fix.lua", [==[
local guide = WoWPro:RegisterGuide('ClassicFix0112', 'Leveling', 'Fix', 'WoWPro Team', 'Alliance', 1)
WoWPro:GuideName(guide,'Fix Start 1-12')
WoWPro:GuideLevels(guide,1,12, 2)
WoWPro:GuideSteps(guide, function()
return [[
]==] .. guide_lines .. "\n]]\nend)\n")
  return root
end

describe("matrix.classes_for", function()
  -- Ruling W (user, 2026-11-12): only C| lines whose R| names the race count. A class-only
  -- line (no R|) adds nothing: it would admit combos the game has no such race/class for.
  it("takes classes only from C| tags on lines whose R| tag names the race", function()
    local root = fixture(table.concat({
      "A One|QID|1|C|Mage|R|Gnome|",
      "A Two|QID|2|C|Priest|R|Dwarf,Gnome|",
      "A Three|QID|3|C|Warrior,Rogue|",
      "A Four|QID|4|R|Dwarf|",
      "C Five|QID|5|C|-Druid|R|Dwarf|",
      "A Six|QID|6|C|Warrior|R|Dwarf|",
    }, "\n"))
    assert.same({ "PRIEST", "WARRIOR" }, matrix.classes_for(root, "Dwarf"))
    assert.is_false(has(matrix.classes_for(root, "Dwarf"), "ROGUE"))
    assert.is_false(has(matrix.classes_for(root, "Dwarf"), "MAGE"))
    assert.same({ "MAGE", "PRIEST" }, matrix.classes_for(root, "Gnome"))
  end)

  it("returns sorted upper-case tokens", function()
    local root = fixture("A Two|QID|2|C|Priest|R|Dwarf|\nA Three|QID|3|C|Hunter|R|Dwarf|")
    assert.same({ "HUNTER", "PRIEST" }, matrix.classes_for(root, "Dwarf"))
  end)

  it("errors for a race with no start guide", function()
    local root = fixture("A One|QID|1|")
    assert.has_error(function() matrix.classes_for(root, "Human") end)
  end)

  if not present then
    pending("addon checkout absent at " .. ADDON)
    return
  end

  it("Dwarf has PRIEST and PALADIN, Gnome has PRIEST (01_12_Dun_Morogh.lua)", function()
    local dwarf = matrix.classes_for(ADDON, "Dwarf")
    assert.is_true(has(dwarf, "PRIEST"))
    assert.is_true(has(dwarf, "PALADIN"))
    assert.is_true(has(matrix.classes_for(ADDON, "Gnome"), "PRIEST"))
  end)

  it("Dwarf has no WARLOCK, Gnome no SHAMAN or HUNTER (Ruling W: invalid in game)", function()
    local dwarf, gnome = matrix.classes_for(ADDON, "Dwarf"), matrix.classes_for(ADDON, "Gnome")
    assert.is_false(has(dwarf, "WARLOCK"))
    assert.is_false(has(gnome, "SHAMAN"))
    assert.is_false(has(gnome, "HUNTER"))
  end)
end)

describe("matrix.VARIANTS", function()
  it("starts with baseline and names the spec §11 variants", function()
    local names = {}
    for i, v in ipairs(matrix.VARIANTS) do names[i] = v.name end
    assert.same({ "baseline", "secondary", "alch-herb", "bs-mining", "lw-skin", "eng-ench", "tailoring" }, names)
  end)

  it("profession config starts every skill at rank 1, max 75", function()
    assert.same({ { name = "Alchemy", rank = 1, max = 75 }, { name = "Herbalism", rank = 1, max = 75 } },
      matrix.professions("alch-herb"))
    assert.same({}, matrix.professions("baseline"))
    assert.is_nil(matrix.professions("nope"))
  end)

  if not present then
    pending("addon checkout absent at " .. ADDON)
    return
  end

  it("covers exactly the Camping 101 professions in the 1-25 Alliance guides", function()
    local found = {}
    local dir = ADDON .. "/WoWPro_Leveling/Forever/Alliance"
    for f in lfs.dir(dir) do
      local lo = f:match("^(%d+)_%d+_.*%.lua$")
      if lo and tonumber(lo) < 25 then
        for line in io.lines(dir .. "/" .. f) do
          local p = line:match("^A Camping 101: ([%a ]+)|")
          if p then found[p] = true end
        end
      end
    end
    local want, got = {}, {}
    for p in pairs(found) do want[#want + 1] = p end
    for _, v in ipairs(matrix.VARIANTS) do
      for _, p in ipairs(v.professions) do got[#got + 1] = p end
    end
    table.sort(want); table.sort(got)
    assert.same(want, got)
    assert.equal(12, #got)
  end)
end)

describe("matrix.combos", function()
  it("has #classes + 6 entries per race, extra variants on the first class", function()
    local root = fixture("A Two|QID|2|C|Priest|R|Dwarf,Gnome|\nA Three|QID|3|C|Hunter|R|Dwarf|")
    local combos = matrix.combos(root, { "Dwarf", "Gnome" })
    assert.equal(2 + 6 + 1 + 6, #combos)
    assert.same({ race = "Dwarf", class = "HUNTER", variant = "baseline" }, combos[1])
    assert.same({ race = "Dwarf", class = "PRIEST", variant = "baseline" }, combos[2])
    assert.same({ race = "Dwarf", class = "HUNTER", variant = "secondary" }, combos[3])
    assert.same({ race = "Gnome", class = "PRIEST", variant = "tailoring" }, combos[#combos])
  end)
end)
