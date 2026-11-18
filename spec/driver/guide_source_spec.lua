local gs = require("hwc.driver.guide_source")

local ROOT = "spec/fixtures/addon"

describe("guide_source", function()
  it("indexes guides by the GID in RegisterGuide, relative to the addon root", function()
    local idx = gs.index(ROOT, "Fix/forever")
    assert.equal("Fix/forever/G1.lua", idx.FixG1)
  end)

  -- WoWPro_GuideRegistry.lua:266: the engine rejects a guide registered for the other
  -- faction, so the Alliance and Horde Zephras Isle files can share one GID.
  it("indexes the file registered for the character's faction or Neutral", function()
    assert.equal("Fix/factions/A.lua", gs.index(ROOT, "Fix/factions", "Alliance").FixIsle)
    assert.equal("Fix/factions/H.lua", gs.index(ROOT, "Fix/factions", "Horde").FixIsle)
    assert.equal("Fix/factions/A.lua", gs.index(ROOT, "Fix/factions", "Horde").FixBoth)
    assert.equal("Fix/factions/A.lua", gs.index(ROOT, "Fix/factions").FixIsle)
  end)

  it("accepts double-quoted GIDs and returns {} for a missing directory", function()
    assert.same({}, gs.index(ROOT, "nope"))
  end)

  it("maps the n-th identical step to its n-th source line", function()
    local file = "Fix/forever/G1.lua"
    local step = { action = "C", name = "Foo", qids = { 5 } }
    assert.equal(7, gs.line_of(ROOT, file, step, 1))
    assert.equal(8, gs.line_of(ROOT, file, step, 2))
    assert.is_nil(gs.line_of(ROOT, file, step, 3))
  end)

  it("matches on the first QID of a multi-QID step", function()
    assert.equal(9, gs.line_of(ROOT, "Fix/forever/G1.lua", { action = "T", name = "Bar", qids = { 7, 8 } }, 1))
  end)

  it("matches an ACTIVE-only step (no QID in the source line) against ACTIVE", function()
    -- the engine fills QID from ACTIVE with a QO, so the step carries qid 9; the line has no |QID|
    assert.equal(10, gs.line_of(ROOT, "Fix/forever/G1.lua", { action = "K", name = "Baz", qids = { 9 } }, 1))
    -- the adapter's ACTIVE fallback for K (no QO): qid 314
    assert.equal(19, gs.line_of(ROOT, "Fix/forever/G1.lua", { action = "K", name = "Vagash", qids = { 314 } }, 1))
    assert.is_nil(gs.line_of(ROOT, "Fix/forever/G1.lua", { action = "K", name = "Vagash", qids = { 999 } }, 1))
  end)

  -- Ruling AA: the engine drops lines whose C|/R|/FACTION| exclude the character
  -- (WoWPro_Parser.lua:1110-1173, 1209-1212, SemiMatch :1042-1066), so the n-th engine
  -- step is the n-th line the character loads.
  local FILE = "Fix/forever/G1.lua"
  local DWARF_WARRIOR = { race = "Dwarf", class = "WARRIOR", faction = "Alliance" }
  local DWARF_PALADIN = { race = "Dwarf", class = "PALADIN", faction = "Alliance" }
  local IRONFORGE = { action = "F", name = "Ironforge", qids = {} }
  local STORMWIND = { action = "F", name = "Stormwind", qids = {} }

  it("maps two same-name F lines for different classes to the right line per character", function()
    assert.same({ 12, 2 }, { gs.line_of(ROOT, FILE, IRONFORGE, 1, DWARF_WARRIOR) })
    assert.is_nil(gs.line_of(ROOT, FILE, IRONFORGE, 2, DWARF_WARRIOR))
    assert.same({ 11, 1 }, { gs.line_of(ROOT, FILE, IRONFORGE, 1, DWARF_PALADIN) })
    assert.same({ 12, 2 }, { gs.line_of(ROOT, FILE, IRONFORGE, 2, DWARF_PALADIN) })
  end)

  it("skips lines whose R| or negated C| excludes the character, with SemiMatch lists", function()
    assert.same({ 14, 2 }, { gs.line_of(ROOT, FILE, STORMWIND, 1, DWARF_WARRIOR) })
    assert.same({ 20, 3 }, { gs.line_of(ROOT, FILE, STORMWIND, 2, DWARF_WARRIOR) })
    assert.is_nil(gs.line_of(ROOT, FILE, STORMWIND, 2, DWARF_PALADIN))
    local elf_druid = { race = "NightElf", class = "DRUID", faction = "Alliance" }
    local elf_warrior = { race = "NightElf", class = "WARRIOR", faction = "Alliance" }
    assert.equal(14, gs.line_of(ROOT, FILE, STORMWIND, 1, elf_druid))
    assert.equal(13, gs.line_of(ROOT, FILE, STORMWIND, 1, elf_warrior))
  end)

  -- WoWPro_Parser.lua:1097-1099: the engine reads UnitRace's token Scourge as Undead
  -- before it tests R| tags, so an Undead character loads R|Undead lines.
  it("reads the Undead token Scourge as Undead for R| tags", function()
    local undead = { race = "Scourge", class = "PRIEST", faction = "Horde" }
    assert.is_true(gs.loads("A Rude Awakening|QID|363|R|Undead|", undead))
    assert.is_true(gs.loads("A X|QID|1|R|Undead,Troll|", undead))
    assert.is_false(gs.loads("A X|QID|1|R|-Undead|", undead))
    assert.is_false(gs.loads("A X|QID|1|R|Orc|", undead))
  end)

  it("skips a line for the other faction", function()
    assert.equal(16, gs.line_of(ROOT, FILE, { action = "C", name = "Qux", qids = { 11 } }, 1, DWARF_WARRIOR))
  end)

  it("matches a no-QID line only to a step with no qids", function()
    assert.equal(17, gs.line_of(ROOT, FILE, { action = "N", name = "Note", qids = {} }, 1))
    assert.equal(18, gs.line_of(ROOT, FILE, { action = "N", name = "Note", qids = { 12 } }, 1))
  end)

  it("returns nil for an unknown step or file", function()
    assert.is_nil(gs.line_of(ROOT, "Fix/forever/G1.lua", { action = "A", name = "Nope", qids = { 5 } }, 1))
    assert.is_nil(gs.line_of(ROOT, "Fix/forever/Missing.lua", { action = "A", name = "Foo", qids = { 5 } }, 1))
  end)

  it("toc_guides lists RegisterGuide gids in TOC order and ignores files the TOC does not load", function()
    assert.same({
      { gid = "GB", rel = "WoWPro_Leveling/b.lua" },
      { gid = "GA", rel = "WoWPro_Leveling/a.lua" },
    }, gs.toc_guides("spec/fixtures/tocguides"))
  end)

  it("indexes the real addon when present", function()
    local home = os.getenv("HOME") .. "/Projects/WoW-Pro-Guides"
    if not require("lfs").attributes(home .. "/WoWPro_Leveling", "mode") then return pending("addon absent") end
    assert.equal("WoWPro_Leveling/Forever/Alliance/01_12_Dun_Morogh.lua", gs.index(home).ClassicDunMorogh0112)
  end)
end)
