-- Human-facing words for findings (design spec §4.7, §4.8).
local text = require("hwc.findings.text")

local function F(t)
  t.id = t.id or "F-AAAA0001"
  t.combos = t.combos or { "Dwarf WARRIOR baseline" }
  t.reasons = t.reasons or {}
  return t
end

local ONE = { single = "Dwarf Warrior", by_qid = {}, by_id = {} }

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
      ["did-not-advance"] = "Doesn't advance",
      ["manual-completion"] = "Manual click",
      ["stuck"] = "Stuck",
      ["leftover-quests"] = "Left in log",
      ["lua-error"] = "Lua error",
      ["missing-global"] = "Missing global",
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
  it("title-cases the class and drops baseline", function()
    assert.equal("Dwarf Warrior", text.character("Dwarf WARRIOR baseline"))
  end)
  it("keeps a non-baseline variant", function()
    assert.equal("Dwarf Hunter (lw-skin)", text.character("Dwarf HUNTER lw-skin"))
  end)
  it("handles a two-word race", function()
    assert.equal("Night Elf Rogue", text.character("Night Elf ROGUE baseline"))
  end)
  it("shows a race token by its display name", function()
    assert.equal("Night Elf Warrior", text.character("NightElf WARRIOR baseline"))
    assert.equal("Night Elf Hunter (lw-skin)", text.character("NightElf HUNTER lw-skin"))
  end)
end)

describe("text.combos", function()
  local matrix = {}
  for _, v in ipairs({ "baseline", "a", "b", "c", "d", "e", "f" }) do matrix[#matrix + 1] = "Dwarf HUNTER " .. v end
  for _, c in ipairs({ "Dwarf PRIEST baseline", "Gnome MAGE baseline", "Dwarf WARRIOR baseline",
    "Gnome PRIEST baseline", "Gnome WARRIOR baseline", "Dwarf MAGE baseline" }) do matrix[#matrix + 1] = c end

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
    local s, dropped = text.combos(without("Dwarf PRIEST baseline", "Gnome MAGE baseline"), matrix)
    assert.equal("all except Dwarf Priest, Gnome Mage", s)
    assert.is_false(dropped) -- names every excluded character
  end)
  it("groups by race and class otherwise", function()
    local aff = { "Dwarf WARRIOR baseline" }
    for i = 1, 7 do aff[#aff + 1] = matrix[i] end
    local s, dropped = text.combos(aff, matrix)
    assert.equal("Dwarf Hunter (all 7 variants), Dwarf Warrior", s)
    assert.is_true(dropped)
  end)
  it("names the variants when only some are affected", function()
    local s, dropped = text.combos({ "Dwarf HUNTER baseline", "Dwarf HUNTER a", "Gnome MAGE baseline" }, matrix)
    assert.equal("Dwarf Hunter (baseline, a), Gnome Mage", s)
    assert.is_false(dropped) -- every variant is named
  end)
  it("uses race display names in every summary form", function()
    local m = { "NightElf WARRIOR baseline", "NightElf HUNTER baseline", "NightElf HUNTER a", "Dwarf MAGE baseline",
      "Dwarf PRIEST baseline", "Gnome ROGUE baseline", "Dwarf ROGUE baseline" }
    assert.equal("all except Night Elf Warrior", (text.combos({ m[2], m[3], m[4], m[5], m[6], m[7] }, m)))
    assert.equal("Night Elf Hunter (all 2 variants), Night Elf Warrior", (text.combos({ m[1], m[2], m[3] }, m)))
    assert.equal("Night Elf Hunter (a)", (text.combos({ m[3] }, m)))
    local f = F({ signal = "accept-refused", name = "Pre", qid = 7, reasons = { "race" },
      combos = { "NightElf WARRIOR baseline", "Dwarf MAGE baseline" } })
    assert.equal('"Pre" can\'t be taken by a Dwarf/Night Elf', text.title(f))
  end)
  it("drops no detail when the summary is the plain list", function()
    local m = { "Dwarf WARRIOR baseline", "Gnome MAGE baseline", "Gnome PRIEST baseline", "Dwarf MAGE baseline",
      "Dwarf PRIEST baseline", "Gnome ROGUE baseline", "Dwarf ROGUE baseline" }
    local s, dropped = text.combos({ "Dwarf WARRIOR baseline", "Gnome MAGE baseline" }, m)
    assert.equal("Dwarf Warrior, Gnome Mage", s)
    assert.is_false(dropped)
  end)
end)

describe("text.title and text.sentence (design spec §4.7)", function()
  local function both(f, ctx) return text.title(f), text.sentence(f, ctx or ONE) end

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
    local s = text.sentence(f, { single = "Dwarf Warrior", by_id = {}, by_qid = { [95213] = pre } })
    assert.equal("The guide tells you to accept this quest, but WoWPro hides the step because its prerequisite, "
      .. "quest 95213, is never completed.", s)
  end)
  it("a prerequisite follow-on has no Follows from prefix and no link", function()
    local pre = F({ id = "F-7F8B32EE", signal = "accept-refused", name = "Pre", qid = 95213, reasons = { "prerequisite" } })
    local f = F({ signal = "never-shown-accept", name = "Next", qid = 5, caused_by = pre.id,
      why = "NextStep:PRE&(95213): A mandatory prereq was not met: 95213" })
    local s = text.sentence(f, { single = "Dwarf Warrior", by_id = { [pre.id] = pre }, by_qid = { [95213] = pre } })
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
      combos = { "Gnome MAGE baseline", "Dwarf PRIEST baseline", "Dwarf PRIEST lw-skin" } })
    local t, s = both(f, { by_id = {}, by_qid = {} })
    assert.equal('"Pre" can\'t be taken by a Mage/Priest', t)
    assert.equal("The guide shows this accept, but the quest data says a Mage/Priest can't take quest 7.", s)
  end)
  it("uses an for a vowel-initial race", function()
    local f = F({ signal = "accept-refused", name = "Pre", qid = 7, reasons = { "race" }, combos = { "Orc WARRIOR baseline" } })
    assert.equal("The guide shows this accept, but the quest data says an Orc can't take quest 7.",
      text.sentence(f, { single = "Orc Warrior", by_id = {}, by_qid = {} }))
  end)
  it("accept-refused by prerequisite", function()
    local t, s = both(F({ signal = "accept-refused", name = "Pre", qid = 7, reasons = { "prerequisite" } }))
    assert.equal('"Pre" can\'t be taken yet', t)
    assert.equal("The guide shows this accept, but the quest data says a prerequisite of quest 7 isn't done yet.", s)
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
      combos = { "Dwarf PRIEST baseline", "Gnome MAGE baseline" } })
    local t, s = both(f, { by_id = {}, by_qid = {} })
    assert.equal('"Shown" is shown to the wrong class', t)
    assert.equal("WoWPro shows this step to characters that quest 7 excludes.", s)
  end)
  it("below-level after a grind (the signal's level is the grind's target)", function()
    local t, s = both(F({ signal = "below-level", name = "Low", qid = 7, level = 6, grind = { kills = 12, to = 6 } }))
    assert.equal('"Low" is offered below its level', t)
    assert.equal("The guide reaches this accept below level 6, the level the quest requires; "
      .. "the client ground 12 kills to get there.", s)
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
    assert.equal("Quest 7's objectives weren't complete after the client did this step, so the client clicked it off.",
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
    assert.equal('The run passed this turn-in step, but quest "Wolves" (412) was still in the log '
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
    local ctx = { single = "Dwarf Warrior", by_qid = {}, by_id = { ["F-7F8B32EE"] = parent } }
    assert.equal("The guide tells you to accept this quest, but WoWPro never shows the step.", text.sentence(f, ctx))
  end)
end)
