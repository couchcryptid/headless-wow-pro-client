local catalog = require("hwc.catalog")
local json = require("hwc.json")
local lfs = require("lfs")

local FIX = "spec/fixtures/catalog"
local PIN = "d57637f490c9dfcdbbc967dab47a8b0d8fe1b3cc"

local function fixture_cfg(over)
  local c = {
    questie_dir = FIX .. "/questie",
    wh_json = FIX .. "/wh.json",
    objs_json = FIX .. "/objs.json",
    rate_overrides = FIX .. "/rate_overrides.json",
    supplement = FIX .. "/supplement.json",
  }
  for k, v in pairs(over or {}) do c[k] = v end
  return { catalog = c }
end

local function has_note(q, needle)
  for _, n in ipairs(q.notes) do
    if n:find(needle, 1, true) then return true end
  end
  return false
end

describe("catalog (fixtures)", function()
  local cat = catalog.load(fixture_cfg())

  it("records every source with presence and provenance", function()
    assert.is_true(cat.sources.questie.present)
    assert.are.equal(64, #cat.sources.questie.sha256["foreverQuestDB.lua"])
    assert.is_true(cat.sources.wh_json.present)
    assert.is_true(cat.sources.supplement.present)
    assert.matches("^%x+$", cat.sources.wh_json.sha256)
  end)

  it("records missing sources as absent and still loads", function()
    local c = catalog.load(fixture_cfg {
      questie_dir = FIX .. "/nope", wh_json = FIX .. "/nope.json", objs_json = FIX .. "/nope2.json",
      rate_overrides = FIX .. "/nope3.json", supplement = FIX .. "/nope4.json" })
    assert.is_false(c.sources.questie.present)
    assert.are.equal(FIX .. "/nope.json", c.sources.wh_json.path)
    assert.is_false(c.sources.wh_json.present)
    assert.is_nil(c:quest(1001))
    assert.is_nil(c:item_id("Fixture Pelt"))
    assert.are.equal(2, #c:placeholder(1001, 2).objectives)
  end)

  it("partial questie dir records present = 'partial'", function()
    local dir = os.tmpname()
    os.remove(dir)
    os.execute("mkdir -p '" .. dir .. "' && cp " .. FIX .. "/questie/* '" .. dir .. "/' && rm '" .. dir .. "/foreverItemDB.lua'")
    local c = catalog.load(fixture_cfg { questie_dir = dir })
    os.execute("rm -rf '" .. dir .. "'")
    assert.are.equal("partial", c.sources.questie.present)
    assert.are.same({ "foreverItemDB.lua" }, c.sources.questie.missing)
    assert.are.equal("Fixture Wolves", c:quest(1001).name)
    assert.is_nil(c.questie.items[5001])
  end)

  it("marks a supplement objective without a count as assumed and unverified", function()
    local path = os.tmpname()
    local f = assert(io.open(path, "w"))
    f:write('{"quests": {"90020": {"name": "Sup Obj", "level": 5, "required_level": 1, "xp": 100, ' ..
      '"objectives": [{"kind": "item", "ids": [750]}], "source": "fixture"}}}')
    f:close()
    local c = catalog.load(fixture_cfg { supplement = path })
    os.remove(path)
    local q = c:quest(90020)
    assert.are.equal(1, q.objectives[1].count)
    assert.is_true(q.objectives[1].count_assumed)
    assert.are.equal("unverified", q.confidence)
    assert.is_true(has_note(q, "objective 1"))
  end)

  it("marks a QuestieDB objective with no count as assumed", function()
    local q = cat:quest(1004)
    assert.are.equal(1, q.objectives[1].count)
    assert.is_true(q.objectives[1].count_assumed)
    assert.are.equal("unverified", q.confidence)
    assert.is_nil(cat:quest(1001).objectives[1].count_assumed)
  end)

  it("takes level from Wowhead over QuestieDB, with a note on disagreement", function()
    local q = cat:quest(1001)
    assert.are.equal("Fixture Wolves", q.name)
    assert.are.equal(20, q.level)
    assert.are.equal(3, q.required_level)
    assert.are.equal(900, q.xp)
    assert.are.equal("verified", q.confidence)
    assert.is_true(has_note(q, "level"))
    assert.are.same({ 1000 }, q.pre_single)
    assert.are.same({}, q.pre_group)
    assert.are.equal(2001, q.starter)
    assert.are.equal(2002, q.ender)
    assert.is_nil(q.races)
    assert.is_nil(q.classes)
  end)

  it("takes required level from Wowhead, then QuestieDB, defaulting to 1", function()
    assert.are.equal(7, cat:quest(1003).required_level)
    assert.are.equal(1, cat:quest(1006).required_level)
  end)

  it("falls back to QuestXP for level and xp, and to 0 unverified", function()
    local q = cat:quest(1005)
    assert.are.equal(9, q.level)
    assert.are.equal(250, q.xp)
    assert.are.equal("verified", q.confidence)
    local t = cat:quest(1006)
    assert.are.equal(13, t.level)
    assert.are.equal(450, t.xp)
    local u = cat:quest(1003)
    assert.are.equal(5, u.level)
    assert.are.equal(0, u.xp)
    assert.are.equal("unverified", u.confidence)
  end)

  it("treats the 'any race' masks as no restriction", function()
    assert.is_nil(cat:quest(1001).races)
    assert.is_nil(cat:quest(1003).races)
  end)

  it("decodes QuestieDB race and class masks into token lists", function()
    local q = cat:quest(1004)
    assert.are.same({ "Orc", "Tauren", "Troll", "Undead" }, q.races)
    assert.are.same({ "SHAMAN" }, q.classes)
  end)

  it("notes a race disagreement between sources below 90000", function()
    local q = cat:quest(1007)
    assert.are.same({ "Human" }, q.races)
    assert.is_true(has_note(q, "race"))
  end)

  it("ignores a Wowhead race mask of 2^32 or more on a Forever quest, with a note", function()
    local q = cat:quest(90001)
    assert.is_nil(q.races)
    assert.is_true(has_note(q, "race"))
    assert.are.equal("Fixture Forever Quest", q.name)
    assert.are.equal(2001, q.starter)
    assert.are.equal(2002, q.ender)
  end)

  it("uses a usable Wowhead race mask on a Forever quest", function()
    assert.are.same({ "NightElf" }, cat:quest(90002).races)
  end)

  it("carries requires_skill from the supplement, and ignores Wowhead class for Camping 101", function()
    local q = cat:quest(1002)
    assert.are.equal("Camping 101: First Aid", q.name)
    assert.are.equal("First Aid", q.requires_skill)
    assert.is_nil(q.classes)
    assert.is_nil(cat:quest(1001).requires_skill)
  end)

  it("gives a Camping 101: <Prof> quest requires_skill = <Prof> by name (spec §3)", function()
    local q = cat:quest(1008)
    assert.are.equal("Camping 101: Fishing", q.name)
    assert.are.equal("Fishing", q.requires_skill)
    assert.is_nil(q.completed_by_training)
    assert.are.equal("First Aid", cat:quest(1002).requires_skill)
    assert.is_nil(cat:quest(1007).requires_skill)
    assert.is_nil(cat:quest(1007).completed_by_training)
  end)

  it("gives Camping 101: Cooking completed_by_training = Cooking and no requires_skill", function()
    local q = cat:quest(1009)
    assert.are.equal("Camping 101: Cooking", q.name)
    assert.are.equal("Cooking", q.completed_by_training)
    assert.is_nil(q.requires_skill)
  end)

  it("lets the supplement override both Camping 101 fields", function()
    local path = os.tmpname()
    local f = assert(io.open(path, "w"))
    f:write('{"quests": {"1008": {"requires_skill": "Skinning", "source": "fixture"}, ' ..
      '"1009": {"requires_skill": "Cooking", "completed_by_training": "Fishing", "source": "fixture"}}}')
    f:close()
    local c = catalog.load(fixture_cfg { supplement = path })
    os.remove(path)
    assert.are.equal("Skinning", c:quest(1008).requires_skill)
    assert.are.equal("Cooking", c:quest(1009).requires_skill)
    assert.are.equal("Fishing", c:quest(1009).completed_by_training)
  end)

  it("takes objectives from objs.json (keeping from_db_only as a note), then QuestieDB", function()
    local q = cat:quest(1001)
    assert.are.equal(1, #q.objectives)
    assert.are.same({ kind = "item", ids = { 5001 }, count = 4, text = "Fixture Pelt" }, q.objectives[1])
    assert.is_true(has_note(q, "from_db_only"))
    -- explicit empty objs.json entry means no objectives
    assert.are.same({}, cat:quest(1003).objectives)
    local d = cat:quest(1004)
    assert.are.equal("npc", d.objectives[1].kind)
    assert.are.same({ 2003 }, d.objectives[1].ids)
    assert.are.equal("object", d.objectives[2].kind)
  end)

  it("serves a quest known only to the supplement", function()
    local q = cat:quest(90009)
    assert.are.equal("Supplement Only", q.name)
    assert.are.equal(12, q.level)
    assert.are.equal(10, q.required_level)
    assert.are.equal(600, q.xp)
  end)

  it("returns nil for an id in no source, and a marked placeholder on request", function()
    assert.is_nil(cat:quest(777777))
    local p = cat:placeholder(777777, 2)
    assert.are.equal(777777, p.id)
    assert.are.equal(1, p.required_level)
    assert.is_nil(p.races)
    assert.is_nil(p.classes)
    assert.are.equal(2, #p.objectives)
    assert.are.same({ kind = "other", count = 1, text = "Objective 2" }, p.objectives[2])
    assert.are.equal(0, p.xp)
    assert.are.equal("unverified", p.confidence)
    assert.is_nil(cat:quest(777777))
  end)

  it("builds npcs", function()
    local n = cat:npc(2003)
    assert.are.same({ id = 2003, name = "Fixture Boss", level_min = 11, level_max = 11, rank = 1,
      spawns = { [1] = { { 62.6, 46.1 } } }, zone_id = 1 }, n)
    assert.is_nil(cat:npc(1))
  end)

  it("builds items with Wowhead drops and rate overrides", function()
    local i = cat:item(5001)
    assert.are.equal("Fixture Pelt", i.name)
    assert.are.same({ { npc = 2003, rate = 0.25 }, { npc = 2001, rate = 0.5 } }, i.drops)
    local f = cat:item(5002)
    assert.are.same({ { npc = 2001, rate = 0.15 }, { npc = 2002, rate = 0.15 } }, f.drops)
    assert.is_true(f.notes[1]:find("invented fixture note", 1, true) ~= nil)
    assert.is_nil(cat:item(1))
  end)

  it("falls back to QuestieDB drops with a nil rate", function()
    local c = catalog.load(fixture_cfg { wh_json = FIX .. "/none.json", rate_overrides = FIX .. "/none.json" })
    assert.are.same({ { npc = 2003 } }, c:item(5001).drops)
  end)

  it("resolves item names to ids (lowest id wins), nil when unknown", function()
    assert.are.equal(5001, cat:item_id("Fixture Pelt"))
    assert.are.equal(5002, cat:item_id("Fixture Fang"))
    assert.is_nil(cat:item_id("Nothing"))
  end)

  it("encodes a quest as key-sorted JSON identically every time", function()
    local a = json.encode(cat:quest(1001))
    local b = json.encode(catalog.load(fixture_cfg()):quest(1001))
    assert.are.equal(a, b)
  end)
end)

describe("catalog (pinned data)", function()
  local dir = "local/questie/" .. PIN
  local home = os.getenv("HOME") .. "/Projects/wow-pro-leveling/sim/data/"
  if lfs.attributes(dir, "mode") ~= "directory" or lfs.attributes(home .. "wh.json", "mode") ~= "file" then
    pending("pinned QuestieDB or wow-pro-leveling data absent")
    return
  end

  local config = require("hwc.config")
  local cfg = { catalog = config.load({ addon_path = os.getenv("HOME") .. "/Projects/WoW-Pro-Guides" }).catalog }
  local cat = catalog.load(cfg)

  it("loads quest 282 with prerequisite, starter and ender", function()
    local q = cat:quest(282)
    assert.are.same({ 218 }, q.pre_single)
    assert.are.equal(786, q.starter)
    assert.are.equal(1965, q.ender)
  end)

  it("loads quest 179 with Wowhead xp and the objs.json objective", function()
    local q = cat:quest(179)
    assert.are.equal(80, q.xp)
    assert.are.equal("item", q.objectives[1].kind)
    assert.are.same({ 750 }, q.objectives[1].ids)
    assert.are.equal(8, q.objectives[1].count)
  end)

  it("loads Vagash as a level 11 elite", function()
    local n = cat:npc(1388)
    assert.are.equal(1, n.rank)
    assert.are.equal(11, n.level_min)
  end)

  it("gives item 750 at least one drop with a numeric rate", function()
    local found = false
    for _, d in ipairs(cat:item(750).drops) do
      if type(d.rate) == "number" then found = true end
    end
    assert.is_true(found)
  end)

  it("records the pinned file hashes", function()
    local f = assert(io.popen("cd '" .. dir .. "' && shasum -a 256 foreverQuestDB.lua"))
    local out = f:read("*a")
    f:close()
    assert.are.equal(out:match("^(%x+)"), cat.sources.questie.sha256["foreverQuestDB.lua"])
    assert.are.equal(PIN, cat.sources.questie.commit)
  end)
end)
