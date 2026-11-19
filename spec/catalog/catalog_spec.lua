local catalog = require("hwc.catalog")
local home = require("hwc.questie.home")
local json = require("hwc.json")
local lfs = require("lfs")

local FIX = "spec/fixtures/catalog"

-- questie_source = false drops the fixture Source, so questie_dir is opened.
local function fixture_cfg(over)
  local c = {
    questie_source = dofile(FIX .. "/questie_source.lua"),
    counts = FIX .. "/counts.json",
  }
  for k, v in pairs(over or {}) do c[k] = v end
  if c.questie_source == false then c.questie_source = nil end
  return { catalog = c, class = "WARRIOR", faction = "Alliance" }
end

local function has_note(q, needle)
  for _, n in ipairs(q.notes) do
    if n:find(needle, 1, true) then return true end
  end
  return false
end

describe("catalog.count_from_text", function()
  local f = catalog.count_from_text

  it("takes the number just before the name, a few words back at most", function()
    assert.same({ 8, "number" }, { f("Sten Stoutarm would like 8 pieces of Tough Wolf Meat.", "Tough Wolf Meat") })
    assert.same({ 10, "number" }, { f("Kill 10 Kobold Vermin.", "Kobold Vermin") })
    assert.same({ 6, "number" }, { f("Bring six Fixture Ribs.", "Fixture Rib") })
  end)

  it("matches the plural of the last word or of the word before 'of'", function()
    assert.same({ 15, "number" }, { f("Kill 15 Mosshide Gnolls and 10 Mosshide Mongrels.", "Mosshide Gnoll") })
    assert.same({ 10, "number" }, { f("Kill 15 Mosshide Gnolls and 10 Mosshide Mongrels.", "Mosshide Mongrel") })
    assert.same({ 5, "number" }, { f("Bring 5 Flasks of Oil to Captain Grayson.", "Flask of Oil") })
    assert.same({ 4, "number" }, { f("Collect 4 Wolves.", "Wolf") })
  end)

  it("never takes a number from another item's clause", function()
    assert.same({ 1, "named-once" }, { f("Bring 3 Okra, Fixture Malt and a map.", "Fixture Malt") })
  end)

  it("gives 1 for a name the context makes one thing: possessive, or after a singular word", function()
    assert.same({ 1, "named-single" }, { f("Find Pamela's doll.", "Pamela's Doll") })
    assert.same({ 1, "named-single" }, { f("Return Bingles' Wrench.", "Bingles' Wrench") })
    assert.same({ 1, "named-single" }, { f("Return the Sparkling Stone.", "A Sparkling Stone") })
    assert.same({ 1, "named-single" }, { f("Kill Gath'Ilzogg and bring his head.", "Head") })
  end)

  it("calls a bare name with no number and no such context a guess", function()
    assert.same({ 1, "named-once" }, { f("Bring some Soothing Spices to Chef Jessen.", "Soothing Spices") })
    assert.same({ 1, "named-once" }, { f("Bring Holy Spring Water to Grimbooze.", "Holy Spring Water") })
  end)

  it("is nil when the name isn't there or is only plural with no number", function()
    assert.is_nil(f("Bring 2 Frostmane Bear Pendants.", "Iceclaw Bear Pendant"))
    assert.is_nil(f("Kill the Snow Leopard Prowlers.", "Snow Leopard Prowler"))
    assert.is_nil(f("Collect Bloodpetals.", "Bloodpetal"))
  end)
end)

describe("catalog (fixtures)", function()
  local cat = catalog.load(fixture_cfg())

  it("records every source with presence and provenance", function()
    assert.is_true(cat.sources.questie.present)
    assert.are.equal("v0.0.0", cat.sources.questie.tag)
    assert.are.equal("fixture", cat.sources.questie.build)
    assert.are.equal(FIX .. "/questie_source.lua", cat.sources.questie.path)
    assert.is_true(cat.sources.counts.present)
    assert.matches("^%x+$", cat.sources.counts.sha256)
  end)

  it("records missing sources as absent and still loads", function()
    local c = catalog.load(fixture_cfg {
      questie_source = false, counts = FIX .. "/nope.json" })
    assert.is_false(c.sources.questie.present)
    assert.are.equal(FIX .. "/nope.json", c.sources.counts.path)
    assert.is_false(c.sources.counts.present)
    assert.is_nil(c:quest(1001))
    assert.is_nil(c:item_id("Fixture Pelt"))
    assert.are.same({}, c:quest_rewards(179))
    assert.is_nil(c:npc(2001))
    assert.is_nil(c:item(5001))
    assert.are.equal(2, #c:placeholder(1001, 2).objectives)
  end)

  it("records no install as absent, with the reason 'none installed'", function()
    local c = catalog.load(fixture_cfg { questie_source = false })
    assert.are.same({ present = false, reason = "none installed" }, c.sources.questie)
  end)

  -- Review Focus 4: a version dir without its TOC is a broken install, not an error.
  it("records a questie_dir without the TOC as absent and broken, without raising", function()
    local dir = os.tmpname()
    os.remove(dir)
    assert(lfs.mkdir(dir))
    local ok, c = pcall(catalog.load, fixture_cfg { questie_source = false, questie_dir = dir })
    lfs.rmdir(dir)
    assert.is_true(ok, tostring(c))
    assert.is_false(c.sources.questie.present)
    assert.are.equal(dir, c.sources.questie.path)
    assert.matches("^broken", c.sources.questie.reason)
    assert.is_nil(c:npc(2001))
  end)

  local function counts_file(body)
    local path = os.tmpname()
    local f = assert(io.open(path, "w"))
    f:write(body)
    f:close()
    return path
  end

  it("takes a hand-checked count from the counts file, matched by kind and id", function()
    local q = cat:quest(1001)
    assert.are.equal(4, q.objectives[1].count)
    assert.is_nil(q.objectives[1].count_assumed)
    assert.are.equal("counts file", q.objectives[1].count_from)
    assert.is_true(has_note(q, "item 5001 count 4 from the counts file (fixture hand check)"))
  end)

  it("notes a counts entry that matches no objective, and leaves the count assumed", function()
    local q = cat:quest(1004)
    assert.is_true(q.objectives[1].count_assumed)
    assert.is_true(has_note(q, "counts file: npc 9999 matches no objective of this quest"))
  end)

  it("rejects a counts entry without a source or with a bad count", function()
    for _, body in ipairs({
      '{"quests": {"1001": {"objectives": [{"kind": "item", "id": 5001, "count": 4}]}}}',
      '{"quests": {"1001": {"source": "x", "objectives": [{"kind": "item", "id": 5001, "count": 0}]}}}',
      '{"quests": {"1001": {"source": "x", "objectives": [{"kind": "spell", "id": 5001, "count": 2}]}}}',
      '{"quests": {"1001": {"source": "x", "objectives": []}}}',
    }) do
      local path = counts_file(body)
      local ok, err = pcall(catalog.load, fixture_cfg { counts = path })
      os.remove(path)
      assert.is_false(ok, body)
      assert.matches("quest 1001", err)
    end
  end)

  it("marks a QuestieDB objective with no count in the text or counts file as assumed", function()
    local q = cat:quest(1004)
    assert.are.equal(1, q.objectives[1].count)
    assert.is_true(q.objectives[1].count_assumed)
    assert.are.equal("unverified", q.confidence)
    assert.is_true(has_note(q, "in neither the quest text nor the counts file (assumed 1)"))
  end)

  it("reads a count from the quest's objective text", function()
    local q = cat:quest(1011)
    assert.are.equal(8, q.objectives[1].count)
    assert.are.equal("number", q.objectives[1].count_from)
    assert.are.equal(1, q.objectives[2].count)
    assert.are.equal("named-once", q.objectives[2].count_from)
    -- A 1 read from a name with no number is a guess: the quest stays unverified.
    assert.are.equal("unverified", q.confidence)
    assert.is_true(has_note(q, "is 1 only because the quest text names it with no number"))
    assert.is_true(has_note(q, "item 5001 count 8 from the quest text (a number before its name)"))
  end)

  it("counts a named unique NPC with no number as one, verified; another NPC stays a guess", function()
    local q = cat:quest(1013)
    assert.are.equal("named-single", q.objectives[1].count_from)
    assert.is_true(has_note(q, "npc 2003 count 1 from the quest text (a named NPC with one or two spawns, or elite)"))
    assert.are.equal("named-once", q.objectives[2].count_from)
  end)

  it("lets the counts file win over the quest text", function()
    local q = cat:quest(1012)
    assert.are.equal(5, q.objectives[1].count)
    assert.are.equal("counts file", q.objectives[1].count_from)
  end)

  it("takes level and required level from QuestieDB, xp from QuestXP", function()
    local q = cat:quest(1001)
    assert.are.equal("Fixture Wolves", q.name)
    assert.are.equal(18, q.level)
    assert.are.equal(3, q.required_level)
    assert.are.equal(700, q.xp)
    assert.are.same({ 1000 }, q.pre_single)
    assert.are.same({}, q.pre_group)
    assert.are.equal(2001, q.starter)
    assert.are.equal(2002, q.ender)
    assert.are.same({ "Dwarf", "Gnome", "Human", "NightElf" }, q.races)
    assert.is_nil(q.classes)
  end)

  it("takes required level from QuestieDB, defaulting to 1", function()
    assert.are.equal(5, cat:quest(1003).required_level)
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

  -- Ruling AB: name-based rules (Camping 101) cannot apply to a quest no source names.
  it("marks a quest with no name in any source unverified, with a note", function()
    local q = cat:quest(1006)
    assert.is_nil(q.name)
    assert.are.equal("unverified", q.confidence)
    assert.is_true(has_note(q, "no name in any source; name-based rules (Camping 101) cannot apply"))
  end)

  -- 77 is classic Alliance; 4294967373 adds Skyborne (Alliance), bit 32
  -- (QuestieDB src/corrections/enum/expansions.lua:27, :364). Neither means "any race":
  -- a Horde character can't take these quests.
  it("decodes the Alliance faction masks, Skyborne bit included", function()
    assert.are.same({ "Dwarf", "Gnome", "Human", "NightElf" }, cat:quest(1001).races)
    assert.are.same({ "Dwarf", "Gnome", "Human", "NightElf", "SkyborneAlliance" }, cat:quest(1003).races)
  end)

  -- 8589934770 is Forever's ALL_HORDE: classic Horde plus Skyborne (Horde), bit 33
  -- (QuestieDB src/corrections/enum/expansions.lua:28, :366), past the 32-bit range.
  it("decodes QuestieDB race and class masks into race keys and class tokens", function()
    local q = cat:quest(1004)
    assert.are.same({ "Orc", "SkyborneHorde", "Tauren", "Troll", "Undead" }, q.races)
    assert.are.same({ "SHAMAN" }, q.classes)
  end)

  it("decodes a single-race QuestieDB mask", function()
    assert.are.same({ "Human" }, cat:quest(1007).races)
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

  it("carries QuestieDB sourceItemId (the item the starter hands over) as source_item", function()
    assert.are.equal(5002, cat:quest(1010).source_item)
    assert.is_nil(cat:quest(1001).source_item)
  end)

  it("gives Camping 101: Cooking completed_by_training = Cooking and no requires_skill", function()
    local q = cat:quest(1009)
    assert.are.equal("Camping 101: Cooking", q.name)
    assert.are.equal("Cooking", q.completed_by_training)
    assert.is_nil(q.requires_skill)
  end)

  it("takes reputation rewards from QuestieDB in its order, an empty array when absent", function()
    assert.same({ { faction = 93, value = -500 }, { faction = 92, value = 100 } }, cat:quest(1382).reputation_reward)
    assert.same({}, cat:quest(1001).reputation_reward)
  end)

  it("takes the reputation gates from requiredMinRep and requiredMaxRep, nil when absent", function()
    local q = cat:quest(1383)
    assert.same({ faction = 72, value = 9000 }, q.min_rep)
    assert.same({ faction = 92, value = 3000 }, q.max_rep)
    assert.is_nil(cat:quest(1382).min_rep)
    assert.is_nil(cat:quest(1382).max_rep)
  end)

  it("drops a reputation gate unless both of its fields are numbers", function()
    assert.is_nil(cat:quest(1384).min_rep)
    assert.is_nil(cat:quest(1384).max_rep)
  end)

  it("names a faction from QuestieDB's faction constants, else 'Faction <id>'", function()
    assert.equal("Gelkis Clan Centaur", cat:faction_name(92))
    assert.equal("Stormwind", cat:faction_name(72))
    assert.equal("The League of Arathor", cat:faction_name(509))
    assert.equal("Brawlgar Arena Season 1", cat:faction_name(1374))
    assert.equal("Faction 91", cat:faction_name(91))
    assert.equal("Faction 92", catalog.load(fixture_cfg { questie_source = false }):faction_name(92))
  end)

  it("takes objectives from QuestieDB, none when it lists none", function()
    -- Without the counts file, so the row's own shape shows.
    local q = catalog.load(fixture_cfg { counts = FIX .. "/nope.json" }):quest(1001)
    assert.are.equal(1, #q.objectives)
    assert.are.same({ kind = "item", ids = { 5001 }, count = 1, count_assumed = true, text = "Fixture Pelt" }, q.objectives[1])
    assert.are.same({}, cat:quest(1003).objectives)
    local d = cat:quest(1004)
    assert.are.equal("npc", d.objectives[1].kind)
    assert.are.same({ 2003 }, d.objectives[1].ids)
    assert.are.equal("object", d.objectives[2].kind)
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

  it("builds items with QuestieDB drop rates, else npcDrops with a nil rate", function()
    local i = cat:item(5001)
    assert.are.equal("Fixture Pelt", i.name)
    assert.are.same({ { npc = 2001, rate = 0.5 }, { npc = 2003, rate = 0.25 } }, i.drops)
    assert.are.same({ { npc = 2001 }, { npc = 2002 } }, cat:item(5002).drops)
    assert.is_nil(cat:item(1))
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

describe("Catalog:chain_part", function()
  local cat = catalog.load(fixture_cfg())
  local function part(id) local p, t = cat:chain_part(id); return { p, t } end

  it("numbers a same-name chain through pre_single, pre_group and next_in_chain", function()
    assert.same({ 1, 4 }, part(1101))
    assert.same({ 3, 4 }, part(1103))
    assert.same({ 4, 4 }, part(1104))
  end)
  it("gives a differently named branch no part", function() assert.same({}, part(1105)) end)
  it("terminates on a cycle and gives no part (Review Focus 1)", function()
    assert.same({}, part(1111))
    assert.same({}, part(1112))
  end)
  it("terminates when only next_in_chain loops and gives no part", function()
    assert.same({}, part(1141))
    assert.same({}, part(1143))
  end)
  it("numbers same-name siblings behind one predecessor deterministically (Review Focus 2)", function()
    assert.same({ 2, 2 }, part(1122))
    assert.same({ 2, 2 }, part(1123))
    assert.same({ 1, 2 }, part(1121))
  end)
  it("gives a quest absent from the catalog no part and no error (Review Focus 3)", function()
    assert.same({}, part(999999))
    assert.same({}, part(nil))
  end)
  it("gives a same-name quest that is not adjacent no part (Review Focus 5)", function()
    assert.same({}, part(1131))
    assert.same({}, part(1132))
  end)
  it("keeps next_in_chain on the quest", function() assert.equal(1102, cat:quest(1101).next_in_chain) end)
end)

describe("catalog (installed QuestieDB)", function()
  local root = home.root()
  if not home.active_dir(root) then
    pending("no QuestieDB installed: run hwc init")
    return
  end

  local config = require("hwc.config")
  local cfg = config.load({ addon_path = os.getenv("HOME") .. "/Projects/WoW-Pro-Guides" })
  local cat = catalog.load(cfg)

  it("loads quest 282 with prerequisite, starter and ender", function()
    local q = cat:quest(282)
    assert.are.same({ 218 }, q.pre_single)
    assert.are.equal(786, q.starter)
    assert.are.equal(1965, q.ender)
  end)

  it("loads quest 179 with its QuestieDB item objective", function()
    local q = cat:quest(179)
    assert.are.equal("item", q.objectives[1].kind)
    assert.are.same({ 750 }, q.objectives[1].ids)
  end)

  it("gives item 750 at least one drop with a numeric rate", function()
    local found = false
    for _, d in ipairs(cat:item(750).drops) do
      if type(d.rate) == "number" then found = true end
    end
    assert.is_true(found)
  end)

  it("loads Vagash as a level 11 elite", function()
    local n = cat:npc(1388)
    assert.are.equal(1, n.rank)
    assert.are.equal(11, n.level_min)
    assert.are.equal(0, n.flags or 0)
  end)

  it("carries QuestieDB npcFlags: Tognus Flintfire (1241) is a gossip/questgiver/trainer NPC", function()
    assert.are.equal(19, cat:npc(1241).flags)
  end)

  it("records the installed release", function()
    local tag = home.active(root)
    local rel = home.read_release(root, tag)
    local q = cat.sources.questie
    assert.is_true(q.present)
    assert.are.equal(home.version_dir(root, tag), q.path)
    assert.are.equal(rel.tag, q.tag)
    assert.are.equal(rel.sha256, q.sha256)
    assert.matches("^%x+$", q.build)
  end)
end)

-- Quest reward items come from QuestieDB itemData.questRewards (item -> rewarding quests).
describe("Catalog:quest_rewards", function()
  it("lists the items QuestieDB names as a quest's rewards, sorted", function()
    local c = catalog.load(fixture_cfg())
    -- 4990 comes after 5004 in the fixture file: the list is sorted, not file order.
    assert.same({ 4990, 5004 }, c:quest_rewards(179))
    assert.same({}, c:quest_rewards(9999))
  end)
end)
