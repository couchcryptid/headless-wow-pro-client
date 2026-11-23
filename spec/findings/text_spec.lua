-- Human-facing words for findings (design spec §4.7, §4.8).
local text = require("hwc.findings.text")

local function F(t)
  t.id = t.id or "F-AAAA0001"
  t.combos = t.combos or { "Dwarf WARRIOR none" }
  t.reasons = t.reasons or {}
  return t
end

local ONE = { single = "Dwarf Warrior", by_id = {} }

describe("text constants", function()
  it("exposes the severity display table", function()
    assert.same({ marker = "🔴", word = "High", rank = 1 }, text.SEVERITY["high"])
    assert.same({ marker = "🟠", word = "Medium-high", rank = 2 }, text.SEVERITY["medium-high"])
    assert.same({ marker = "🟡", word = "Medium", rank = 3 }, text.SEVERITY["medium"])
    assert.same({ marker = "⚪", word = "Low", rank = 4 }, text.SEVERITY["low"])
  end)
  it("labels every signal in plain words", function()
    assert.same({
      ["never-shown-accept"] = "Never offered",
      ["hidden-use-step"] = "Use step never shown",
      ["accept-refused"] = "Can't be taken",
      ["log-full"] = "Quest log full",
      ["orphan-turnin"] = "Turn-in without the quest",
      ["wrong-race-class"] = "Wrong race or class",
      ["below-level"] = "Offered below level",
      ["level-check"] = "Level check reached short",
      ["did-not-advance"] = "Doesn't advance",
      ["manual-completion"] = "Manual click",
      ["stuck"] = "Stuck",
      ["leftover-quests"] = "Left in log",
      ["lua-error"] = "Lua error",
      ["missing-global"] = "Missing global",
      ["rep-faction-unmet"] = "REP faction never met",
      ["arrival-data-gap"] = "Arrival data missing",
      ["emulation-gap"] = "Not emulated",
    }, text.SIGNALS)
  end)
  it("labels every early stop reason, and not the normal end", function()
    assert.same({
      iterations = "Hit its step limit",
      errors = "Too many addon errors",
      ["no-step"] = "No step to show",
      ["max-guides"] = "Reached --max-guides",
      stuck = "Stuck on a step",
      ["guide-cycle"] = "Guide loops back on itself",
    }, text.STOPS)
    assert.is_nil(text.STOPS["no-next-guide"])
  end)
  it("labels every stop reason driver/run.lua emits except no-next-guide", function()
    local f = assert(io.open("src/hwc/driver/run.lua", "r"))
    local src = f:read("*a")
    f:close()
    local n = 0
    for reason in src:gmatch('self:stop%("([^"]+)"%)') do
      n = n + 1
      if reason ~= "no-next-guide" then assert.is_string(text.STOPS[reason], "no STOPS entry for " .. reason) end
    end
    assert.is_true(n > 0, "found no self:stop calls in run.lua")
  end)
  it("has no markdown helpers", function()
    assert.is_nil(text.anchor)
    assert.is_nil(text.md_text)
    assert.is_nil(text.links)
  end)
  it("returns nil for an unknown verb letter", function() assert.is_nil(text.VERBS["Q"]) end)
end)

describe("text.step", function()
  it("uses the verb for a known letter", function()
    assert.equal('Get flight path at "Thelsamar"', text.step("f", "Thelsamar"))
    assert.equal('Set hearth at "Stoutlager Inn"', text.step("h", "Stoutlager Inn"))
  end)
  it("words the parser-confirmed t, P, *, a and M letters", function()
    assert.equal('Turn in when complete "Report"', text.step("t", "Report"))
    assert.equal('Take portal to "Stormwind"', text.step("P", "Stormwind"))
    assert.equal('Trash "Old Map"', text.step("*", "Old Map"))
    assert.equal('Accept repeatable "Daily"', text.step("a", "Daily"))
    assert.equal('Make "Copper Bar"', text.step("M", "Copper Bar"))
  end)
  it("falls back to the raw letter for an unknown action", function()
    assert.equal('X "Foo"', text.step("X", "Foo"))
  end)
  it("quotes the bare name with no action", function() assert.equal('"Foo"', text.step(nil, "Foo")) end)
  it("is nil without a name", function()
    assert.is_nil(text.step("A", ""))
    assert.is_nil(text.step("A", nil))
  end)
end)

describe("text.character", function()
  it("title-cases the class and drops an empty profession set", function()
    assert.equal("Dwarf Warrior", text.character("Dwarf WARRIOR none"))
  end)
  it("lists the professions", function()
    assert.equal("Dwarf Hunter (Leatherworking, Skinning)", text.character("Dwarf HUNTER leatherworking,skinning"))
    assert.equal("Dwarf Warrior (Herbalism, Skinning)", text.character("Dwarf WARRIOR herbalism,skinning"))
    assert.equal("Dwarf Warrior (First Aid, Fishing)", text.character("Dwarf WARRIOR first-aid,fishing"))
  end)
  it("handles a two-word race", function()
    assert.equal("Night Elf Rogue", text.character("Night Elf ROGUE none"))
  end)
  it("shows a race token by its display name", function()
    assert.equal("Night Elf Warrior", text.character("NightElf WARRIOR none"))
    assert.equal("Night Elf Hunter (Tailoring)", text.character("NightElf HUNTER tailoring"))
  end)
end)

describe("text.combos", function()
  local matrix = {}
  for _, v in ipairs({ "none", "alchemy", "herbalism", "mining", "skinning", "tailoring", "fishing" }) do matrix[#matrix + 1] = "Dwarf HUNTER " .. v end
  for _, c in ipairs({ "Dwarf PRIEST none", "Gnome MAGE none", "Dwarf WARRIOR none",
    "Gnome PRIEST none", "Gnome WARRIOR none", "Dwarf MAGE none" }) do matrix[#matrix + 1] = c end

  local function without(...)
    local skip = {}
    for _, c in ipairs({ ... }) do skip[c] = true end
    local out = {}
    for _, c in ipairs(matrix) do if not skip[c] then out[#out + 1] = c end end
    return out
  end

  it("says all N characters when every combo is affected", function()
    local s, dropped = text.combos(matrix, matrix)
    assert.equal("all 13 characters", s)
    assert.is_false(dropped) -- "all" is complete
  end)
  it("lists the excluded characters when at most 3 are unaffected", function()
    local s, dropped = text.combos(without("Dwarf PRIEST none", "Gnome MAGE none"), matrix)
    assert.equal("all except Dwarf Priest, Gnome Mage", s)
    assert.is_false(dropped) -- names every excluded character
  end)
  it("groups by race and class otherwise", function()
    local aff = { "Dwarf WARRIOR none" }
    for i = 1, 7 do aff[#aff + 1] = matrix[i] end
    local s, dropped = text.combos(aff, matrix)
    assert.equal("Dwarf Hunter (all 7 profession sets), Dwarf Warrior", s)
    assert.is_true(dropped)
  end)
  it("names the profession sets when only some are affected", function()
    local s, dropped = text.combos({ "Dwarf HUNTER none", "Dwarf HUNTER alchemy", "Gnome MAGE none" }, matrix)
    assert.equal("Dwarf Hunter (none, Alchemy), Gnome Mage", s)
    assert.is_false(dropped) -- every profession set is named
  end)
  it("uses race display names in every summary form", function()
    local m = { "NightElf WARRIOR none", "NightElf HUNTER none", "NightElf HUNTER tailoring", "Dwarf MAGE none",
      "Dwarf PRIEST none", "Gnome ROGUE none", "Dwarf ROGUE none" }
    assert.equal("all except Night Elf Warrior", (text.combos({ m[2], m[3], m[4], m[5], m[6], m[7] }, m)))
    assert.equal("Night Elf Hunter (all 2 profession sets), Night Elf Warrior", (text.combos({ m[1], m[2], m[3] }, m)))
    assert.equal("Night Elf Hunter (Tailoring)", (text.combos({ m[3] }, m)))
    local f = F({ signal = "accept-refused", name = "Pre", qid = 7, reasons = { "race" },
      combos = { "NightElf WARRIOR none", "Dwarf MAGE none" } })
    assert.equal('"Pre" can\'t be taken by a Dwarf/Night Elf', text.title(f))
  end)
  it("drops no detail when the summary is the plain list", function()
    local m = { "Dwarf WARRIOR none", "Gnome MAGE none", "Gnome PRIEST none", "Dwarf MAGE none",
      "Dwarf PRIEST none", "Gnome ROGUE none", "Dwarf ROGUE none" }
    local s, dropped = text.combos({ "Dwarf WARRIOR none", "Gnome MAGE none" }, m)
    assert.equal("Dwarf Warrior, Gnome Mage", s)
    assert.is_false(dropped)
  end)
end)

describe("text.title and text.sentence (design spec §4.7)", function()
  local function both(f, ctx) return text.title(f), text.sentence(f, ctx or ONE) end

  describe("quest chain parts and named quest references", function()
    it("text.quest_ref names the quest, numbers a chain part, and falls back to the bare id", function()
      assert.equal('quest 1029 "Raene\'s Cleansing" (8/11)', text.quest_ref(1029, "Raene's Cleansing", { part = 8, total = 11 }))
      assert.equal('quest 1045 "Raene\'s Cleansing"', text.quest_ref(1045, "Raene's Cleansing"))
      assert.equal("quest 1045", text.quest_ref(1045, nil, { part = 1, total = 2 }))
      assert.equal("quest 1045", text.quest_ref(1045, ""))
      assert.equal('"X" (2/3)', text.with_part("X", { part = 2, total = 3 }))
    end)
    it("a never-shown-accept title numbers the part", function()
      local f = F({ signal = "never-shown-accept", name = "Raene's Cleansing", qid = 1030, chain = { part = 9, total = 11 },
        why = "NextStep:PRE&(1029): A mandatory prereq was not met: 1029",
        pre_qname = "Raene's Cleansing", pre_chain = { part = 8, total = 11 } })
      local t, s = both(f)
      assert.equal('"Raene\'s Cleansing" (9/11) is never offered', t)
      assert.matches('quest 1029 "Raene\'s Cleansing" (8/11), is never completed.', s, 1, true)
    end)
    it("a prerequisite why with no space after the colon still names the id", function()
      local f = F({ signal = "never-shown-accept", name = "Next", qid = 5, why = "x not met:77" })
      assert.matches("prerequisite, quest 77, is never", text.sentence(f, ONE), 1, true)
      assert.equal("not met:%s*(%d+)", text.PRE_NOT_MET)
    end)
    it("a never-shown-accept prerequisite with no name stays plain", function()
      local f = F({ signal = "never-shown-accept", name = "Next", qid = 5, why = "x not met: 77" })
      assert.matches("prerequisite, quest 77, is never", text.sentence(f, ONE), 1, true)
    end)
    it("the left-in-log title numbers the part", function()
      local t = text.title(F({ signal = "leftover-quests", qid = 1029, qname = "Raene's Cleansing", chain = { part = 8, total = 11 } }))
      assert.equal('Quest "Raene\'s Cleansing" (8/11) (1029) is left in the log', t)
    end)
    it("the missing list names and numbers each prerequisite", function()
      local f = F({ signal = "accept-refused", name = "Next", qid = 5, reasons = { "prerequisite" },
        missing = { 1029 }, missing_names = { ["1029"] = "Raene's Cleansing" }, missing_chain = { ["1029"] = { part = 8, total = 11 } } })
      assert.matches('needs quest 1029 "Raene\'s Cleansing" (8/11), which', text.sentence(f, ONE), 1, true)
    end)
    describe("missing_outcome endings", function()
      local function sent(extra)
        local f = { signal = "accept-refused", name = "Next", qid = 5, reasons = { "prerequisite" } }
        for k, v in pairs(extra) do f[k] = v end
        return text.sentence(F(f), ONE)
      end
      local P = "The guide shows this accept, but the quest data says it needs "
      it("a single quest ends with which is never accepted", function()
        assert.equal(P .. 'quest 98387 "Blackrock Blockade", which is never accepted.',
          sent({ missing = { 98387 }, missing_names = { ["98387"] = "Blackrock Blockade" },
            missing_outcome = { ["98387"] = "never-accepted" } }))
      end)
      it("a single quest that is done only later", function()
        assert.equal(P .. "quest 7, which isn't done until later in the run.",
          sent({ missing = { 7 }, missing_outcome = { ["7"] = "completed-later" } }))
      end)
      it("all-of with mixed outcomes joins with , and ", function()
        assert.equal(P .. "quest 7, which is never accepted, and quest 8, which is never completed.",
          sent({ missing = { 7, 8 }, missing_outcome = { ["7"] = "never-accepted", ["8"] = "never-completed" } }))
      end)
      it("any-of with a shared outcome", function()
        assert.equal(P .. "one of quest 7 or quest 8, none of which is ever accepted.",
          sent({ missing = { 7, 8 }, missing_any = true, missing_outcome = { ["7"] = "never-accepted", ["8"] = "never-accepted" } }))
        assert.equal(P .. "one of quest 7 or quest 8, none of which is ever completed.",
          sent({ missing = { 7, 8 }, missing_any = true, missing_outcome = { ["7"] = "never-completed", ["8"] = "never-completed" } }))
      end)
      it("mixed any-of joins with , or ", function()
        assert.equal(P .. "quest 7, which is never accepted, or quest 8, which is never completed.",
          sent({ missing = { 7, 8 }, missing_any = true, missing_outcome = { ["7"] = "never-accepted", ["8"] = "never-completed" } }))
      end)
      it("a quest with no outcome keeps today's wording", function()
        assert.equal(P .. "quest 7, which isn't done yet.", sent({ missing = { 7 } }))
        assert.equal(P .. "quest 7, which isn't done yet.", sent({ missing = { 7 }, missing_outcome = {} }))
      end)
    end)
    it("the finding's own quest is named in sentences, and plain without a name", function()
      local named = F({ signal = "orphan-turnin", action = "T", qid = 1045, qname = "Raene's Cleansing", chain = { part = 10, total = 11 } })
      assert.matches('turn in quest 1045 "Raene\'s Cleansing" (10/11), but', text.sentence(named, ONE), 1, true)
      local bare = F({ signal = "orphan-turnin", action = "T", qid = 1045 })
      assert.matches("turn in quest 1045, but", text.sentence(bare, ONE), 1, true)
    end)
    it("a finding with no chain and no qid renders as before", function()
      assert.equal('"Next" is never offered', text.title(F({ signal = "never-shown-accept", name = "Next" })))
    end)
  end)

  it("never-shown-accept with an unmet prerequisite, no finding for it", function()
    local f = F({ signal = "never-shown-accept", name = "Next", qid = 5,
      why = "NextStep:PRE&(95213): A mandatory prereq was not met: 95213" })
    local t, s = both(f)
    assert.equal('"Next" is never offered', t)
    assert.equal("The guide tells you to accept this quest, but WoWPro hides the step because its prerequisite, "
      .. "quest 95213, is never completed.", s)
  end)
  it("hidden-use-step names the item the step needs and the item it uses", function()
    local f = F({ signal = "hidden-use-step", name = "Divined Scroll", qid = 1016, use = "5456", loot = { [5455] = 1 } })
    local t, s = both(f)
    assert.equal('"Divined Scroll" is never shown', t)
    assert.equal("WoWPro hides this use step until item 5455 is in bags, and it wasn't while the run passed here, "
      .. "so the client never used item 5456.", s)
  end)
  it("hidden-use-step lists several loot items ascending", function()
    local f = F({ signal = "hidden-use-step", use = "5456", loot = { [9] = 1, [5455] = 2, [12] = 1 } })
    assert.equal("WoWPro hides this use step until items 9, 12, 5455 are in bags, and it wasn't while the run "
      .. "passed here, so the client never used item 5456.", text.sentence(f, ONE))
  end)
  it("never-shown-accept names a prerequisite that has its own finding as plain quest N", function()
    local f = F({ signal = "never-shown-accept", name = "Next", qid = 5,
      why = "NextStep:PRE&(95213): A mandatory prereq was not met: 95213" })
    local pre = F({ id = "F-7F8B32EE", signal = "accept-refused", name = "Pre", qid = 95213, reasons = { "prerequisite" } })
    local s = text.sentence(f, { single = "Dwarf Warrior", by_id = { [pre.id] = pre } })
    assert.equal("The guide tells you to accept this quest, but WoWPro hides the step because its prerequisite, "
      .. "quest 95213, is never completed.", s)
  end)
  it("a prerequisite follow-on has no Follows from prefix and no link", function()
    local pre = F({ id = "F-7F8B32EE", signal = "accept-refused", name = "Pre", qid = 95213, reasons = { "prerequisite" } })
    local f = F({ signal = "never-shown-accept", name = "Next", qid = 5, caused_by = pre.id,
      why = "NextStep:PRE&(95213): A mandatory prereq was not met: 95213" })
    local s = text.sentence(f, { single = "Dwarf Warrior", by_id = { [pre.id] = pre } })
    assert.equal("The guide tells you to accept this quest, "
      .. "but WoWPro hides the step because its prerequisite, quest 95213, is never completed.", s)
  end)
  it("never-shown-accept with some other why", function()
    local f = F({ signal = "never-shown-accept", name = "Next", qid = 5, why = "Something odd" })
    local t, s = both(f)
    assert.equal('"Next" is never offered', t)
    assert.equal('The guide tells you to accept this quest, but WoWPro never shows the step. '
      .. 'The engine said: "Something odd".', s)
  end)
  -- The reason goes in the sentence: the reader shouldn't have to open the fold.
  it("never-shown-accept skipped as optional", function()
    local _, s = both(F({ signal = "never-shown-accept", name = "Next", qid = 5,
      why = "NextStep(): Optional steps default to skipped." }))
    assert.equal("WoWPro skips this accept because the step is optional, and optional steps are skipped by default.", s)
  end)
  it("never-shown-accept hidden by level", function()
    local _, s = both(F({ signal = "never-shown-accept", name = "Next", qid = 5, level = 19,
      why = "NextStep(): Skipping step because player level not high enough." }))
    assert.equal("WoWPro hides this accept until the character's level is high enough; "
      .. "the character was level 19 when the guide passed it.", s)
    local _, s2 = both(F({ signal = "never-shown-accept", name = "Next", qid = 5,
      why = "NextStep(): Skipping step because player level not high enough." }))
    assert.equal("WoWPro hides this accept until the character's level is high enough.", s2)
  end)
  it("never-shown-accept with no why", function()
    local t, s = both(F({ signal = "never-shown-accept", name = "Next", qid = 5 }))
    assert.equal('"Next" is never offered', t)
    assert.equal("The guide tells you to accept this quest, but WoWPro never shows the step and gave no reason.", s)
  end)
  it("accept-refused by race, single character", function()
    local t, s = both(F({ signal = "accept-refused", name = "Pre", qid = 7, reasons = { "race" } }))
    assert.equal('"Pre" can\'t be taken by a Dwarf', t)
    assert.equal("The guide shows this accept, but the quest data says a Dwarf can't take quest 7.", s)
  end)
  it("accept-refused by class across several combos", function()
    local f = F({ signal = "accept-refused", name = "Pre", qid = 7, reasons = { "class" },
      combos = { "Gnome MAGE none", "Dwarf PRIEST none", "Dwarf PRIEST leatherworking,skinning" } })
    local t, s = both(f, { by_id = {} })
    assert.equal('"Pre" can\'t be taken by a Mage/Priest', t)
    assert.equal("The guide shows this accept, but the quest data says a Mage/Priest can't take quest 7.", s)
  end)
  it("uses an for a vowel-initial race", function()
    local f = F({ signal = "accept-refused", name = "Pre", qid = 7, reasons = { "race" }, combos = { "Orc WARRIOR none" } })
    assert.equal("The guide shows this accept, but the quest data says an Orc can't take quest 7.",
      text.sentence(f, { single = "Orc Warrior", by_id = {} }))
  end)
  it("accept-refused by prerequisite", function()
    local t, s = both(F({ signal = "accept-refused", name = "Pre", qid = 7, reasons = { "prerequisite" } }))
    assert.equal('"Pre" can\'t be taken yet', t)
    assert.equal("The guide shows this accept, but the quest data says a prerequisite of quest 7 isn't done yet.", s)
  end)
  it("accept-refused by prerequisite names the missing quests, with the catalog's name when known", function()
    local s = text.sentence(F({ signal = "accept-refused", name = "The Reports", qid = 291, reasons = { "prerequisite" },
      missing = { 98323 }, missing_names = { ["98323"] = "Secure the Mountain" } }), ONE)
    assert.equal("The guide shows this accept, but the quest data says it needs quest 98323 \"Secure the Mountain\", "
      .. "which isn't done yet.", s)
    s = text.sentence(F({ signal = "accept-refused", name = "X", qid = 9, reasons = { "prerequisite" },
      missing = { 5, 6 }, missing_names = { ["6"] = "Six" } }), ONE)
    assert.equal("The guide shows this accept, but the quest data says it needs quest 5 and quest 6 \"Six\", "
      .. "which aren't done yet.", s)
  end)
  it("accept-refused by an any-of (pre_single) prerequisite says one of them would do", function()
    local s = text.sentence(F({ signal = "accept-refused", name = "X", qid = 9, reasons = { "prerequisite" },
      missing = { 5, 6 }, missing_any = true, missing_names = { ["6"] = "Six" } }), ONE)
    assert.equal("The guide shows this accept, but the quest data says it needs one of quest 5 or quest 6 \"Six\", "
      .. "none of which is done yet.", s)
    s = text.sentence(F({ signal = "accept-refused", name = "X", qid = 9, reasons = { "prerequisite" },
      missing = { 98323 }, missing_any = true, missing_names = { ["98323"] = "Secure the Mountain" } }), ONE)
    assert.equal("The guide shows this accept, but the quest data says it needs quest 98323 \"Secure the Mountain\", "
      .. "which isn't done yet.", s)
  end)
  it("accept-refused by reputation names the faction and both standings", function()
    local t, s = both(F({ signal = "accept-refused", name = "Pre", qid = 7, reasons = { "reputation" },
      rep = { faction = 72, name = "Stormwind", bound = "min", value = 3000, points = 2000 } }))
    assert.equal('"Pre" can\'t be taken: reputation too low', t)
    assert.equal("The quest data needs Friendly with Stormwind; this character has Neutral (2000). "
      .. "Reputation from kills, item turn-ins and encounters isn't modelled, so a real player may have it.", s)
  end)
  it("accept-refused by reputation above a max gate, at a value inside a band", function()
    local t, s = both(F({ signal = "accept-refused", name = "Pre", qid = 7, reasons = { "reputation" },
      rep = { faction = 92, name = "Gelkis Clan Centaur", bound = "max", value = 2500, points = 2600 } }))
    assert.equal('"Pre" can\'t be taken: reputation too high', t)
    assert.equal("The quest data needs less than Neutral (2500) with Gelkis Clan Centaur; this character has Neutral (2600). "
      .. "Reputation from kills, item turn-ins and encounters isn't modelled, so a real player may have it.", s)
  end)
  it("accept-refused by reputation without the gate's details", function()
    local t, s = both(F({ signal = "accept-refused", name = "Pre", qid = 7, reasons = { "reputation" } }))
    assert.equal('"Pre" can\'t be taken: reputation too low/high', t)
    assert.equal("The quest data needs a reputation standing this character doesn't have. "
      .. "Reputation from kills, item turn-ins and encounters isn't modelled, so a real player may have it.", s)
  end)
  it("rep-faction-unmet with no faction name", function()
    local t, s = both(F({ signal = "rep-faction-unmet", action = "C", name = "Strange Alliance", qid = 1382, faction = 91 }))
    assert.equal("REP step checks Faction 91, which this character never met", t)
    assert.equal("WoWPro asks for reputation with faction 91, but this character has never met that faction, "
      .. "so the step is skipped. Reputation from kills and encounters isn't modelled; if the guide meant "
      .. "another faction, the id is wrong.", s)
  end)
  it("rep-faction-unmet names a known faction", function()
    local t = both(F({ signal = "rep-faction-unmet", name = "x", faction = 92, faction_name = "Gelkis Clan Centaur" }))
    assert.equal("REP step checks Gelkis Clan Centaur, which this character never met", t)
  end)
  it("rep-faction-unmet names the tag's own faction and the id it checks", function()
    local t, s = both(F({ signal = "rep-faction-unmet", action = "C", name = "Strange Alliance", qid = 1382,
      faction = 91, faction_name = "Faction 91", tag_faction = "Gelkis Clan Centaur" }))
    assert.equal("REP step names Gelkis Clan Centaur but checks Faction 91, which this character never met", t)
    assert.equal("WoWPro asks for reputation with faction 91, but this character has never met that faction, "
      .. "so the step is skipped. Reputation from kills and encounters isn't modelled; if the guide meant "
      .. "another faction, the id is wrong.", s)
  end)
  it("log-full", function()
    local t, s = both(F({ signal = "log-full", name = "Pre", qid = 7 }))
    assert.equal('"Pre" can\'t be taken: quest log full', t)
    assert.equal("The guide shows this accept while the quest log is already full.", s)
  end)
  it("orphan-turnin", function()
    local t, s = both(F({ signal = "orphan-turnin", action = "T", name = "Report", qid = 7 }))
    assert.equal('Turn in "Report" for a quest the character never had', t)
    assert.equal("The guide asks you to turn in quest 7, but this character never had it.", s)
  end)
  it("wrong-race-class, single character", function()
    local t, s = both(F({ signal = "wrong-race-class", name = "Shown", qid = 7, reasons = { "race" } }))
    assert.equal('"Shown" is shown to the wrong race', t)
    assert.equal("WoWPro shows this step to a Dwarf, but quest 7 is for other races.", s)
  end)
  it("wrong-race-class by class, single character", function()
    local t, s = both(F({ signal = "wrong-race-class", name = "Shown", qid = 7, reasons = { "class" } }))
    assert.equal('"Shown" is shown to the wrong class', t)
    assert.equal("WoWPro shows this step to a Warrior, but quest 7 is for other classes.", s)
  end)
  it("wrong-race-class, multi-combo run", function()
    local f = F({ signal = "wrong-race-class", name = "Shown", qid = 7, reasons = { "class" },
      combos = { "Dwarf PRIEST none", "Gnome MAGE none" } })
    local t, s = both(f, { by_id = {} })
    assert.equal('"Shown" is shown to the wrong class', t)
    assert.equal("WoWPro shows this step to characters that quest 7 excludes.", s)
  end)
  it("below-level after a grind (the signal's level is the grind's target)", function()
    local t, s = both(F({ signal = "below-level", name = "Low", qid = 7, level = 6, grind = { kills = 12, to = 6 } }))
    assert.equal('"Low" is offered below its level', t)
    assert.equal("The guide reaches this accept below level 6, the level the quest requires; "
      .. "the client ground 12 kills to get there.", s)
  end)
  it("below-level words the levels short, and explains a gap under 2", function()
    local f = { signal = "below-level", name = "The Haunted Isle", qid = 7, level = 32, levels_short = 0.9,
      grind = { kills = 228, to = 32 } }
    local t, s = both(F(f))
    assert.equal('"The Haunted Isle" is offered 0.9 levels below the level it requires', t)
    assert.equal("The guide reaches this accept 0.9 levels below level 32, the level the quest requires "
      .. "(the client ground 228 kills to get there). Gaps under 2 levels are within what the simulation's "
      .. "missing XP explains (no incidental kills or rested XP).", s)
    f.levels_short = 2.5
    t, s = both(F(f))
    assert.equal('"The Haunted Isle" is offered 2.5 levels below the level it requires', t)
    assert.equal("The guide reaches this accept 2.5 levels below level 32, the level the quest requires "
      .. "(the client ground 228 kills to get there).", s)
  end)
  it("below-level under 0.1 levels short says less than 0.1", function()
    local t, s = both(F({ signal = "below-level", name = "Tiny", qid = 7, level = 8, levels_short = 0.04,
      grind = { kills = 2, to = 8 } }))
    assert.equal('"Tiny" is offered less than 0.1 levels below the level it requires', t)
    assert.equal("The guide reaches this accept less than 0.1 levels below level 8, the level the quest requires "
      .. "(the client ground 2 kills to get there). Gaps under 2 levels are within what the simulation's "
      .. "missing XP explains (no incidental kills or rested XP).", s)
    t = both(F({ signal = "below-level", name = "Tiny", qid = 7, levels_short = 0, grind = { kills = 2, to = 8 } }))
    assert.equal('"Tiny" is offered less than 0.1 levels below the level it requires', t)
  end)
  it("words a level check by its gap and its check point", function()
    local f = { signal = "level-check", name = "Level 2", qid = nil, gap = 1.0,
      grind = { kills = 40, to = 2, point = 250, offset = -650 } }
    local t, s = both(F(f))
    assert.equal('The guide\'s level check "Level 2" is reached 1.0 levels short', t)
    assert.equal("The client ground 40 kills to reach the point the guide checks "
      .. "(level 2, within 650 XP of level 3). " .. require("hwc.findings.gap").MARGIN_SENTENCE, s)
    f.gap, f.grind = 2.5, { kills = 90, to = 5, point = 300, offset = 300 }
    t, s = both(F(f))
    assert.equal('The guide\'s level check "Level 2" is reached 2.5 levels short', t)
    assert.equal("The client ground 90 kills to reach the point the guide checks (level 5, with at least 300 XP).", s)
    f.gap, f.grind = 0.04, { kills = 1, to = 5, point = 0, offset = 0 }
    t, s = both(F(f))
    assert.equal('The guide\'s level check "Level 2" is reached less than 0.1 levels short', t)
    assert.truthy(s:find("(level 5).", 1, true))
  end)
  it("words below-level at 4 levels or more without the margin sentence", function()
    local _, s = both(F({ signal = "below-level", name = "Low", qid = 7, levels_short = 4.5,
      grind = { kills = 9, to = 9 } }))
    assert.equal("The guide reaches this accept 4.5 levels below level 9, the level the quest requires "
      .. "(the client ground 9 kills to get there).", s)
  end)
  it("below-level without a grind stays neutral", function()
    local _, s = both(F({ signal = "below-level", name = "Low", qid = 7, level = 4 }))
    assert.equal("The guide reaches this accept below the level the quest requires.", s)
  end)
  it("did-not-advance after the client acted", function()
    local t, s = both(F({ signal = "did-not-advance", action = "K", name = "Stuck", qid = 7 }))
    assert.equal('"Stuck" doesn\'t advance', t)
    assert.equal("The client did what this step asks, but WoWPro didn't mark it done, so the client clicked it off.", s)
  end)
  it("did-not-advance on a refused step says why it was refused", function()
    local function s_of(action, reason)
      local f = F({ signal = "did-not-advance", action = action, name = "Stuck", qid = 7, reasons = { reason } })
      local _, s = both(f)
      return s
    end
    assert.equal("The turn-in was refused because quest 7 wasn't complete, so the client clicked the step off.",
      s_of("T", "incomplete"))
    assert.equal("The objectives of quest 7 weren't complete after the client did this step, so the client clicked it off.",
      s_of("C", "incomplete"))
    assert.equal("Quest 7 wasn't in the log when the guide reached this step, so the client clicked it off.",
      s_of("K", "not-in-log"))
    assert.equal("The turn-in needs a profession skill the character doesn't have, so the client clicked the step off.",
      s_of("T", "requires-skill"))
    assert.equal("The step was refused (already-completed), so the client clicked it off.",
      s_of("A", "already-completed"))
  end)
  it("manual-completion", function()
    local t, s = both(F({ signal = "manual-completion", name = "Click" }))
    assert.equal('"Click" needed a manual click', t)
    assert.equal("No game event completed this step, so the client clicked it off.", s)
  end)
  it("stuck settle-limit", function()
    local t, s = both(F({ signal = "stuck", name = "Foo", reasons = { "settle-limit" } }))
    assert.equal('Stuck after "Foo"', t)
    assert.equal("WoWPro kept scheduling work after this step and never settled.", s)
  end)
  it("stuck same-step", function()
    local t, s = both(F({ signal = "stuck", name = "Foo", reasons = { "same-step" } }))
    assert.equal('Stuck on "Foo"', t)
    assert.equal("WoWPro stayed on this step past the watchdog limit.", s)
  end)
  it("stuck max-iterations", function()
    local t, s = both(F({ signal = "stuck", name = "Foo", reasons = { "max-iterations" } }))
    assert.equal("Run hit its step limit", t)
    assert.equal("The run stopped at its step limit before this guide ended.", s)
  end)
  it("text.title handles a stuck finding with no name", function()
    local f = F({ signal = "stuck", reasons = { "no-current-step" } })
    assert.equal("No step to show", text.title(f))
    assert.equal("WoWPro had no current step to show, so the run couldn't continue.", text.sentence(f, ONE))
  end)
  it("stuck no-guide-loaded", function()
    local t, s = both(F({ signal = "stuck", reasons = { "no-guide-loaded" } }))
    assert.equal("No guide loaded", t)
    assert.equal("WoWPro loaded no guide, so nothing ran.", s)
  end)
  it("stuck guide-cycle", function()
    local t, s = both(F({ signal = "stuck", name = "Onwards", reasons = { "guide-cycle" } }))
    assert.equal('Guide loops back to "Onwards"', t)
    assert.equal("Finishing this step sent the run to another guide, and WoWPro then came back to this same step, "
      .. "which would only send it away again; the run stopped here.", s)
  end)
  it("stuck load-guide-failed", function()
    local t, s = both(F({ signal = "stuck", reasons = { "load-guide-failed" } }))
    assert.equal("Next guide didn't load", t)
    assert.equal("WoWPro didn't load the next guide in the chain, so the run stopped.", s)
  end)
  it("leftover-quests with a name", function()
    local t, s = both(F({ signal = "leftover-quests", qid = 412, qname = "Wolves" }))
    assert.equal('Quest "Wolves" (412) is left in the log', t)
    assert.equal('The run passed this turn-in step, but quest 412 "Wolves" was still in the log '
      .. "when the run ended.", s)
  end)
  it("leftover-quests accepted earlier and not turned in within scope", function()
    local t, s = both(F({ signal = "leftover-quests", qid = 412, qname = "Wolves", reasons = { "not-turned-in" } }))
    assert.equal('Quest "Wolves" (412) is not turned in within scope', t)
    assert.equal("The guide accepts this quest here, but no guide the run played has a turn-in step for it; "
      .. "it was still in the log when the run ended.", s)
  end)
  it("leftover-quests with no qname", function()
    local t, s = both(F({ signal = "leftover-quests", qid = 412 }))
    assert.equal("Quest 412 is left in the log", t)
    assert.equal("The run passed this turn-in step, but quest 412 was still in the log when the run ended.", s)
  end)
  it("lua-error uses the first line of the message", function()
    local f = F({ signal = "lua-error", name = "boom\nsecond", message = "boom\nsecond" })
    assert.equal("Lua error: boom", text.title(f))
    assert.equal("WoWPro raised an error during the run. The message and stack are in the detail below.",
      text.sentence(f, ONE))
  end)
  it("lua-error truncates a long message to 80 characters plus an ellipsis", function()
    local msg = string.rep("x", 100)
    assert.equal("Lua error: " .. string.rep("x", 80) .. "…", text.title(F({ signal = "lua-error", message = msg })))
    local exact = string.rep("y", 80)
    assert.equal("Lua error: " .. exact, text.title(F({ signal = "lua-error", message = exact })))
  end)
  it("unknown signal falls back to the raw signal and an empty sentence", function()
    local f = F({ signal = "mystery", action = "A", name = "Foo" })
    assert.equal('mystery: Accept "Foo"', text.title(f))
    assert.equal("", text.sentence(f, ONE))
  end)

  it("keeps a title with markdown characters plain", function()
    local parent = F({ id = "F-00000009", signal = "lua-error", message = "x.lua:1: '<eof>' expected near ']' *a_b*" })
    assert.equal("Lua error: x.lua:1: '<eof>' expected near ']' *a_b*", text.title(parent))
  end)

  it("a follow-on keeps the first clause only, with no prefix", function()
    local parent = F({ id = "F-7F8B32EE", signal = "accept-refused", name = "Pre", qid = 7, reasons = { "prerequisite" } })
    local f = F({ signal = "never-shown-accept", name = "Next", qid = 5, why = "Something odd", caused_by = "F-7F8B32EE" })
    local ctx = { single = "Dwarf Warrior", by_id = { ["F-7F8B32EE"] = parent } }
    assert.equal("The guide tells you to accept this quest, but WoWPro never shows the step.", text.sentence(f, ctx))
  end)
end)

describe("arrival finding text (spec section 10)", function()
  local function dnaf(reason, extra)
    local f = { signal = "did-not-advance", action = "R", name = "Stormwind", reasons = { reason },
      named = { name = "Stormwind", tz = "1453; Stormwind City" } }
    for k, v in pairs(extra or {}) do f[k] = v end
    return f
  end
  local function gapf(reason, extra)
    local f = { signal = "arrival-data-gap", reasons = { reason }, name = reason .. ": k" }
    for k, v in pairs(extra or {}) do f[k] = v end
    return f
  end
  it("words each did-not-advance arrival reason", function()
    assert.equal('"Stormwind" and TZ "1453; Stormwind City" name no area in Forever, so the addon can never complete '
      .. "this step by zone; the client clicked it off.", text.sentence(dnaf("name-not-an-area"), {}))
    assert.equal('"Stormwind" name no area in Forever, so the addon can never complete this step by zone; the client '
      .. "clicked it off.", text.sentence(dnaf("name-not-an-area", { named = { name = "Stormwind" } }), {}))
    assert.equal('The step names "Stormwind" (TZ "1453; Stormwind City"), but the player arrived in Elwynn Forest / '
      .. "Goldshire, so the addon didn't complete it and the client clicked it off.",
      text.sentence(dnaf("arrival-mismatch", { arrived = { zone = "Elwynn Forest", subzone = "Goldshire" } }), {}))
    assert.equal('The step names "Stormwind" (TZ "1453; Stormwind City"), but the player arrived in Elwynn Forest, '
      .. "so the addon didn't complete it and the client clicked it off.",
      text.sentence(dnaf("arrival-mismatch", { arrived = { zone = "Elwynn Forest" } }), {}))
    -- Resolved: the player landed by the loose match (spec section 9).
    local landed = { resolved_by = "loose", arrived = { zone = "Stormwind City" } }
    assert.equal("The guide flies to a flight point the character hasn't discovered, so the client travelled there "
      .. "another way.", text.sentence(dnaf("flight-point-undiscovered", landed), {}))
    assert.equal('No flight point on the taxi map matches "Stormwind", so the client travelled there another way.',
      text.sentence(dnaf("no-taxi-node", landed), {}))
  end)
  it("doesn't claim another way of travel when nothing says where the player landed", function()
    assert.equal("The guide flies to a flight point the character hasn't discovered, so the client clicked the "
      .. "step off.", text.sentence(dnaf("flight-point-undiscovered"), {}))
    assert.equal('No flight point on the taxi map matches "Stormwind", so the client clicked the step off.',
      text.sentence(dnaf("no-taxi-node"), {}))
  end)
  it("words an f for a flight point the character already knows", function()
    assert.equal('The guide asks you to get the flight point at "Ironforge, Dun Morogh", which the character '
      .. "already knows, so no new flight path was discovered and the client clicked the step off.",
      text.sentence(dnaf("flight-point-already-known", { action = "f", named = { name = "Ironforge, Dun Morogh" } }),
        {}))
  end)
  it("words an emulation-gap", function()
    local f = { signal = "emulation-gap", reasons = { "aura-not-emulated" }, buff = "1229451",
      name = "aura-not-emulated: G:7" }
    assert.equal("Not emulated", text.SIGNALS["emulation-gap"])
    assert.equal("Not emulated: aura-not-emulated: G:7", text.title(f))
    assert.equal("hwc doesn't emulate auras, so the buff this step checks (BUFF 1229451) never appears; "
      .. "the client clicked the step off.", text.sentence(f, {}))
  end)
  it("words the gap reasons", function()
    assert.equal("The Forever client tables aren't installed, so arrival steps aren't judged. Run hwc update.",
      text.sentence(gapf("tables-missing"), {}))
    for _, r in ipairs({ "fp-unknown", "start-node-unknown", "destination-unresolved", "arrival-unknown", "inn-unknown",
      "waypoint-arrival-not-emulated", "subzone-unknown", "taxi-not-taken", "arrival-data-mismatch" }) do
      assert.matches("^hwc has no arrival data for this: .+%.$", text.sentence(gapf(r), {}))
    end
    assert.matches("never took the flight", text.sentence(gapf("taxi-not-taken"), {}), 1, true)
    -- What hwc lacks, never what the step names (the step isn't blamed for a gap).
    assert.equal("hwc has no arrival data for this: the landing subzone isn't captured.",
      text.sentence(gapf("subzone-unknown"), {}))
    assert.equal("hwc has no arrival data for this: no flight point is within reach of the departure in hwc's tables.",
      text.sentence(gapf("fp-unknown"), {}))
    assert.equal("hwc has no arrival data for this: no captured inn is near here.",
      text.sentence(gapf("inn-unknown"), {}))
    assert.equal("hwc has no arrival data for this: no captured crossing leaves from here.",
      text.sentence(gapf("arrival-unknown"), {}))
    -- An F step's arrival-unknown is a departure map hwc's tables place on no continent.
    assert.equal("hwc has no arrival data for this: hwc's tables place the departure map on no continent.",
      text.sentence(gapf("arrival-unknown", { action = "F" }), {}))
    for _, r in ipairs({ "fp-unknown", "arrival-unknown", "inn-unknown", "subzone-unknown" }) do
      assert.is_nil(text.sentence(gapf(r), {}):find("this step names", 1, true), r)
    end
    assert.matches("(x vs y)", text.sentence(gapf("arrival-data-mismatch", { detail = "x vs y" }), {}), 1, true)
    assert.equal("Arrival data missing", text.SIGNALS["arrival-data-gap"])
    assert.equal("No arrival data: subzone-unknown: k", text.title(gapf("subzone-unknown", { name = "subzone-unknown: k" })))
  end)
end)
