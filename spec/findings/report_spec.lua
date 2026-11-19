local group = require("hwc.findings.group")
local report = require("hwc.findings.report")
local json = require("hwc.json")
local dkjson = require("dkjson")

local function runlog(signals)
  return { character = { race = "Dwarf", class = "WARRIOR", professions = {} }, rank = 2, steps = {},
    signals = signals, guides = {} }
end

local function sigs()
  return {
    { signal = "did-not-advance", gid = "G1", file = "a.lua", line = 40, action = "T", name = "Report", qid = 314,
      why = "w", level = 3, log = { 314, 5 }, before = { name = "b" }, after = { name = "c" }, confidence = "verified" },
    { signal = "accept-refused", gid = "G1", file = "a.lua", line = 10, action = "A", name = "Pre", qid = 96629,
      reason = "prerequisite", confidence = "unverified" },
    { signal = "never-shown-accept", gid = "G1", file = "a.lua", line = 20, action = "A", name = "Next", qid = 5,
      why = "PRE&(x): A mandatory prereq was not met: 96629" },
    { signal = "manual-completion", gid = "G1", file = "a.lua", line = 50, action = "H", name = "Hearth", expected = true },
    { signal = "lua-error", message = "boom\nsecond line", stack = "x.lua:1" },
    { signal = "lua-error", message = "hx", reason = "harness" },
  }
end

local function findings() return group.findings({ runlog(sigs()) }) end
local function header() return { scope = "s", matrix = { combos = { "Dwarf WARRIOR none" } } } end

describe("report.build", function()
  it("round trips through JSON", function()
    local fs = findings()
    local doc = dkjson.decode(json.encode(report.build(fs, header()), { indent = true }))
    assert.equal(2, doc.format)
    assert.equal(#fs, #doc.findings)
    for i, f in ipairs(doc.findings) do
      assert.equal(fs[i].id, f.id)
      assert.equal(fs[i].signal, f.signal)
      assert.same(fs[i].combos, f.combos)
      assert.is_true(#f.title > 0)
      assert.is_true(#f.sentence > 0)
    end
  end)

  it("encodes zero findings as an empty array", function()
    local s = json.encode(report.build({}, header()))
    assert.truthy(s:find('"findings"%s*:%s*%[%s*%]'))
    assert.equal(0, report.build({}, header()).summary.findings)
  end)

  it("counts non-expected, non-harness findings with a severity", function()
    local fs = findings()
    local doc = report.build(fs, header())
    local n, roots, by_sev, by_sig = 0, 0, {}, {}
    for _, f in ipairs(fs) do
      if f.severity and not f.expected and not (f.harness or f.signal == "missing-global") then
        n = n + 1
        if not f.caused_by then roots = roots + 1 end
        by_sev[f.severity] = (by_sev[f.severity] or 0) + 1
        by_sig[f.signal] = (by_sig[f.signal] or 0) + 1
      end
    end
    assert.is_true(n > 0 and n < #fs)
    assert.equal(n, doc.summary.findings)
    assert.equal(roots, doc.summary.roots)
    assert.same(by_sev, doc.summary.by_severity)
    assert.same(by_sig, doc.summary.by_signal)
    assert.equal(#fs, #doc.findings)
  end)

  it("marks empty lists as arrays without mutating inputs", function()
    local fs = findings()
    local doc = report.build(fs, header())
    -- header.notes is a map, and this header gives it nothing to say: {} is right there.
    local s = json.encode(doc):gsub('"notes":{}', "")
    assert.falsy(s:find("{}", 1, true))
    for _, f in ipairs(fs) do assert.is_nil(f.title); assert.is_nil(getmetatable(f.combos)) end
  end)

  it("passes the header fields through without mutating the header", function()
    local h = header()
    local doc = report.build({}, h)
    assert.equal("s", doc.header.scope)
    assert.same(h.matrix, doc.header.matrix)
    assert.is_nil(h.gaps)
    assert.is_nil(h.warnings)
  end)

  it("appends the run's assumptions to the gaps without changing report.GAPS", function()
    local before = #report.GAPS
    local doc = report.build({}, { assumptions = { "x" } })
    local gaps = doc.header.gaps
    assert.equal(before + 1, #gaps)
    assert.equal("x", gaps[#gaps])
    assert.equal(before, #report.GAPS)
    assert.is_nil(doc.header.assumptions)
  end)

  it("lists quest-reward-only reputation as a static gap", function()
    local found = false
    for _, g in ipairs(report.GAPS) do
      if g == "reputation is gained from quest rewards only (no kills, item turn-ins or encounters)" then found = true end
    end
    assert.is_true(found)
  end)

  it("writes format 2", function()
    assert.equal(2, report.build({}, {}).format)
  end)

  it("gives each finding its own step and a plain sentence", function()
    local fs = findings()
    local doc = report.build(fs, header())
    local follow
    for i, f in ipairs(doc.findings) do
      assert.same({ action = fs[i].action, name = fs[i].name }, f.step)
      if f.caused_by then follow = f end
    end
    assert.truthy(follow, "fixture has a follow-on")
    assert.is_nil(follow.sentence:find("[", 1, true))
    assert.is_nil(follow.sentence:find("](#", 1, true))
    assert.is_nil(follow.sentence:find("Follows from", 1, true))
  end)

  it("counts explains as counted descendants", function()
    local fs = {
      { id = "F-1", signal = "accept-refused", severity = "high", qid = 1, causes = { "F-2", "F-3" }, combos = {} },
      { id = "F-2", signal = "did-not-advance", severity = "medium", caused_by = "F-1", causes = {}, combos = {} },
      { id = "F-3", signal = "lua-error", severity = "high", harness = true, caused_by = "F-1", causes = {}, combos = {} },
    }
    local doc = report.build(fs, header())
    assert.equal(1, doc.findings[1].explains)
    assert.is_nil(doc.findings[2].explains)
    assert.is_nil(doc.findings[3].explains)
  end)

  it("carries labels for signals, actions, combos and stops", function()
    local h = { matrix = { combos = { "NightElf WARRIOR none", "Dwarf MAGE alchemy,herbalism" } } }
    local labels = report.build({}, h).labels
    assert.equal("Night Elf Warrior", labels.combos["NightElf WARRIOR none"])
    assert.equal("Dwarf Mage (Alchemy, Herbalism)", labels.combos["Dwarf MAGE alchemy,herbalism"])
    assert.equal("Never offered", labels.signals["never-shown-accept"])
    assert.equal("Accept", labels.actions.A)
    assert.equal("Hit its step limit", labels.stops.iterations)
  end)

  it("carries the level-flag rule wording", function()
    local labels = report.build({}, {}).labels
    assert.same({
      ["enter-under"] = "Entered below the guide's start level",
      ["leave-under"] = "Left below the guide's end level",
      ["enter-over"] = "Entered above the guide's end level",
    }, labels.flags)
  end)

  it("carries gaps and warnings in the header", function()
    local doc = report.build({}, { client = { dirty = true }, catalog = { supplement = { present = false } } })
    assert.same(report.GAPS, doc.header.gaps)
    assert.same({
      "The client checkout had uncommitted changes; this run may not be reproducible from its commit.",
      "Catalog source supplement was missing. Camping 101 quests aren't recognised, so characters with "
        .. "professions play like ones with none.",
    }, doc.header.warnings)
  end)

  it("encodes no warnings as an empty array", function()
    local s = json.encode(report.build({}, {}))
    assert.truthy(s:find('"warnings"%s*:%s*%[%s*%]'))
  end)

  it("counts by file and by combo, primary and follow-on, counted findings only", function()
    local fs = {
      { id = "F-1", signal = "accept-refused", severity = "high", file = "a.lua", causes = { "F-2" },
        combos = { "Dwarf WARRIOR none", "Gnome MAGE none" } },
      { id = "F-2", signal = "did-not-advance", severity = "high", file = "a.lua", caused_by = "F-1", causes = {},
        combos = { "Dwarf WARRIOR none" } },
      { id = "F-3", signal = "manual-completion", severity = "low", file = "a.lua", expected = true, causes = {},
        combos = { "Dwarf WARRIOR none" } },
      { id = "F-4", signal = "missing-global", severity = "low", causes = {}, combos = { "Dwarf WARRIOR none" } },
    }
    local s = report.build(fs, header()).summary
    assert.same({ ["a.lua"] = { high = { primary = 1, follow = 1 } } }, s.by_file)
    assert.same({
      ["Dwarf WARRIOR none"] = { high = { primary = 1, follow = 1 } },
      ["Gnome MAGE none"] = { high = { primary = 1, follow = 0 } },
    }, s.by_combo)
  end)
end)

describe("labels and notes for wording the markdown carried", function()
  it("labels severities and the folds", function()
    local labels = report.build({}, {}).labels
    assert.same({ high = "High", ["medium-high"] = "Medium-high", medium = "Medium", low = "Low" }, labels.severities)
    assert.same({ harness = "gaps in this client's WoW API stubs, not guide bugs",
      expected = "the client clicked off by design (notes, repair-or-restock stops, guide ends)" }, labels.folds)
  end)

  it("says what jumped guides mean, or nothing", function()
    assert.equal("Jumped guides: 2 (GA, GB). Their quests were never done, so prerequisite, turn-in and "
      .. "leftover-quest findings after a jump may come from it.", report.jumped_note({ "GA", "GB" }))
    assert.is_nil(report.jumped_note(nil))
    assert.is_nil(report.jumped_note({}))
  end)

  it("states the dungeon setting and the accepts it skipped, or nothing", function()
    assert.equal("Skip dungeon quests: off (WoWPro's EnableDungeons).", report.dungeons_note({ skip = false, skipped = 0 }))
    assert.equal("Skip dungeon quests: on (WoWPro's EnableDungeons). This client doesn't run dungeons, so the "
      .. "1 dungeon accept WoWPro skipped isn't listed as a finding.", report.dungeons_note({ skip = true, skipped = 1 }))
    assert.equal("Skip dungeon quests: on (WoWPro's EnableDungeons). This client doesn't run dungeons, so the "
      .. "3 dungeon accepts WoWPro skipped aren't listed as findings.", report.dungeons_note({ skip = true, skipped = 3 }))
    assert.is_nil(report.dungeons_note(nil))
    assert.is_nil(report.dungeons_note({ skipped = 2 }))
  end)

  it("lists carried quests by name and id, or nothing", function()
    assert.equal("Taken in the guide the run stopped in and still in the log, which that guide or the next may "
      .. "turn in after the run's end, so not findings: 2 quests: \"Frostmane Hold\" (287), quest 313.",
      report.carried_note({ { qid = 287, qname = "Frostmane Hold" }, { qid = 313 } }))
    assert.equal("Taken in the guide the run stopped in and still in the log, which that guide or the next may "
      .. "turn in after the run's end, so not findings: 1 quest: quest 9.", report.carried_note({ { qid = 9, qname = "" } }))
    assert.equal("Taken in the guide the run stopped in and still in the log, which that guide or the next may "
      .. "turn in after the run's end, so not findings: 1 quest: \"Raene's Cleansing\" (8/11) (1029).",
      report.carried_note({ { qid = 1029, qname = "Raene's Cleansing", chain = { part = 8, total = 11 } } }))
    assert.is_nil(report.carried_note(nil))
    assert.is_nil(report.carried_note({}))
  end)

  it("glosses the guide rank, or nothing", function()
    assert.equal("Guide rank: 2 (WoWPro's setting for which optional steps are shown).", report.rank_note(2))
    assert.is_nil(report.rank_note(nil))
  end)

  it("lists the filters in order, on one line, or nothing", function()
    assert.equal('Filters: --include "Alliance/Dun_*", --exclude "Alliance/Dun_5 11.lua".',
      report.filters_note({ { kind = "include", pattern = "Alliance/Dun_*" },
        { kind = "exclude", pattern = "Alliance/Dun_5\n11.lua" } }))
    assert.is_nil(report.filters_note(nil))
    assert.is_nil(report.filters_note({}))
  end)

  it("lists the guides played, or nothing", function()
    assert.equal("Guides played: GA, GB.", report.played_note({ "GA", "GB" }))
    assert.is_nil(report.played_note(nil))
    assert.is_nil(report.played_note({}))
  end)

  it("lists included guides never reached, or nothing", function()
    assert.equal("Included but never reached: GC.", report.unreached_note({ "GC" }))
    assert.is_nil(report.unreached_note(nil))
    assert.is_nil(report.unreached_note({}))
  end)

  it("lists races that reached no included guide, or nothing", function()
    assert.equal("Races that reached no included guide: Human, NightElf.",
      report.skipped_races_note({ "Human", "NightElf" }))
    assert.is_nil(report.skipped_races_note(nil))
    assert.is_nil(report.skipped_races_note({}))
  end)

  it("puts the notes in the header", function()
    local notes = report.build({}, { rank = 3, jumped = { "GA" } }).header.notes
    assert.equal(report.rank_note(3), notes.rank)
    assert.equal(report.jumped_note({ "GA" }), notes.jumped)
    assert.is_nil(notes.dungeons)
    assert.is_nil(notes.carried)
    for _, k in ipairs({ "filters", "played", "unreached", "skipped_races" }) do assert.is_nil(notes[k]) end
    local f = report.build({}, { filters = { { kind = "include", pattern = "X" } }, played = { "GA" },
      unreached = { "GB" }, skipped_races = { "Human" } }).header.notes
    assert.equal(report.filters_note({ { kind = "include", pattern = "X" } }), f.filters)
    assert.equal(report.played_note({ "GA" }), f.played)
    assert.equal(report.unreached_note({ "GB" }), f.unreached)
    assert.equal(report.skipped_races_note({ "Human" }), f.skipped_races)
    assert.truthy(json.encode(report.build({}, {})):find('"notes"%s*:%s*{%s*}'))
  end)
end)

describe("report.warnings", function()
  it("names a dirty WoW-Pro checkout unless it isn't a git folder", function()
    local line = "The WoW-Pro checkout had uncommitted changes; this run may not be reproducible from its commit."
    assert.same({ line }, report.warnings({ addon = { dirty = true } }, {}))
    assert.same({}, report.warnings({ addon = { git = false, dirty = true } }, {}))
  end)

  it("names missing catalog sources in name order, without backticks", function()
    local w = report.warnings({ catalog = { questie = { present = false }, a = { present = false },
      b = { present = true } } }, {})
    assert.same({ "Catalog source a was missing.", "Catalog source questie was missing." }, w)
  end)

  it("warns when most counted findings are unverified", function()
    local fs = {
      { id = "F-1", signal = "accept-refused", severity = "high", confidence = "unverified" },
      { id = "F-2", signal = "accept-refused", severity = "high", confidence = "unverified" },
      { id = "F-3", signal = "accept-refused", severity = "high" },
      { id = "F-4", signal = "missing-global", severity = "low", confidence = "unverified" },
    }
    assert.same({ "2 of 3 findings rest on quest data not checked against a second source." },
      report.warnings({}, fs))
  end)

  it("warns about races that reached no included guide", function()
    assert.same({ "1 race reached no included guide and was skipped: Human." },
      report.warnings({ skipped_races = { "Human" } }, {}))
    assert.same({ "2 races reached no included guide and were skipped: Human, NightElf." },
      report.warnings({ skipped_races = { "Human", "NightElf" } }, {}))
    assert.same({}, report.warnings({ skipped_races = {} }, {}))
  end)

  it("adds a level-flag warning line", function()
    local h = { guides = { { gid = "G", flags = { { combo = "Dwarf WARRIOR none", rule = "enter-under" } } } } }
    assert.same({ "1 guide entered under-levelled" }, report.warnings(h, {}))
  end)

  it("counts guides, not flags, per rule, in rule order", function()
    local h = { guides = {
      { gid = "G1", flags = { { combo = "a", rule = "enter-under" }, { combo = "b", rule = "enter-under" },
        { combo = "a", rule = "leave-under" } } },
      { gid = "G2", flags = { { combo = "a", rule = "enter-under" }, { combo = "a", rule = "enter-over" } } },
      { gid = "G3", flags = {} },
    } }
    assert.same({ "2 guides entered under-levelled", "1 guide left under-levelled", "1 guide entered over-levelled" },
      report.warnings(h, {}))
  end)
end)

describe("report.guides", function()
  local A, B = "Dwarf WARRIOR none", "Gnome MAGE none"
  local function gl(gid, t)
    t.gid, t.file = gid, gid .. ".lua"
    if t.finished == nil then t.finished = true end
    return t
  end

  it("keeps a guide played by one of two combos, with only that combo's levels", function()
    local g = report.guides({
      { combo = A, guide_levels = { gl("G1", { start_level = 1, end_level = 6, enter = 1, leave = 6, last_line = 90 }) } },
      { combo = B, guide_levels = {} },
    })
    assert.equal(1, #g)
    assert.same({ file = "G1.lua", gid = "G1", last_line = 90, start_level = 1, end_level = 6,
      levels = { [A] = { enter = 1, leave = 6, finished = true } }, flags = {} }, g[1])
  end)

  it("keeps each combo's levels when two combos enter at different levels, and the highest last_line", function()
    local g = report.guides({
      { combo = A, guide_levels = { gl("G1", { start_level = 5, end_level = 10, enter = 5, leave = 10, last_line = 80 }) } },
      { combo = B, guide_levels = { gl("G1", { start_level = 5, end_level = 10, enter = 7, leave = 10, last_line = 95 }) } },
    })
    assert.equal(1, #g)
    assert.same({ enter = 5, leave = 10, finished = true }, g[1].levels[A])
    assert.same({ enter = 7, leave = 10, finished = true }, g[1].levels[B])
    assert.equal(95, g[1].last_line)
  end)

  it("fires each flag rule only when its condition holds", function()
    local function flags(t) return report.guides({ { combo = A, guide_levels = { gl("G", t) } } })[1].flags end
    assert.same({ { combo = A, rule = "enter-under" } }, flags({ start_level = 5, end_level = 10, enter = 4, leave = 10 }))
    assert.same({}, flags({ start_level = 5, end_level = 10, enter = 5, leave = 10 }))
    assert.same({ { combo = A, rule = "leave-under" } }, flags({ start_level = 5, end_level = 10, enter = 5, leave = 9 }))
    assert.same({ { combo = A, rule = "enter-over" } }, flags({ start_level = 5, end_level = 10, enter = 11, leave = 12 }))
    assert.same({}, flags({ start_level = 5, end_level = 10, enter = 10, leave = 10 }))
  end)

  it("suppresses leave-under when the guide wasn't finished", function()
    local g = report.guides({ { combo = A, guide_levels = {
      gl("G", { start_level = 5, end_level = 10, enter = 5, leave = 7, finished = false }) } } })
    assert.same({}, g[1].flags)
    assert.is_false(g[1].levels[A].finished)
  end)

  it("raises no flag and no error when the guide has no level range", function()
    local g = report.guides({ { combo = A, guide_levels = { gl("G", { enter = 3, leave = 4 }) } } })
    assert.is_nil(g[1].start_level)
    assert.is_nil(g[1].end_level)
    assert.same({}, g[1].flags)
  end)

  it("merges by first appearance, walking the entries in order, and sorts flags by combo then rule", function()
    local g = report.guides({
      { combo = B, guide_levels = { gl("G1", { start_level = 1, end_level = 5, enter = 1, leave = 5 }),
        gl("G3", { start_level = 10, end_level = 12, enter = 9, leave = 11 }) } },
      { combo = A, guide_levels = { gl("G1", { start_level = 1, end_level = 5, enter = 1, leave = 5 }),
        gl("G2", { start_level = 5, end_level = 10, enter = 5, leave = 10 }),
        gl("G3", { start_level = 10, end_level = 12, enter = 9, leave = 11 }) } },
    })
    local gids = {}
    for i, e in ipairs(g) do gids[i] = e.gid end
    assert.same({ "G1", "G3", "G2" }, gids)
    assert.same({ { combo = A, rule = "enter-under" }, { combo = A, rule = "leave-under" },
      { combo = B, rule = "enter-under" }, { combo = B, rule = "leave-under" } }, g[2].flags)
  end)

  it("sorts one combo's flags by rule name", function()
    local g = report.guides({ { combo = A, guide_levels = {
      gl("G", { start_level = 5, end_level = 10, enter = 11, leave = 9 }),
    } } })
    -- enter-over fires; leave-under fires (finished, 9 < 10): rule names sort enter-over first.
    assert.same({ { combo = A, rule = "enter-over" }, { combo = A, rule = "leave-under" } }, g[1].flags)
  end)

  it("encodes empty flags as an array", function()
    local g = report.guides({ { combo = A, guide_levels = { gl("G", { enter = 3, leave = 4 }) } } })
    assert.truthy(json.encode(g):find('"flags"%s*:%s*%[%s*%]'))
  end)
end)

describe("report.context", function()
  it("builds by_id and single", function()
    local fs = findings()
    local ctx = report.context(fs, header())
    for _, f in ipairs(fs) do assert.equal(f, ctx.by_id[f.id]) end
    assert.equal("Dwarf Warrior", ctx.single)
  end)

  it("single is nil for several or duplicated-to-many combos", function()
    local h = { matrix = { combos = { "Dwarf WARRIOR none", "Gnome MAGE none" } } }
    assert.is_nil(report.context({}, h).single)
    assert.is_nil(report.context({}, {}).single)
    local d = { matrix = { combos = { "Dwarf WARRIOR none", "Dwarf WARRIOR none" } } }
    assert.equal("Dwarf Warrior", report.context({}, d).single)
  end)
end)

describe("report.counted", function()
  it("counts a finding with a severity that is neither expected nor harness", function()
    assert.is_true(report.counted({ severity = "high", signal = "never-shown-accept" }))
    assert.is_false(report.counted({ signal = "never-shown-accept" }))
    assert.is_false(report.counted({ severity = "low", expected = true, signal = "x" }))
    assert.is_false(report.counted({ severity = "low", signal = "missing-global" }))
  end)
end)
