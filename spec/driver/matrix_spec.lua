-- Character matrix (design spec §3, §11): which race x class x profession variants
-- `hwc matrix` plays. Classes come from Player.RACES (Blizzard's Forever table), never
-- from guide tags: the guide is what's under test. The Camping 101 case reads the
-- real guides and pends without the addon checkout.
local lfs = require("lfs")
local matrix = require("hwc.driver.matrix")
local Player = require("hwc.world.player")

local ADDON = os.getenv("HOME") .. "/Projects/WoW-Pro-Guides"
local present = lfs.attributes(ADDON .. "/WoWPro/WoWPro.toc", "mode") ~= nil

describe("matrix.classes_for", function()
  it("is the race's Forever class list from Player.RACES", function()
    assert.same(Player.RACES.Gnome.classes, matrix.classes_for("Gnome"))
    assert.same(Player.RACES.Undead.classes, matrix.classes_for("Undead"))
  end)

  -- Upstream 9310ff2ab (2026-11-17) dropped the guide's only C|Priest|R|Dwarf,Gnome lines;
  -- the matrix must not lose a combo the game has when a guide changes.
  it("keeps Gnome Priest whatever the guides say", function()
    local found = false
    for _, c in ipairs(matrix.classes_for("Gnome")) do if c == "PRIEST" then found = true end end
    assert.is_true(found)
  end)

  it("returns a copy the caller may change", function()
    local a = matrix.classes_for("Dwarf")
    a[1] = "NOPE"
    assert.equal("HUNTER", matrix.classes_for("Dwarf")[1])
  end)

  it("errors for a race not in scope", function()
    assert.has_error(function() matrix.classes_for("Goblin") end, "hwc: race not in scope: Goblin")
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
    local combos = matrix.combos({ "Tauren", "Gnome" })
    local nt, ng = #Player.RACES.Tauren.classes, #Player.RACES.Gnome.classes
    assert.equal(nt + 6 + ng + 6, #combos)
    assert.same({ race = "Tauren", class = "DRUID", variant = "baseline" }, combos[1])
    assert.same({ race = "Tauren", class = "HUNTER", variant = "baseline" }, combos[2])
    assert.same({ race = "Tauren", class = "DRUID", variant = "secondary" }, combos[nt + 1])
    assert.same({ race = "Gnome", class = "MAGE", variant = "tailoring" }, combos[#combos])
  end)
end)
