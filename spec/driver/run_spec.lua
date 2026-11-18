-- The driver loop (design spec §4.4) against a scripted fake engine: which
-- signals it records, when it right-clicks and when it stops.
local fx = dofile("spec/helpers/driver_fixtures.lua")
local run = require("hwc.driver.run")

local function drive(guides, script, opts, world)
  world = world or fx.fake_world()
  local E = fx.scripted_engine(guides, script, "G1", world)
  opts = opts or {}
  opts.perform = E.perform
  local log = run.drive({ engine = E, world = world, cfg = { race = "Dwarf", class = "WARRIOR" },
    errors = {}, missing_order = {}, addon = { path = "/x" } }, opts)
  return log, E
end

local function signals(log, name)
  local out = {}
  for _, s in ipairs(log.signals) do
    if s.signal == name then out[#out + 1] = s end
  end
  return out
end

local function kinds(log)
  local out = {}
  for _, s in ipairs(log.signals) do out[#out + 1] = s.signal end
  return out
end

-- A one-guide chain ending in a D step with no next guide.
local function one_guide(steps)
  steps[#steps + 1] = { action = "D", name = "Done" }
  return { G1 = { startlevel = 1, file = "g1.lua", steps = steps } }
end

local function completes(n)
  local s = {}
  for i = 1, n do s[i] = { complete = { i } } end
  return s
end

describe("driver.run", function()
  it("records no signal for a step that completes on its action", function()
    local log, E = drive(one_guide({ { action = "R", name = "Go" } }), { G1 = completes(1) })
    assert.same({ "manual-completion" }, kinds(log)) -- only the closing D
    assert.is_true(signals(log, "manual-completion")[1].expected)
    assert.equal("D", signals(log, "manual-completion")[1].action)
    assert.same({ "G1:2" }, E.manual)
    assert.equal("no-next-guide", log.stop.reason)
    assert.same({ "G1" }, log.guides)
    assert.equal(2, #log.steps)
    assert.equal("Go", log.steps[1].name)
    assert.equal("acted", log.steps[1].outcome.kind)
  end)

  -- Guide-filters final review 1: a git-less addon's identity (git = false and
  -- the TOC version) survives into the run log, which the report header reads.
  it("carries the addon's git flag and version into the log", function()
    local world = fx.fake_world()
    local guides = one_guide({ { action = "R", name = "Go" } })
    local E = fx.scripted_engine(guides, { G1 = completes(1) }, "G1", world)
    local log = run.drive({ engine = E, world = world, cfg = { race = "Dwarf", class = "WARRIOR" },
      errors = {}, missing_order = {}, addon = { path = "/x", git = false, version = "x" } },
      { perform = E.perform })
    assert.is_false(log.addon.git)
    assert.equal("x", log.addon.version)
    assert.equal("/x", log.addon.path)
  end)

  -- Final review minor 2: spec §5.2 "logged as an abstracted-turnin event".
  it("copies an abstracted turn-in into the snapshot outcome", function()
    local log = drive(one_guide({ { action = "A", name = "Camping 101: Cooking", qids = { 96629 },
      outcome = { kind = "acted", abstracted_turnin = 96629 } } }), { G1 = completes(1) })
    assert.equal(96629, log.steps[1].outcome.abstracted_turnin)
  end)

  it("records an expected manual-completion for an N step", function()
    local log = drive(one_guide({ { action = "N", name = "Read this", outcome = { kind = "noop" } } }), {})
    local m = signals(log, "manual-completion")
    assert.equal(2, #m)
    assert.equal("N", m[1].action)
    assert.is_true(m[1].expected)
    assert.same({}, signals(log, "did-not-advance"))
  end)

  it("records did-not-advance for a C that does not complete and right-clicks it once", function()
    local log, E = drive(one_guide({ { action = "C", name = "Kill", qids = { 7 },
      outcome = { kind = "refused", reason = "incomplete" } } }), {})
    local d = signals(log, "did-not-advance")
    assert.equal(1, #d)
    assert.equal("incomplete", d[1].reason)
    assert.equal(7, d[1].qid)
    assert.equal(101, d[1].line)
    assert.equal("g1.lua", d[1].file)
    assert.equal("Done", d[1].after.name)
    -- one click, one signal: the C's click is the did-not-advance, not also a manual-completion
    local m = signals(log, "manual-completion")
    assert.equal(1, #m)
    assert.equal("D", m[1].action)
    assert.same({ "G1:1", "G1:2" }, E.manual)
  end)

  it("counts a step as advanced when its action also completes a sticky row (Review Focus 2)", function()
    local steps = {
      { action = "R", name = "a" },
      { action = "C", name = "sticky", sticky = true },
      { action = "R", name = "b" },
      { action = "T", name = "turn" },
    }
    local log, E = drive(one_guide(steps), { G1 = { { complete = { 1 } }, nil, { complete = { 3 } },
      { complete = { 4, 2 } } } })
    assert.same({}, signals(log, "did-not-advance"))
    assert.same({ "G1:5" }, E.manual)
    assert.same({ "G1:1", "G1:3", "G1:4", "G1:5" }, E.acted)
  end)

  it("performs a shown sticky objective row once, without right-clicking it", function()
    local steps = {
      { action = "C", name = "Kill boars", qids = { 183 }, sticky = true },
      { action = "R", name = "walk" },
      { action = "T", name = "The Boar Hunter", qids = { 183 } },
    }
    -- the sticky's objectives are not complete until the player does them;
    -- the turn-in only completes once they are (the sticky row completes with them)
    local script = { G1 = { { complete = { 1 } }, { complete = { 2 } }, { complete = { 3 } } } }
    local log, E = drive(one_guide(steps), script)
    assert.same({ "G1:1", "G1:2", "G1:3", "G1:4" }, E.acted)
    assert.same({ "G1:4" }, E.manual)
    assert.same({}, signals(log, "did-not-advance"))
    assert.is_true(log.steps[1].sticky)
  end)

  it("performs a sticky row at most once even when it stays shown", function()
    local steps = {
      { action = "C", name = "Kill boars", qids = { 183 }, sticky = true },
      { action = "R", name = "walk" },
      { action = "R", name = "walk more" },
    }
    local log, E = drive(one_guide(steps), { G1 = { nil, { complete = { 2 } }, { complete = { 3 } } } })
    assert.same({ "G1:1", "G1:2", "G1:3", "G1:4" }, E.acted)
    assert.same({}, signals(log, "did-not-advance"))
  end)

  it("fires stuck after the limit when a step comes back after every right-click (Review Focus 3)", function()
    local steps = {}
    for i = 1, 4 do steps[i] = { action = "R", name = "r" .. i } end
    steps[5] = { action = "C", name = "Loot", qids = { 9 } }
    local script = completes(4)
    script[5] = { on_manual = { uncomplete = { 5 } } }
    local log, E = drive(one_guide(steps), { G1 = script })
    assert.equal("stuck", log.stop.reason)
    assert.equal(5, #signals(log, "did-not-advance"))
    local stuck = signals(log, "stuck")
    assert.equal(1, #stuck)
    assert.equal("Loot", stuck[1].name)
    local n5 = 0
    for _, a in ipairs(E.acted) do if a == "G1:5" then n5 = n5 + 1 end end
    assert.equal(5, n5)
  end)

  it("closes G1 when its last action switches the guide inside the settle (Review Focus 1)", function()
    local world = fx.fake_world({}, { 77 })
    local guides = {
      G1 = { startlevel = 1, next_gid = "G2", file = "g1.lua", steps = {
        { action = "R", name = "a" },
        { action = "A", name = "Hidden", qids = { 55 }, why = "PRE not met", hidden = true },
        { action = "T", name = "last" },
      } },
      G2 = { startlevel = 5, file = "g2.lua", steps = {
        { action = "R", name = "g2 first" },
        { action = "D", name = "Done" },
      } },
    }
    local script = { G1 = { { complete = { 1 } }, nil, { complete = { 3 }, done = true, switch = "G2" } },
      G2 = completes(1) }
    local log, E = drive(guides, script, {}, world)
    assert.same({ "G1", "G2" }, log.guides)
    local hidden = signals(log, "never-shown-accept")
    assert.equal(1, #hidden)
    assert.equal("G1", hidden[1].gid)
    assert.equal("Hidden", hidden[1].name)
    assert.equal("PRE not met", hidden[1].why)
    assert.equal("g1.lua", hidden[1].file)
    -- 77 has no turn-in step in any guide played: carried past the run, not a signal
    assert.same({}, signals(log, "leftover-quests"))
    assert.same({ { qid = 77 } }, log.carried)
    assert.same({ "G1:1", "G1:3", "G2:1", "G2:2" }, E.acted)
    assert.equal("no-next-guide", log.stop.reason)
  end)

  -- A quest in the log is a finding only once, at the end of the run, and only when the
  -- run reached a turn-in step for it. Carrying a quest into the next guide is normal;
  -- one with no turn-in in the guides played is carried past the run (RunLog.carried).
  it("records one leftover-quests at the reached turn-in step, not one per guide", function()
    local world = fx.fake_world({ [77] = { name = "Wolves" } }, { 77 })
    local guides = {
      G1 = { startlevel = 1, next_gid = "G2", file = "g1.lua", steps = {
        { action = "T", name = "Wolves", qids = { 77 } },
        { action = "R", name = "a" },
      } },
      G2 = { startlevel = 5, file = "g2.lua", steps = { { action = "R", name = "b" } } },
    }
    local script = { G1 = { nil, { complete = { 2 }, done = true, switch = "G2" } }, G2 = completes(1) }
    local log = drive(guides, script, {}, world)
    local left = signals(log, "leftover-quests")
    assert.equal(1, #left)
    assert.same({ "G1", "g1.lua", 101, "T", "Wolves", 77, "Wolves" },
      { left[1].gid, left[1].file, left[1].line, left[1].action, left[1].name, left[1].qid, left[1].qname })
    assert.is_nil(left[1].before)
    assert.is_nil(left[1].after)
    assert.same({}, log.carried)
  end)

  it("carries a quest whose turn-in step the run never reached", function()
    local world = fx.fake_world({ [77] = { name = "Wolves" } }, { 77 })
    local guides = {
      G1 = { startlevel = 1, next_gid = "G2", file = "g1.lua", steps = { { action = "R", name = "a" } } },
      G2 = { startlevel = 25, file = "g2.lua", steps = { { action = "T", name = "Wolves", qids = { 77 } } } },
    }
    local log = drive(guides, { G1 = { { complete = { 1 }, done = true, switch = "G2" } } }, { max_guides = 2 }, world)
    assert.equal("max-guides", log.stop.reason)
    assert.same({}, signals(log, "leftover-quests"))
    assert.same({ { qid = 77, qname = "Wolves" } }, log.carried)
  end)

  -- A quest accepted in an earlier guide that no guide played turns in is a finding:
  -- only the guide the run stopped in can still turn its quests in after the run.
  it("flags a quest accepted in an earlier guide with no turn-in in scope", function()
    local world = fx.fake_world({ [77] = { name = "Wolves" }, [88] = { name = "Bears" } }, { 77, 88 })
    local guides = {
      G1 = { startlevel = 1, next_gid = "G2", file = "g1.lua", steps = {
        { action = "A", name = "Wolves", qids = { 77 } },
        { action = "R", name = "a" },
      } },
      G2 = { startlevel = 5, file = "g2.lua", steps = {
        { action = "A", name = "Bears", qids = { 88 } },
        { action = "R", name = "b" },
      } },
    }
    local script = { G1 = { { complete = { 1 } }, { complete = { 2 }, done = true, switch = "G2" } },
      G2 = completes(2) }
    local log = drive(guides, script, {}, world)
    local left = signals(log, "leftover-quests")
    assert.equal(1, #left)
    assert.same({ "G1", "g1.lua", 101, "A", 77, "not-turned-in" },
      { left[1].gid, left[1].file, left[1].line, left[1].action, left[1].qid, left[1].reason })
    assert.same({ { qid = 88, qname = "Bears" } }, log.carried) -- G2 is where the run stopped
  end)

  -- 01_12_Dun_Morogh.lua:273: Forever quest 95213 has no catalog entry, so its
  -- leftover-quests finding read "Quest 95213 is left in the log" with no name.
  it("names a quest the catalog lacks from the guide's own A step for it", function()
    local world = fx.fake_world({ [96] = { name = "Catalog Name" } }, { 95213, 96 })
    local steps = {
      { action = "A", name = "Stolen Blasting Powder", qids = { 95213 } },
      { action = "T", name = "Stolen Blasting Powder", qids = { 95213 } },
      { action = "T", name = "Guide Name", qids = { 96 } },
    }
    local log = drive(one_guide(steps), { G1 = completes(1) }, {}, world)
    local names = {}
    for _, l in ipairs(signals(log, "leftover-quests")) do names[l.qid] = l.qname end
    assert.equal("Stolen Blasting Powder", names[95213])
    assert.equal("Catalog Name", names[96]) -- the catalog wins when it has a name
  end)

  -- Ruling X: an accept the engine skipped because its quest is already done
  -- (WoWPro_Broker.lua:2042, "NextStep(): QID is complete: " .. QID) is not a hidden accept.
  it("records no never-shown-accept for an A step skipped as 'QID is complete', but does for a PRE why", function()
    local guides = {
      G1 = { startlevel = 1, file = "g1.lua", steps = {
        { action = "R", name = "a" },
        { action = "A", name = "Done Before", qids = { 55 }, why = "NextStep(): QID is complete: 55", hidden = true },
        { action = "A", name = "Gated", qids = { 56 },
          why = "NextStep:PRE&(55): A mandatory prereq was not met: 55", hidden = true },
        { action = "D", name = "Done" },
      } },
    }
    local script = { G1 = { { complete = { 1 } }, nil, nil, { complete = { 4 }, done = true } } }
    local log = drive(guides, script, {})
    local hidden = signals(log, "never-shown-accept")
    assert.equal(1, #hidden)
    assert.equal("Gated", hidden[1].name)
  end)

  -- An accept whose quest entered the log or the history anyway hid nothing; an accept
  -- gated by a P| profession the character doesn't know is hidden by design (spec §3:
  -- only a gated accept withheld from a character WITH the skill is a finding).
  it("records no never-shown-accept for a quest that was taken anyway or a profession the character lacks", function()
    local world = fx.fake_world({}, { 57 })
    world.log.history[58] = true
    world.player.skills["Fishing"] = { rank = 1, max = 75 }
    local guides = {
      G1 = { startlevel = 1, file = "g1.lua", steps = {
        { action = "R", name = "a" },
        { action = "A", name = "In Log", qids = { 57 }, why = "Quest in QuestLog", hidden = true },
        { action = "A", name = "Turned In", qids = { 58 }, why = "AutoCompleteQuestUpdate: AutoComplete", hidden = true },
        { action = "A", name = "Camping 101: First Aid", qids = { 59 }, why = "NextStep(): SkippedStep.", hidden = true,
          tags = { prof = "First Aid;129" } },
        { action = "A", name = "Camping 101: Fishing", qids = { 60 }, why = "NextStep(): SkippedStep.", hidden = true,
          tags = { prof = "Fishing;356" } },
        -- Skill level 0: the engine shows it without the profession (WoWPro_Broker.lua:2783-2787),
        -- so hiding it for another reason is still a finding.
        { action = "A", name = "Level Zero Cooking", qids = { 61 }, why = "NextStep:PRE&(9): A mandatory prereq was not met: 9",
          hidden = true, tags = { prof = "Cooking;185;0;0" } },
        { action = "D", name = "Done" },
      } },
    }
    local script = { G1 = { { complete = { 1 } }, nil, nil, nil, nil, nil, { complete = { 7 }, done = true } } }
    local log = drive(guides, script, {}, world)
    local hidden = signals(log, "never-shown-accept")
    assert.equal(2, #hidden)
    assert.equal("Camping 101: Fishing", hidden[1].name)
    assert.equal("Level Zero Cooking", hidden[2].name)
  end)

  it("closes G1 when the right-click on its D step loads G2 (Review Focus 1, manual path)", function()
    local world = fx.fake_world({}, { 77 })
    local guides = {
      G1 = { startlevel = 1, next_gid = "G2", file = "g1.lua", steps = {
        { action = "R", name = "a" },
        { action = "A", name = "Hidden", qids = { 55 }, why = "PRE not met", hidden = true },
        { action = "D", name = "Onwards" },
      } },
      G2 = { startlevel = 5, file = "g2.lua", steps = {
        { action = "R", name = "g2 first" },
        { action = "D", name = "Done" },
      } },
    }
    local script = { G1 = { { complete = { 1 } }, nil, { on_manual = { switch = "G2" } } }, G2 = completes(1) }
    local log, E = drive(guides, script, {}, world)
    assert.same({ "G1", "G2" }, log.guides)
    assert.same({ "G1:1", "G1:3", "G2:1", "G2:2" }, E.acted)
    assert.same({ "G1:3", "G2:2" }, E.manual)
    local hidden = signals(log, "never-shown-accept")
    assert.equal(1, #hidden)
    assert.equal("Hidden", hidden[1].name)
    assert.same({}, signals(log, "leftover-quests"))
    assert.same({ { qid = 77 } }, log.carried)
    assert.equal("Onwards", signals(log, "manual-completion")[1].name)
  end)

  -- WoWPro's "Skip Dungeon Quests" (WoWProCharDB.EnableDungeons, on by default) completes
  -- DUNGEON accepts unshown (WoWPro_Broker.lua:2589). This client doesn't run dungeons, so
  -- that's expected: the RunLog records the setting and the skipped accepts, not signals.
  it("records an engine-completed unshown DUNGEON accept as a dungeon skip, not a signal", function()
    local steps = {
      { action = "R", name = "a" },
      { action = "A", name = "Deadmines", qids = { 3 }, tags = { dungeon = "1581" }, hidden = true },
    }
    local log = drive(one_guide(steps), { G1 = { { complete = { 1, 2 } } } })
    assert.same({}, signals(log, "never-shown-accept"))
    assert.is_true(log.skip_dungeons)
    assert.same({ { gid = "G1", file = "g1.lua", line = 102, qid = 3, name = "Deadmines" } }, log.dungeon_skips)
  end)

  it("still flags a hidden DUNGEON accept the engine did not complete", function()
    local steps = {
      { action = "R", name = "a" },
      { action = "A", name = "Deadmines", qids = { 3 }, tags = { dungeon = "1581" }, hidden = true },
    }
    local log = drive(one_guide(steps), { G1 = { { complete = { 1 } } } })
    assert.equal(1, #signals(log, "never-shown-accept"))
    assert.same({}, log.dungeon_skips)
  end)

  it("stops with max-guides once that many guides have loaded", function()
    local guides = {
      G1 = { startlevel = 1, next_gid = "G2", steps = { { action = "R", name = "a" } } },
      G2 = { startlevel = 5, steps = { { action = "R", name = "b" } } },
    }
    local log = drive(guides, { G1 = { { complete = { 1 }, done = true, switch = "G2" } } }, { max_guides = 2 })
    assert.equal("max-guides", log.stop.reason)
    assert.same({ "G1", "G2" }, log.guides)
  end)

  -- Forever 30_41 -> Dungeon_Uld -> 30_41 ...: Uld has no next guide, so the addon pops
  -- back to 30_41, which comes back on the same final step that sent the run away. A
  -- player stops there; the driver must too, instead of clicking it until max-iterations.
  it("stops with guide-cycle when a guide comes back on the step that left it", function()
    local guides = {
      G1 = { startlevel = 1, next_gid = "G2", file = "g1.lua", steps = {
        { action = "R", name = "a" }, { action = "R", name = "Onwards" } } },
      G2 = { startlevel = 5, file = "g2.lua", steps = { { action = "R", name = "Onwards" } } },
    }
    local script = { G1 = { { complete = { 1 } }, { switch = "G2" } }, G2 = { { switch = "G1" } } }
    local log = drive(guides, script, { max_iterations = 200 })
    assert.equal("guide-cycle", log.stop.reason)
    assert.same({ "G1", "G2" }, log.guides)
    local stuck = signals(log, "stuck")
    assert.equal(1, #stuck)
    assert.equal("guide-cycle", stuck[1].reason)
    assert.equal("G1", stuck[1].gid)
    assert.equal("Onwards", stuck[1].name)
  end)

  it("keeps playing a guide the engine returns to further along", function()
    local guides = {
      G1 = { startlevel = 1, file = "g1.lua", steps = {
        { action = "R", name = "a" }, { action = "R", name = "jump" }, { action = "R", name = "after" } } },
      G2 = { startlevel = 5, file = "g2.lua", steps = { { action = "R", name = "x" } } },
    }
    local script = {
      G1 = { { complete = { 1 } }, { complete = { 2 }, switch = "G2" }, { complete = { 3 }, done = true } },
      G2 = { { complete = { 1 }, switch = "G1" } },
    }
    local log = drive(guides, script, { max_iterations = 200 })
    assert.equal("no-next-guide", log.stop.reason)
    assert.same({ "G1", "G2", "G1" }, log.guides)
    assert.same({}, signals(log, "stuck"))
  end)

  it("turns refusals into log-full, accept-refused, orphan-turnin and below-level", function()
    local steps = {
      { action = "A", name = "Full", qids = { 1 }, outcome = { kind = "refused", reason = "log-full" } },
      { action = "A", name = "Class", qids = { 2 }, outcome = { kind = "refused", reason = "class" } },
      { action = "T", name = "Orphan", qids = { 3, 4 }, outcome = { kind = "refused", reason = "not-in-log" } },
      { action = "A", name = "Low", qids = { 5 }, outcome = { kind = "acted", grind = { kills = 9, to = 4 } } },
    }
    local script = { G1 = { nil, nil, nil, { complete = { 4 } } } }
    local log, E = drive(one_guide(steps), script, {}, fx.fake_world({ [5] = { name = "Low Quest" } }))
    assert.equal(1, #signals(log, "log-full"))
    local ar = signals(log, "accept-refused")
    assert.equal(1, #ar)
    assert.equal("class", ar[1].reason)
    local o = signals(log, "orphan-turnin")
    assert.equal(2, #o)
    assert.same({ 3, 4 }, { o[1].qid, o[2].qid })
    local b = signals(log, "below-level")
    assert.equal(1, #b)
    assert.equal(5, b[1].qid)
    assert.equal("Orphan", b[1].before.name)
    assert.equal("T", b[1].before.action)
    assert.equal("Low Quest", b[1].qname)
    assert.same({ kills = 9, to = 4 }, b[1].grind)
    -- One click, one finding: a refused step's own signal already says why it didn't
    -- advance, so the client clicks it off without a did-not-advance as well.
    assert.same({}, signals(log, "did-not-advance"))
    assert.same({ "G1:1", "G1:2", "G1:3", "G1:5" }, E.manual)
  end)

  it("flags a shown step whose quest the catalog keeps from this race or class, once", function()
    local world = fx.fake_world({ [8] = { races = { "Human" }, confidence = "unverified" } })
    local steps = { { action = "C", name = "Human only", qids = { 8 } } }
    local log = drive(one_guide(steps), {}, {}, world)
    local w = signals(log, "wrong-race-class")
    assert.equal(1, #w)
    assert.equal("race", w[1].reason)
    assert.equal("unverified", w[1].confidence)
  end)

  it("flags wrong-race-class only when every listed QID excludes the character (Ruling P)", function()
    local world = fx.fake_world({ [8] = { races = { "Human" } }, [9] = {}, [10] = { classes = { "MAGE" } } })
    local steps = {
      { action = "A", name = "Variants", qids = { 8, 9 } },
      { action = "A", name = "None for me", qids = { 8, 10 } },
    }
    local log = drive(one_guide(steps), {}, {}, world)
    local w = signals(log, "wrong-race-class")
    assert.equal(1, #w)
    assert.equal("None for me", w[1].name)
    assert.equal(8, w[1].qid)
    assert.equal("race", w[1].reason)
  end)

  it("does not flag a non-quest step that borrows a race/class quest's QID", function()
    -- 01_12_Dun_Morogh.lua:301-302: `f Thelsamar` and `h Stoutlager Inn` carry the
    -- Shaman-only QID 94466. On a non-quest step the QID only skips the step once that
    -- quest is complete (WoWPro_Broker.lua:2037); it gates nothing by race or class.
    local world = fx.fake_world({ [8] = { classes = { "SHAMAN" } } })
    local steps = {
      { action = "f", name = "Thelsamar", qids = { 8 } },
      { action = "h", name = "Stoutlager Inn", qids = { 8 } },
      { action = "R", name = "Run", qids = { 8 } },
    }
    local log = drive(one_guide(steps), {}, {}, world)
    assert.same({}, signals(log, "wrong-race-class"))
  end)

  it("reads why from the acted step's guide when a signal follows a guide switch", function()
    local guides = {
      G1 = { startlevel = 1, next_gid = "G2", steps = {
        { action = "A", name = "Full", qids = { 1 }, why = "g1 why", outcome = { kind = "refused", reason = "log-full" } },
      } },
      G2 = { startlevel = 5, steps = { { action = "R", name = "b", why = "g2 why" } } },
    }
    local log = drive(guides, { G1 = { { switch = "G2" } } }, { max_guides = 2 })
    local f = signals(log, "log-full")[1]
    assert.equal("G1", f.gid)
    assert.equal("g1 why", f.why)
  end)

  it("records the right-click error as the manual-completion reason", function()
    local world = fx.fake_world()
    local E = fx.scripted_engine(one_guide({ { action = "N", name = "note", outcome = { kind = "noop" } } }), {}, "G1", world)
    local real = E.complete_manual
    function E:complete_manual(i)
      real(self, i)
      if i == 1 then return false, "Broker.lua:1: boom" end
      return true
    end
    local log = run.drive({ engine = E, world = world, cfg = {}, errors = {}, missing_order = {} }, { perform = E.perform })
    assert.equal("Broker.lua:1: boom", signals(log, "manual-completion")[1].reason)
  end)

  it("records the right-click error as the did-not-advance reason for an unexpected click", function()
    local world = fx.fake_world()
    local E = fx.scripted_engine(one_guide({ { action = "C", name = "Kill", qids = { 7 },
      outcome = { kind = "refused", reason = "incomplete" } } }), {}, "G1", world)
    local real = E.complete_manual
    function E:complete_manual(i)
      real(self, i)
      if i == 1 then return false, "Broker.lua:1: boom" end
      return true
    end
    local ctx = { engine = E, world = world, cfg = {}, errors = {}, missing_order = {} }
    local log = run.drive(ctx, { perform = E.perform })
    assert.equal("Broker.lua:1: boom", signals(log, "did-not-advance")[1].reason)
    assert.equal("D", signals(log, "manual-completion")[1].action)
    assert.equal(1, #signals(log, "manual-completion"))
  end)

  it("records stuck with settle-limit when a settle hits its limit", function()
    local log = drive(one_guide({ { action = "R", name = "a" } }), { G1 = { { complete = { 1 }, hit_limit = true } } })
    local s = signals(log, "stuck")
    assert.equal(1, #s)
    assert.equal("settle-limit", s[1].reason)
  end)

  it("stops with iterations past max_iterations", function()
    local steps = { { action = "C", name = "loop", qids = { 1 } } }
    local log = drive(one_guide(steps), { G1 = { { on_manual = { uncomplete = { 1 } } } } },
      { max_iterations = 3, stuck_limit = 100 })
    assert.equal("iterations", log.stop.reason)
    assert.equal(1, #signals(log, "stuck"))
  end)

  it("stops with no-step when nothing is current and the guide is not done", function()
    local steps = { { action = "R", name = "a" }, { action = "R", name = "s", sticky = true } }
    local guides = { G1 = { startlevel = 1, steps = steps } }
    local log = drive(guides, { G1 = { { complete = { 1 } } } })
    assert.equal("no-step", log.stop.reason)
    assert.equal(1, #signals(log, "stuck"))
  end)

  it("stops with no-step and a stuck reason when the engine read fails", function()
    local world = fx.fake_world()
    local E = fx.scripted_engine(one_guide({ { action = "R", name = "a" } }), {}, "G1", world)
    function E:current() return nil, "boom" end
    local log = run.drive({ engine = E, world = world, cfg = {}, errors = {}, missing_order = {} },
      { perform = E.perform })
    assert.equal("no-step", log.stop.reason)
    assert.equal("boom", signals(log, "stuck")[1].reason)
    assert.is_nil(E.acted)
  end)

  it("turns addon errors, harness errors and missing globals into signals at the end", function()
    local world = fx.fake_world()
    local E = fx.scripted_engine(one_guide({}), {}, "G1", world)
    local errors = {
      { msg = "WoWPro_Broker.lua:10: attempt to index nil", stack = "stack traceback:\n\tWoWPro_Broker.lua:10: in f\n\tx" },
      { msg = "src/hwc/stubs/core.lua:5: bad", stack = "" },
    }
    local log = run.drive({ engine = E, world = world, cfg = {}, errors = errors, missing_order = { "Foo", "Foo", "Bar" } },
      { perform = E.perform })
    local l = signals(log, "lua-error")
    assert.equal(2, #l)
    assert.equal("WoWPro_Broker.lua:10: attempt to index nil", l[1].message)
    assert.equal("WoWPro_Broker.lua:10: in f", l[1].stack)
    assert.is_nil(l[1].reason)
    assert.equal("harness", l[2].reason)
    local m = signals(log, "missing-global")
    assert.same({ "Foo", "Bar" }, { m[1].global, m[2].global })
  end)

  it("stops with errors past max_addon_errors", function()
    local world = fx.fake_world()
    local steps = { { action = "R", name = "a" }, { action = "R", name = "b" } }
    local E = fx.scripted_engine(one_guide(steps), { G1 = completes(2) }, "G1", world)
    local errors = {}
    local perform = E.perform
    local function noisy(ctx, step)
      errors[#errors + 1] = { msg = "WoWPro.lua:1: x", stack = "" }
      errors[#errors + 1] = { msg = "WoWPro.lua:1: y", stack = "" }
      return perform(ctx, step)
    end
    local log = run.drive({ engine = E, world = world, cfg = {}, errors = errors, missing_order = {} },
      { perform = noisy, max_addon_errors = 1 })
    assert.equal("errors", log.stop.reason)
    assert.same({ "G1:1" }, E.acted)
  end)

  it("builds the run log from ordered data only", function()
    local log = drive(one_guide({ { action = "R", name = "Go" } }), { G1 = completes(1) })
    assert.same({ race = "Dwarf", class = "WARRIOR", professions = {} }, log.character)
    assert.equal(2, log.rank)
    local s = log.steps[1]
    assert.same({ 1, 2 }, s.rows)
    assert.same({}, s.log)
    assert.equal(1, s.n)
    assert.equal("G1", s.gid)
    local a = require("hwc.json").encode(log)
    local b = require("hwc.json").encode(drive(one_guide({ { action = "R", name = "Go" } }), { G1 = completes(1) }))
    assert.equal(a, b)
  end)

  it("lists the stop reasons", function()
    for _, r in ipairs({ "no-next-guide", "stuck", "iterations", "errors", "no-step", "max-guides", "guide-cycle" }) do
      assert.is_true(run.STOP[r], r)
    end
    assert.is_nil(run.STOP.level)
    assert.is_nil(run.STOP["chain-range"])
    assert.is_nil(run.DEFAULTS.stop_level)
    assert.is_nil(run.CHAIN_MAX_START)
  end)

  -- Guide filters: the driver plays the chain to its last line and jumps over the
  -- guides the include/exclude filters left out, with the guide-list click (LoadGuide).
  describe("guide filters", function()
    local function set(...)
      local out = {}
      for _, g in ipairs({ ... }) do out[g] = true end
      return out
    end

    -- G1 (1) -> G2 (5) -> G3 (10); G1 completes and the engine switches to G2.
    local function chain()
      return {
        G1 = { startlevel = 1, next_gid = "G2", file = "g1.lua", steps = { { action = "R", name = "a" } } },
        G2 = { startlevel = 5, next_gid = "G3", file = "g2.lua", steps = { { action = "R", name = "b" } } },
        G3 = { startlevel = 10, file = "g3.lua", steps = {
          { action = "R", name = "c" }, { action = "D", name = "Done" },
        } },
      }
    end
    local SCRIPT = {
      G1 = { { complete = { 1 }, done = true, switch = "G2" } },
      G2 = { { complete = { 1 }, done = true, switch = "G3" } },
      G3 = completes(1),
    }

    it("an excluded guide is jumped to the next included one on the chain", function()
      local log, E = drive(chain(), SCRIPT, { included = set("G1", "G3") })
      assert.same({ "G1", "G3" }, log.guides)
      assert.same({ "G3" }, E.loaded)
      assert.equal(1, #log.jumps)
      local j = log.jumps[1]
      assert.equal("G2", j.from)
      assert.same({ "G2" }, j.passed)
      assert.equal("G3", j.to)
      assert.equal(1, j.level_before)
      assert.equal(10, j.level_after)
      for _, s in ipairs(log.steps) do assert.not_equal("G2", s.gid) end
      assert.same({ "G1:1", "G3:1", "G3:2" }, E.acted)
      assert.equal("no-next-guide", log.stop.reason)
    end)

    it("the start guide excluded jumps before playing", function()
      local log, E = drive(chain(), SCRIPT, { included = set("G2") })
      assert.same({ "G2" }, log.guides)
      assert.equal("G1", log.jumps[1].from)
      assert.same({ "G1" }, log.jumps[1].passed)
      assert.equal("G2", log.jumps[1].to)
      assert.equal(5, log.jumps[1].level_after)
      assert.same({ "G2" }, E.loaded)
      assert.equal("G2:1", E.acted[1])
    end)

    it("excluded guides to the end of the chain stop with no-next-guide", function()
      local log, E = drive(chain(), SCRIPT, { included = set("G1") })
      assert.equal("no-next-guide", log.stop.reason)
      assert.same({ "G1" }, log.guides)
      assert.same({ "G2", "G3" }, log.jumps[1].passed)
      assert.is_nil(log.jumps[1].to)
      assert.equal(1, log.jumps[1].level_after)
      assert.same({}, E.loaded)
    end)

    it("treats a cycle in the chain as its end", function()
      local guides = chain()
      guides.G3.next_gid = "G2"
      local log = drive(guides, SCRIPT, { included = set("G1") })
      assert.equal("no-next-guide", log.stop.reason)
      assert.same({ "G2", "G3" }, log.jumps[1].passed)
      assert.is_nil(log.jumps[1].to)
    end)

    it("the level is never lowered", function()
      local world = fx.fake_world()
      world.player.level = 12
      local log = drive(chain(), SCRIPT, { included = set("G1", "G3") }, world)
      assert.equal(12, log.jumps[1].level_before)
      assert.equal(12, log.jumps[1].level_after)
    end)

    it("raises the level with the XP table, recording it as XP", function()
      local world = fx.fake_world()
      local log = drive(chain(), SCRIPT, { included = set("G1", "G3") }, world)
      assert.equal(10, world.player.level)
      local xp = require("hwc.world.xp")
      local total = 0
      for l = 1, 9 do total = total + xp.to_next(l) end
      local recorded = 0
      for _, r in ipairs(world.xp_records) do recorded = recorded + r.n end
      assert.equal(total, recorded)
      assert.equal(10, log.jumps[1].level_after)
    end)

    it("stops the raise at the XP cap", function()
      local guides = chain()
      guides.G3.startlevel = 40
      local log = drive(guides, SCRIPT, { included = set("G1", "G3") })
      assert.equal(require("hwc.world.xp").CAP_LEVEL, log.jumps[1].level_after)
    end)

    it("stops with load-guide-failed when the engine does not load the guide", function()
      local guides = chain()
      local world = fx.fake_world()
      local E = fx.scripted_engine(guides, SCRIPT, "G1", world)
      function E:load_guide(gid) self.loaded[#self.loaded + 1] = gid; return false, "boom" end
      local log = run.drive({ engine = E, world = world, cfg = {}, errors = {}, missing_order = {} },
        { perform = E.perform, included = set("G1", "G3") })
      assert.equal("no-step", log.stop.reason)
      local stuck = signals(log, "stuck")
      assert.equal(1, #stuck)
      assert.equal("load-guide-failed", stuck[1].reason)
      assert.same({ "G1" }, log.guides)
    end)

    it("plays every guide with no included set", function()
      local log, E = drive(chain(), SCRIPT)
      assert.same({ "G1", "G2", "G3" }, log.guides)
      assert.same({}, log.jumps)
      assert.same({}, E.loaded)
    end)

    it("a run past level 25 keeps playing", function()
      local steps = { { action = "R", name = "a" }, { action = "R", name = "b" } }
      local log, E = drive(one_guide(steps), { G1 = { { complete = { 1 }, level = 30 }, { complete = { 2 } } } })
      assert.equal("no-next-guide", log.stop.reason)
      assert.equal(30, log.stop.level)
      assert.same({ "G1:1", "G1:2", "G1:3" }, E.acted)
    end)
  end)
end)
