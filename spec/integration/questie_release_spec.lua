-- Integration: loads the installed, unmodified QuestieDB release per character.
-- Needs an install (hwc init); pending without one. About 1 s for two loads.
local home = require("hwc.questie.home")
local source = require("hwc.questie.source")
-- luasystem ships with busted; it gives wall time, which os.clock does not
local system = require("system")

local dir = home.active_dir(home.root())

describe("QuestieDB release, loaded per character", function()
  if not dir then
    pending("no QuestieDB installed: run hwc init")
    return
  end

  local function timed_open(character)
    local t0 = system.gettime()
    local s, why = source.open(dir, character)
    io.stderr:write(("[questie] open %s %s: %.2f s\n"):format(character.class, character.faction, system.gettime() - t0))
    assert(s, why)
    return s
  end

  local warrior, mage
  setup(function()
    warrior = timed_open({ class = "WARRIOR", faction = "Alliance" })
    mage = timed_open({ class = "MAGE", faction = "Alliance" })
  end)

  it("serves quests and their xp", function()
    assert.are.equal("Dwarven Outfitters", warrior:quest(179).name)
    assert.is_not_nil(warrior:xp(179))
  end)

  it("serves npcs, items, objects and the sorted item ids", function()
    assert.are.equal(658, warrior:quest(179).startedBy[1][1])
    assert.are.equal("Sten Stoutarm", warrior:npc(658).name)
    assert.are.equal("Tough Wolf Meat", warrior:item(750).name)
    assert.are.equal("Silverleaf", warrior:object(1617).name)
    local ids = warrior:item_ids()
    assert.is_true(#ids > 0)
    for i = 2, #ids do assert(ids[i - 1] < ids[i], "item ids not ascending at " .. i) end
  end)

  it("names the installed release", function()
    local rel = home.read_release(home.root(), home.active(home.root()))
    assert.are.same({ path = dir, tag = rel.tag, build = rel.build, sha256 = rel.sha256 }, warrior.info)
  end)

  -- Review Focus 1: dynamic corrections run as the character, and two
  -- characters in one process never share them. QuestieDB
  -- src/corrections/Forever/legacy/classicQuestFixes.lua:393-404 (the
  -- Alliance table) picks The Calling's next quest by UnitClassBase("player").
  it("applies class-specific corrections per character", function()
    assert.are.equal(8316, warrior:quest(8315).nextQuestInChain)
    assert.are.equal(8381, mage:quest(8315).nextQuestInChain)
  end)

  it("leaves no errors in either sandbox", function()
    assert.are.same({}, warrior.sandbox.errors)
    assert.are.same({}, mage.sandbox.errors)
  end)
end)
