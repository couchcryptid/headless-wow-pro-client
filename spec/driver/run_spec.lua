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

  it("attaches the chain part to a signal, and names the prerequisite a hidden accept waits on", function()
    local world = fx.fake_world({
      [1030] = { name = "Raene's Cleansing", chain = { 9, 11 } },
      [1029] = { name = "Raene's Cleansing", chain = { 8, 11 } },
    })
    local guides = {
      G1 = { startlevel = 1, file = "g1.lua", steps = {
        { action = "R", name = "a" },
        { action = "A", name = "Raene's Cleansing", qids = { 1030 },
          why = "NextStep:PRE&(1029): A mandatory prereq was not met: 1029", hidden = true },
        { action = "D", name = "Done" },
      } },
    }
    local log = drive(guides, { G1 = { { complete = { 1 } }, nil, { complete = { 3 }, done = true } } }, {}, world)
    local hidden = signals(log, "never-shown-accept")
    assert.equal(1, #hidden)
    assert.same({ part = 9, total = 11 }, hidden[1].chain)
    assert.equal("Raene's Cleansing", hidden[1].pre_qname)
    assert.same({ part = 8, total = 11 }, hidden[1].pre_chain)
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

  -- WoWPro hides a non-optional U step with an L tag until every L item is in bags
  -- (WoWPro_Broker.lua:2182, why "You don't have the required items for this step.").
  local HIDDEN_USE = "You don't have the required items for this step."
  local function use_step(extra)
    local s = { action = "U", name = "Scroll", qids = { 1016 }, hidden = true, why = HIDDEN_USE,
      tags = { use = "5456", lootitem = { [5455] = 1 } } }
    for k, v in pairs(extra or {}) do s[k] = v end
    return s
  end

  it("records hidden-use-step for a U step hidden until its L items are in bags", function()
    local steps = {
      { action = "A", name = "Q", qids = { 1016 } },
      { action = "l", name = "Q", qids = { 1016 } },
      use_step(),
      { action = "T", name = "Q", qids = { 1016 } },
      { action = "D", name = "Done" },
    }
    local log = drive(one_guide(steps), { G1 = { { complete = { 1, 2, 4, 5 }, done = true } } })
    local hits = signals(log, "hidden-use-step")
    assert.equal(1, #hits)
    assert.equal(103, hits[1].line)
    assert.equal("5456", hits[1].use)
    assert.same({ [5455] = 1 }, hits[1].loot)
    assert.equal(1016, hits[1].qid)
    assert.equal("l", hits[1].before.action)
    assert.equal("T", hits[1].after.action)
  end)

  it("records no hidden-use-step without an L tag, for an optional step, or for another why", function()
    local steps = {
      { action = "R", name = "a" },
      use_step({ tags = { use = "5456" } }),
      use_step({ tags = { use = "5456", lootitem = { [5455] = 1 }, optional = true } }),
      use_step({ why = "Some other reason." }),
      { action = "D", name = "Done" },
    }
    local log = drive(one_guide(steps), { G1 = { { complete = { 1, 5 }, done = true } } })
    assert.same({}, signals(log, "hidden-use-step"))
  end)

  it("keeps a hidden A step with a use item as never-shown-accept", function()
    local steps = {
      { action = "R", name = "a" },
      { action = "A", name = "Q", qids = { 5 }, hidden = true, why = HIDDEN_USE,
        tags = { use = "5456", lootitem = { [5455] = 1 } } },
      { action = "D", name = "Done" },
    }
    local log = drive(one_guide(steps), { G1 = { { complete = { 1, 3 }, done = true } } })
    assert.equal(1, #signals(log, "never-shown-accept"))
    assert.same({}, signals(log, "hidden-use-step"))
  end)

  -- A turn-in refused for a missing item that a hidden L-gated U step of the same
  -- quest produces: the player combines the item off-guide and turns in once more
  -- (design 2026-11-18-hidden-use-turnin). The world is a quest log over bags: an
  -- item objective's progress is the bag count, and a turn-in removes the quest.
  describe("a hidden use step at a refused turn-in", function()
    local function item_world(objectives)
      local w = fx.fake_world()
      local quest = { objectives = objectives }
      local order = { 1016 }
      -- The U steps' use item (U|5456|) is in the bags: the player can use it.
      w.player.bags = { [5456] = 1 }
      w.log = {
        history = {},
        entries = function() local out = {} for i, q in ipairs(order) do out[i] = { id = q, quest = quest } end return out end,
        get = function(_, q) if order[1] == q then return { id = q, quest = quest } end return nil end,
        have = function(_, _, i)
          local obj = quest.objectives[i]
          return math.min(obj.count, w.player.bags[obj.ids[1]] or 0)
        end,
      }
      w.turn_in = function(q)
        for i, obj in ipairs(quest.objectives) do
          if w.log:have(q, i) < obj.count then return false end
        end
        order = {}
        w.log.history[q] = true
        return true
      end
      w.catalog = { quest = function(_, q) return q == 1016 and quest or nil end }
      return w
    end

    -- perform stand-in over the scripted engine: U puts its step's `gives` items in
    -- the bags and fires BAG_UPDATE (with `levels` levels); T turns 1016 in or is
    -- refused "incomplete" while an item objective is short.
    local function drive_items(steps, script, w, opts, guides)
      local E = fx.scripted_engine(guides or one_guide(steps), script, "G1", w)
      E.fired_events = {}
      function E:fire(event) self.fired_events[#self.fired_events + 1] = event end
      opts = opts or {}
      opts.perform = function(ctx, step)
        local s = E.guides[E.cur_gid].steps[step.index] -- before E.perform's settle may switch guides
        if s.before then s.before() end
        local out = E.perform(ctx, step)
        if s.action == "U" then
          for _, id in ipairs(s.gives or {}) do w.player.bags[id] = (w.player.bags[id] or 0) + 1 end
          ctx.engine:fire("BAG_UPDATE", 0)
          out.events = { "BAG_UPDATE" }
          if s.levels then
            w.player.level = w.player.level + s.levels
            out.levels = s.levels
          end
        elseif s.action == "T" then
          if s.refuse then
            out.kind, out.reason = "refused", s.refuse
          elseif not w.turn_in(1016) then
            out.kind, out.reason = "refused", "incomplete"
          else
            -- The engine skips a done quest's steps with this why (WoWPro_Broker.lua:2042).
            for _, u in ipairs(E.guides.G1.steps) do
              if u.action == "U" then u.why = "NextStep(): QID is complete: 1016" end
            end
          end
        end
        return out
      end
      local log = run.drive({ engine = E, world = w, cfg = { race = "Dwarf", class = "WARRIOR" },
        errors = {}, missing_order = {}, addon = { path = "/x" } }, opts)
      return log, E
    end

    local function hidden_use(lootid, extra)
      local s = use_step({ tags = { use = "5456", lootitem = { [lootid] = 1 } }, gives = { lootid } })
      for k, v in pairs(extra or {}) do s[k] = v end
      return s
    end

    local function count(list, v)
      local n = 0
      for _, x in ipairs(list) do if x == v then n = n + 1 end end
      return n
    end

    local SCROLL = { { kind = "item", ids = { 5455 }, count = 1 } }

    it("performs the hidden U step off-guide and turns in", function()
      local w = item_world(SCROLL)
      local steps = {
        { action = "l", name = "Q", qids = { 1016 }, tags = { lootitem = { [12220] = 5 } } },
        hidden_use(5455),
        { action = "T", name = "Q", qids = { 1016 } },
      }
      local log, E = drive_items(steps, { G1 = { { complete = { 1 } }, nil, { complete = { 3 } },
        { complete = { 4 }, done = true } } }, w)
      assert.same({ { gid = "G1", file = "g1.lua", line = 102, qid = 1016, action = "U", for_line = 103,
        events = { "BAG_UPDATE" }, levels = 0 } }, log.offguide)
      assert.same({ "G1:1", "G1:3", "G1:2", "G1:3", "G1:4" }, E.acted)
      assert.is_true(w.log.history[1016])
      local t = log.steps[2]
      assert.equal("T", t.action)
      assert.equal("acted", t.outcome.kind)
      assert.same({}, signals(log, "did-not-advance"))
      assert.same({}, signals(log, "leftover-quests"))
      local hits = signals(log, "hidden-use-step")
      assert.equal(1, #hits)
      assert.equal(102, hits[1].line)
    end)

    it("has an empty offguide list when nothing was done off-guide", function()
      local log = drive(one_guide({ { action = "R", name = "a" } }), { G1 = { { complete = { 1 } },
        { complete = { 2 }, done = true } } })
      assert.same({}, log.offguide)
    end)

    it("uses the lowest-index hidden U step whose L item is the missing item (Review Focus 1)", function()
      local w = item_world(SCROLL)
      local steps = {
        { action = "R", name = "a" },
        hidden_use(9999),
        hidden_use(5455),
        hidden_use(5455),
        { action = "T", name = "Q", qids = { 1016 } },
      }
      local log, E = drive_items(steps, { G1 = { { complete = { 1 } }, nil, nil, nil, { complete = { 5 } },
        { complete = { 6 }, done = true } } }, w)
      assert.equal(1, #log.offguide)
      assert.equal(103, log.offguide[1].line)
      assert.equal(105, log.offguide[1].for_line)
      assert.equal(0, count(E.acted, "G1:2"))
      assert.equal(0, count(E.acted, "G1:4"))
      assert.same({}, signals(log, "did-not-advance"))
    end)

    it("does nothing when the hidden U step's L item isn't the missing item (Review Focus 2)", function()
      local w = item_world(SCROLL)
      local steps = {
        { action = "R", name = "a" },
        hidden_use(9999),
        { action = "T", name = "Q", qids = { 1016 } },
      }
      local log, E = drive_items(steps, { G1 = { { complete = { 1 } }, nil, nil,
        { complete = { 4 }, done = true } } }, w)
      assert.same({}, log.offguide)
      assert.equal(0, count(E.acted, "G1:2"))
      assert.equal(1, #signals(log, "did-not-advance"))
      assert.equal(1, #signals(log, "leftover-quests"))
      assert.equal(1, #signals(log, "hidden-use-step"))
    end)

    it("tries the turn-in once more only, then records did-not-advance (Review Focus 3)", function()
      local w = item_world({ { kind = "item", ids = { 5455 }, count = 1 }, { kind = "item", ids = { 7777 }, count = 1 } })
      local steps = {
        { action = "R", name = "a" },
        hidden_use(5455),
        { action = "T", name = "Q", qids = { 1016 } },
      }
      local log, E = drive_items(steps, { G1 = { { complete = { 1 } }, nil, nil,
        { complete = { 4 }, done = true } } }, w)
      assert.equal(1, #log.offguide)
      assert.equal(1, count(E.acted, "G1:2"))
      assert.equal(2, count(E.acted, "G1:3"))
      local dna = signals(log, "did-not-advance")
      assert.equal(1, #dna)
      assert.equal(103, dna[1].line)
      assert.equal("incomplete", dna[1].reason)
      assert.equal("refused", log.steps[2].outcome.kind)
      assert.equal(1, #signals(log, "leftover-quests"))
    end)

    it("never re-performs a U step the guide showed (Review Focus 4)", function()
      local w = item_world(SCROLL)
      local steps = {
        { action = "R", name = "a" },
        use_step({ hidden = false, why = HIDDEN_USE }), -- shown and performed; gives nothing
        { action = "T", name = "Q", qids = { 1016 } },
      }
      local log, E = drive_items(steps, { G1 = { { complete = { 1 } }, { complete = { 2 } }, nil,
        { complete = { 4 }, done = true } } }, w)
      assert.same({}, log.offguide)
      assert.equal(1, count(E.acted, "G1:2"))
      assert.equal(1, #signals(log, "did-not-advance"))
    end)

    it("applies the off-guide U action's events and levels (Review Focus 5)", function()
      local w = item_world(SCROLL)
      local steps = {
        { action = "R", name = "a" },
        hidden_use(5455, { levels = 1 }),
        { action = "T", name = "Q", qids = { 1016 } },
      }
      local events = {}
      local log, E = drive_items(steps, { G1 = { { complete = { 1 } }, nil, { complete = { 3 } },
        { complete = { 4 }, done = true } } }, w, { on_progress = function(e) events[#events + 1] = e end })
      assert.same({ "BAG_UPDATE" }, E.fired_events)
      assert.same({ "BAG_UPDATE" }, log.offguide[1].events)
      assert.equal(1, log.offguide[1].levels)
      assert.equal(2, w.player.level)
      local levels = {}
      for _, e in ipairs(events) do if e.kind == "level" then levels[#levels + 1] = e.level end end
      assert.same({ 2 }, levels)
      assert.same({}, signals(log, "did-not-advance"))
    end)
    it("does not use the U step off-guide when its use item is not in the bags", function()
      local w = item_world(SCROLL)
      w.player.bags[5456] = nil
      local steps = {
        { action = "R", name = "a" },
        hidden_use(5455),
        { action = "T", name = "Q", qids = { 1016 } },
      }
      local log, E = drive_items(steps, { G1 = { { complete = { 1 } }, nil, nil,
        { complete = { 4 }, done = true } } }, w)
      assert.same({}, log.offguide)
      assert.equal(0, count(E.acted, "G1:2"))
      assert.is_nil(w.player.bags[5456])
      assert.equal(1, #signals(log, "did-not-advance"))
    end)

    it("does not perform the U step again for a second turn-in of the quest after a failed retry", function()
      local w = item_world({ { kind = "item", ids = { 5455 }, count = 1 }, { kind = "item", ids = { 7777 }, count = 1 } })
      local steps = {
        { action = "R", name = "a" },
        hidden_use(5455),
        { action = "T", name = "Q", qids = { 1016 } },
        -- 5455 is short again at the second turn-in (as if the combined item were lost).
        { action = "T", name = "Q", qids = { 1016 }, before = function() w.player.bags[5455] = nil end },
      }
      local log, E = drive_items(steps, { G1 = { { complete = { 1 } }, nil, nil, nil,
        { complete = { 5 }, done = true } } }, w)
      assert.equal(1, #log.offguide)
      assert.equal(1, count(E.acted, "G1:2"))
      assert.equal(1, count(E.acted, "G1:4"))
    end)

    it("does not use the U step off-guide for a refusal other than incomplete", function()
      local w = item_world(SCROLL)
      local steps = {
        { action = "R", name = "a" },
        hidden_use(5455),
        { action = "T", name = "Q", qids = { 1016 }, refuse = "not-in-log" },
      }
      local log, E = drive_items(steps, { G1 = { { complete = { 1 } }, nil, nil,
        { complete = { 4 }, done = true } } }, w)
      assert.same({}, log.offguide)
      assert.equal(0, count(E.acted, "G1:2"))
      assert.equal(1, count(E.acted, "G1:3"))
    end)

    it("does not use a U step off-guide whose why is not the missing-items why", function()
      local w = item_world(SCROLL)
      local steps = {
        { action = "R", name = "a" },
        hidden_use(5455, { why = "NextStep(): skipped by the player" }),
        { action = "T", name = "Q", qids = { 1016 } },
      }
      local log, E = drive_items(steps, { G1 = { { complete = { 1 } }, nil, nil,
        { complete = { 4 }, done = true } } }, w)
      assert.same({}, log.offguide)
      assert.equal(0, count(E.acted, "G1:2"))
      assert.equal(1, #signals(log, "did-not-advance"))
    end)

    it("checks a turn-in's settle once when the off-guide U step leaves the guide", function()
      local w = item_world(SCROLL)
      local steps = {
        { action = "R", name = "a" },
        hidden_use(5455),
        { action = "T", name = "Q", qids = { 1016 } },
      }
      local guides = one_guide(steps)
      guides.G1.next_gid = nil
      guides.G2 = { startlevel = 1, file = "g2.lua", steps = { { action = "D", name = "Done" } } }
      local log = drive_items(steps, { G1 = { { complete = { 1 } }, { switch = "G2" }, { hit_limit = true } },
        G2 = { { complete = { 1 }, done = true } } }, w, nil, guides)
      local limits = {}
      for _, s in ipairs(signals(log, "stuck")) do
        if s.reason == "settle-limit" and s.line == 103 then limits[#limits + 1] = s end
      end
      assert.equal(1, #limits)
    end)
  end)

  describe("arrival credits", function()
    it("records each objective an arrival credited in log.arrivals", function()
      local steps = {
        { action = "R", name = "Secure the Mountain", qids = { 98319 },
          outcome = { kind = "acted", arrivals = { 1 } } },
      }
      local log = drive(one_guide(steps), { G1 = { { complete = { 1 } }, { complete = { 2 }, done = true } } })
      assert.same({ { gid = "G1", file = "g1.lua", line = 101, qid = 98319, objective = 1 } }, log.arrivals)
    end)

    it("has an empty arrivals list when no arrival credited anything", function()
      local log = drive(one_guide({ { action = "R", name = "a" } }), { G1 = { { complete = { 1 } },
        { complete = { 2 }, done = true } } })
      assert.same({}, log.arrivals)
    end)
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

  describe("quest colour", function()
    local function accept(level, quest, grind)
      -- The colour is judged at the do step: here the quest's T step.
      local steps = { { action = "A", name = "Q", qids = { 5 }, outcome = { kind = "acted", grind = grind } },
        { action = "T", name = "Q", qids = { 5 } } }
      local world = fx.fake_world({ [5] = quest })
      world.player.level = level
      return drive(one_guide(steps), { G1 = { { complete = { 1 } }, { complete = { 2 } } } }, {}, world)
    end
    local function colours(log)
      local out = {}
      for _, s in ipairs(log.signals) do
        if s.signal:match("^quest%-") then out[#out + 1] = s end
      end
      return out
    end

    it("emits quest-red with the levels and no exempt for a combat quest", function()
      local c = colours(accept(30, { name = "Hard", level = 36 }))
      assert.equal(1, #c)
      assert.equal("quest-red", c[1].signal)
      assert.same({ 36, 30, "red" }, { c[1].quest_level, c[1].char_level, c[1].color })
      assert.is_nil(c[1].exempt)
      assert.equal(5, c[1].qid)
    end)
    it("emits quest-orange at 3 to 4 levels above", function()
      assert.equal("quest-orange", colours(accept(30, { level = 33 }))[1].signal)
    end)
    it("emits quest-grey for any quest, a non-combat one too", function()
      assert.equal("quest-grey", colours(accept(30, { level = 10 }))[1].signal)
      local c = colours(accept(30, { level = 10, noncombat = "commerce" }))
      assert.equal("quest-grey", c[1].signal)
    end)
    it("emits nothing for yellow or green", function()
      assert.same({}, colours(accept(30, { level = 30 })))
      assert.same({}, colours(accept(30, { level = 25 })))
    end)
    it("exempts a non-combat quest from red and orange", function()
      assert.same({}, colours(accept(1, { level = 60, noncombat = "commerce" })))
      assert.same({}, colours(accept(30, { level = 33, noncombat = "no-combat-objective" })))
    end)
    it("emits one colour signal per do-step line: the first play wins", function()
      local steps = { { action = "A", name = "Q", qids = { 5 } }, { action = "T", name = "Q", qids = { 5 } },
        { action = "R", name = "Back" } }
      local script = { G1 = { { complete = { 1 } }, { complete = { 2 } },
        { complete = { 3 }, uncomplete = { 1, 2 }, level = 33 } } }
      local world = fx.fake_world({ [5] = { name = "Hard", level = 36 } })
      world.player.level = 30
      local log, E = drive(one_guide(steps), script, {}, world)
      local plays = 0
      for _, a in ipairs(E.acted) do if a == "G1:1" then plays = plays + 1 end end
      assert.equal(2, plays)
      local c = colours(log)
      assert.equal(1, #c)
      assert.equal("quest-red", c[1].signal)
    end)
    it("emits nothing for a quest with no level or no catalog entry, and does not error", function()
      assert.same({}, colours(accept(30, { name = "No level" })))
      local steps = { { action = "A", name = "Q", qids = { 5 } } }
      local log = drive(one_guide(steps), { G1 = { { complete = { 1 } } } }, {}, fx.fake_world({}))
      assert.same({}, colours(log))
    end)
    it("reads the level after a grind raised it", function()
      -- Quest 33 needs level 33: the grind leaves the player at 33, so it is yellow, not red.
      local steps = { { action = "A", name = "Q", qids = { 5 },
        outcome = { kind = "acted", grind = { kills = 9, to = 33, short = 3 }, level = 33 } } }
      local world = fx.fake_world({ [5] = { name = "Q", level = 33, required_level = 33 } })
      world.player.level = 30
      local log = drive(one_guide(steps), { G1 = { { complete = { 1 } } } }, {}, world)
      assert.same({}, colours(log))
      assert.equal(1, #signals(log, "below-level"))
    end)
    it("emits nothing for a refused accept", function()
      local steps = { { action = "A", name = "Q", qids = { 5 }, outcome = { kind = "refused", reason = "class" } } }
      local log = drive(one_guide(steps), {}, {}, fx.fake_world({ [5] = { level = 60 } }))
      assert.same({}, colours(log))
    end)
  end)

  describe("level gap", function()
    local function colours(log)
      local out = {}
      for _, s in ipairs(log.signals) do
        if s.signal:match("^quest%-") and s.signal ~= "quest-grey" then out[#out + 1] = s end
      end
      return out
    end
    -- Accept (A), then the do steps. Quest 5 is level 26; the character is level 20 at the accept.
    local function play(steps, script, quest, level)
      local world = fx.fake_world({ [5] = quest or { name = "Hard", level = 26 }, [6] = { name = "Other", level = 40 } })
      world.player.level = level or 20
      return drive(one_guide(steps), script, {}, world)
    end

    it("emits level-check with the gap when an L step ground to its check point", function()
      local steps = { { action = "L", name = "Level 2", tags = { level = "2;-650" },
        outcome = { kind = "acted", grind = { kills = 7, to = 2, point = 250, offset = -650, short = 1.0 } } } }
      local log = play(steps, { G1 = { { complete = { 1 } } } })
      local c = signals(log, "level-check")
      assert.equal(1, #c)
      assert.equal(1.0, c[1].gap)
      assert.same({ kills = 7, to = 2, point = 250, offset = -650 }, c[1].grind)
      assert.same({}, signals(log, "below-level"))
    end)
    it("emits level-check on a non-L step carrying a LVL tag that ground", function()
      local steps = { { action = "R", name = "Go", tags = { level = "3" },
        outcome = { kind = "acted", grind = { kills = 3, to = 3, point = 0, offset = 0, short = 2.0 } } } }
      local log = play(steps, { G1 = { { complete = { 1 } } } })
      assert.equal(2.0, signals(log, "level-check")[1].gap)
    end)
    it("emits no level-check when the step needed no grind", function()
      local steps = { { action = "L", name = "Level 2", tags = { level = "2" }, outcome = { kind = "acted" } } }
      assert.same({}, signals(play(steps, { G1 = { { complete = { 1 } } } }), "level-check"))
    end)

    it("judges the colour at the C step, not the accept", function()
      -- Red/orange at the accept (level 20 vs 26) would be red; at the C step the character
      -- is 23.7, so the gap is 2.3 and the band orange (26 - 23 = 3).
      local steps = {
        { action = "A", name = "Hard", qids = { 5 } },
        { action = "C", name = "Kill things", qids = { 5 }, outcome = { kind = "acted", level = 23, xp = 700 } },
      }
      local script = { G1 = { { complete = { 1 } }, { complete = { 2 } } } }
      local world = fx.fake_world({ [5] = { name = "Hard", level = 26 } })
      world.player.level = 20
      -- level 23 needs xp_max(23) to give .7
      local xp = require("hwc.world.xp")
      steps[2].outcome.xp = math.floor(xp.to_next(23) * 0.7)
      local log = drive(one_guide(steps), script, {}, world)
      local c = colours(log)
      assert.equal(1, #c)
      assert.equal("quest-orange", c[1].signal)
      assert.equal("C", c[1].action)
      assert.equal(2.3, c[1].gap)
      assert.equal(23, c[1].char_level)
      assert.equal(5, c[1].qid)
      assert.equal(6.0, c[1].accept_gap)
    end)
    it("judges a quest at its T step when no C or K step is played", function()
      local steps = {
        { action = "A", name = "Hard", qids = { 5 } },
        { action = "T", name = "Hard", qids = { 5 } },
      }
      local log = play(steps, { G1 = { { complete = { 1 } }, { complete = { 2 } } } })
      local c = colours(log)
      assert.equal(1, #c)
      assert.equal("quest-red", c[1].signal)
      assert.equal("T", c[1].action)
      assert.equal(6.0, c[1].gap)
    end)
    it("gives no colour finding for a quest accepted but never done", function()
      local steps = { { action = "A", name = "Hard", qids = { 5 } }, { action = "R", name = "Away" } }
      assert.same({}, colours(play(steps, { G1 = { { complete = { 1 } }, { complete = { 2 } } } })))
    end)
    it("judges once, at the first do step, even when a T step follows", function()
      local steps = {
        { action = "A", name = "Hard", qids = { 5 } },
        { action = "C", name = "Kill", qids = { 5 } },
        { action = "T", name = "Hard", qids = { 5 } },
      }
      local c = colours(play(steps, { G1 = { { complete = { 1 } }, { complete = { 2 } }, { complete = { 3 } } } }))
      assert.equal(1, #c)
      assert.equal("C", c[1].action)
    end)
    it("judges each quest of a do step that lists several", function()
      local steps = {
        { action = "A", name = "Hard", qids = { 5 } },
        { action = "A", name = "Other", qids = { 6 } },
        { action = "C", name = "Kill", qids = { 5, 6 } },
      }
      local c = colours(play(steps, { G1 = { { complete = { 1 } }, { complete = { 2 } }, { complete = { 3 } } } }))
      table.sort(c, function(a, b) return a.qid < b.qid end)
      assert.same({ 5, 6 }, { c[1].qid, c[2].qid })
      assert.same({ 6.0, 20.0 }, { c[1].gap, c[2].gap })
    end)
    it("keeps one colour finding per do-step line", function()
      local steps = {
        { action = "A", name = "Hard", qids = { 5 } },
        { action = "C", name = "Kill", qids = { 5 } },
      }
      local script = { G1 = { { complete = { 1 } }, { complete = { 2 } } } }
      local log = play(steps, script)
      assert.equal(1, #colours(log))
    end)
    it("keeps grey at the accept", function()
      local steps = { { action = "A", name = "Old", qids = { 5 } } }
      local log = play(steps, { G1 = { { complete = { 1 } } } }, { name = "Old", level = 5 }, 30)
      local g = signals(log, "quest-grey")
      assert.equal(1, #g)
      assert.equal("A", g[1].action)
    end)
    it("skips a non-combat quest at the do step", function()
      local steps = { { action = "A", name = "Buy", qids = { 5 } }, { action = "T", name = "Buy", qids = { 5 } } }
      local log = play(steps, { G1 = { { complete = { 1 } }, { complete = { 2 } } } },
        { name = "Buy", level = 40, noncombat = "commerce" })
      assert.same({}, colours(log))
    end)
  end)

  it("records levels_short from the grind on a below-level signal", function()
    local steps = { { action = "A", name = "Low", qids = { 5 },
      outcome = { kind = "acted", grind = { kills = 228, to = 32, short = 0.9 } } } }
    local log = drive(one_guide(steps), {}, {}, fx.fake_world({ [5] = { name = "Low Quest" } }))
    local b = signals(log, "below-level")
    assert.equal(0.9, b[1].levels_short)
    assert.same({ kills = 228, to = 32 }, b[1].grind)
  end)

  it("carries the missing prerequisites and their names on a prerequisite accept-refused", function()
    local steps = {
      { action = "A", name = "The Reports", qids = { 291 },
        outcome = { kind = "refused", reason = "prerequisite", missing = { 98323, 99999 }, missing_any = true } },
    }
    local log = drive(one_guide(steps), {}, {}, fx.fake_world({ [98323] = { name = "Secure the Mountain" } }))
    local ar = signals(log, "accept-refused")
    assert.equal(1, #ar)
    assert.equal("prerequisite", ar[1].reason)
    assert.same({ 98323, 99999 }, ar[1].missing)
    assert.same({ ["98323"] = "Secure the Mountain" }, ar[1].missing_names)
    assert.is_true(ar[1].missing_any)
  end)

  describe("missing_outcome on a prerequisite accept-refused", function()
    local function refused() return { action = "A", name = "Tharil'zun", qids = { 19 },
      outcome = { kind = "refused", reason = "prerequisite", missing = { 98387 } } } end
    local function after(records) return { action = "A", name = "Later", qids = { 5 }, outcome = { kind = "acted", records = records } } end
    local function outcome_of(steps)
      local log = drive(one_guide(steps), {}, {}, fx.fake_world({ [98387] = { name = "Blackrock Blockade" } }))
      return signals(log, "accept-refused")[1]
    end
    it("never-accepted when the quest never appears", function()
      assert.same({ ["98387"] = "never-accepted" }, outcome_of({ refused() }).missing_outcome)
    end)
    it("never-completed when it is accepted later but not turned in", function()
      local sig = outcome_of({ refused(), after({ { kind = "quest_accept", id = 98387 } }) })
      assert.same({ ["98387"] = "never-completed" }, sig.missing_outcome)
    end)
    it("never-completed when accepted, abandoned and re-accepted without a turn-in", function()
      local sig = outcome_of({ refused(), after({ { kind = "quest_accept", id = 98387 }, { kind = "quest_accept", id = 98387 } }) })
      assert.same({ ["98387"] = "never-completed" }, sig.missing_outcome)
    end)
    it("completed-later when turned in after the refusal", function()
      local sig = outcome_of({ refused(), after({ { kind = "quest_accept", id = 98387 }, { kind = "quest_turn_in", id = 98387 } }) })
      assert.same({ ["98387"] = "completed-later" }, sig.missing_outcome)
    end)
    it("drops a quest completed before the refusal, without crashing", function()
      local before = after({ { kind = "quest_accept", id = 98387 }, { kind = "quest_turn_in", id = 98387 } })
      local sig = outcome_of({ before, refused() })
      assert.is_nil(sig.missing_outcome)
    end)
  end)

  it("carries the chain part of a missing prerequisite", function()
    local steps = {
      { action = "A", name = "The Reports", qids = { 291 },
        outcome = { kind = "refused", reason = "prerequisite", missing = { 1029 } } },
    }
    local log = drive(one_guide(steps), {}, {}, fx.fake_world({ [1029] = { name = "Raene's Cleansing", chain = { 8, 11 } } }))
    local ar = signals(log, "accept-refused")
    assert.same({ ["1029"] = { part = 8, total = 11 } }, ar[1].missing_chain)
  end)

  it("turns a reputation refusal into an unverified accept-refused naming the gate", function()
    local ReputationState = require("hwc.world.reputation_state")
    -- The catalog calls the quest verified: the refusal's own confidence wins.
    local world = fx.fake_world({ [9] = { name = "Honored Only", confidence = "verified",
      min_rep = { faction = 72, value = 9000 } } })
    world.reputation = ReputationState.new("Dwarf", "Alliance", { [72] = "Stormwind" })
    local steps = { { action = "A", name = "Honored Only", qids = { 9 },
      outcome = { kind = "refused", reason = "reputation" } } }
    local log, E = drive(one_guide(steps), {}, {}, world)
    local ar = signals(log, "accept-refused")
    assert.equal(1, #ar)
    assert.equal("reputation", ar[1].reason)
    assert.equal("unverified", ar[1].confidence)
    assert.same({ faction = 72, name = "Stormwind", bound = "min", value = 9000, points = 3100 }, ar[1].rep)
    assert.same({}, signals(log, "did-not-advance"))
    assert.same({ "G1:1", "G1:2" }, E.manual)
  end)

  it("still records a reputation refusal when the world has no reputation state", function()
    local steps = { { action = "A", name = "Gated", qids = { 9 }, outcome = { kind = "refused", reason = "reputation" } } }
    local log = drive(one_guide(steps), {}, {}, fx.fake_world({ [9] = { confidence = "verified" } }))
    local ar = signals(log, "accept-refused")
    assert.equal(1, #ar)
    assert.equal("unverified", ar[1].confidence)
    assert.is_nil(ar[1].rep)
    assert.is_nil(log.reputation)
  end)

  -- Design 2026-11-18-reputation §4.5, §6: REP|Gelkis Clan Centaur;91;hated-neutral (Galak) at
  -- 30_41_Alliance.lua:544. The stub returned nil for 91 (unmet_lookups) when WoWPro asked.
  describe("rep-faction-unmet", function()
    local ReputationState = require("hwc.world.reputation_state")
    local function rep_run(prepare, rep, steps_override, opts, script)
      local world = fx.fake_world({ [1382] = { name = "Strange Alliance", confidence = "verified" } })
      world.reputation = ReputationState.new("Dwarf", "Alliance", {})
      prepare(world.reputation)
      local steps = steps_override or {
        { action = "R", name = "Go" },
        { action = "C", name = "Strange Alliance", qids = { 1382 }, rep = rep or "Gelkis Clan Centaur;91;hated-neutral", hidden = true },
      }
      return drive(one_guide(steps), script or { G1 = completes(1) }, opts or {}, world)
    end

    it("reports a REP step whose faction the stub returned nil for", function()
      local log = rep_run(function(r) r.lookups[91] = true; r.unmet_lookups[91] = true end)
      local u = signals(log, "rep-faction-unmet")
      assert.equal(1, #u)
      assert.equal(91, u[1].faction)
      assert.equal("unverified", u[1].confidence)
      assert.equal("G1", u[1].gid)
      assert.equal("g1.lua", u[1].file)
      assert.equal(102, u[1].line)
      assert.equal("C", u[1].action)
      assert.equal("Strange Alliance", u[1].name)
      assert.equal(1382, u[1].qid)
      assert.equal("Faction 91", u[1].faction_name)
      assert.equal("Gelkis Clan Centaur", u[1].tag_faction)
    end)

    it("reports nothing when the stub only ever found the faction", function()
      local log = rep_run(function(r) r.lookups[91] = true; r:gain(91, 0) end)
      assert.same({}, signals(log, "rep-faction-unmet"))
    end)

    it("still reports a faction looked up while unmet and met later in the same guide", function()
      local log = rep_run(function(r) r.lookups[91] = true; r.unmet_lookups[91] = true; r:gain(91, 0) end)
      assert.equal(1, #signals(log, "rep-faction-unmet"))
    end)

    it("reports nothing when the stub was never asked for the faction", function()
      local log = rep_run(function() end)
      assert.same({}, signals(log, "rep-faction-unmet"))
    end)

    -- Driver:close's limit: a run that stops early never reached steps at or past the
    -- furthest one it acted on.
    it("reports nothing for a REP step at or after where an early stop left the run", function()
      local steps = {
        { action = "C", name = "loop", qids = { 1 } },
        { action = "C", name = "Strange Alliance", qids = { 1382 }, rep = "Gelkis Clan Centaur;91;hated-neutral", hidden = true },
      }
      local log = rep_run(function(r) r.unmet_lookups[91] = true end, nil, steps,
        { max_iterations = 3, stuck_limit = 100 }, { G1 = { { on_manual = { uncomplete = { 1 } } } } })
      assert.equal("iterations", log.stop.reason)
      assert.same({}, signals(log, "rep-faction-unmet"))
    end)

    it("gives no signal and no error for a tag with no id or a non-numeric id", function()
      for _, tag in ipairs({ "Gelkis Clan Centaur", "Gelkis Clan Centaur;", "Gelkis Clan Centaur;abc;neutral", ";;" }) do
        local log = rep_run(function(r) r.unmet_lookups[91] = true end, tag)
        assert.same({}, signals(log, "rep-faction-unmet"), tag)
      end
    end)

    it("gives no signal and no error for a spaced tag whose id was never looked up", function()
      local log = rep_run(function() end, " Gelkis Clan Centaur ; 91 ; hated-neutral ")
      assert.same({}, signals(log, "rep-faction-unmet"))
    end)

    -- WoWPro_Broker.lua:2807/:2816 split on ";" and tonumber the id, which accepts spaces.
    it("trims the tag's faction name and reads a spaced id as WoWPro does", function()
      local log = rep_run(function(r) r.unmet_lookups[91] = true end, " Gelkis Clan Centaur ; 91 ; hated-neutral ")
      local u = signals(log, "rep-faction-unmet")
      assert.equal(1, #u)
      assert.equal("Gelkis Clan Centaur", u[1].tag_faction)
    end)

    it("leaves the tag name out when the tag's first field is empty", function()
      local log = rep_run(function(r) r.unmet_lookups[91] = true end, " ;91;neutral")
      local u = signals(log, "rep-faction-unmet")
      assert.equal(1, #u)
      assert.is_nil(u[1].tag_faction)
    end)
  end)

  -- Review Focus 5: changes in turn-in order, assumptions sorted; identical JSON twice.
  it("carries the world's reputation changes and assumptions into the log, deterministically", function()
    local ReputationState = require("hwc.world.reputation_state")
    local function world()
      local w = fx.fake_world()
      local r = ReputationState.new("Gnome", "Alliance", { [500] = "Zeta", [600] = "Alpha", [92] = "Gelkis Clan Centaur" })
      for _, g in ipairs({ { 7, 600, 10 }, { 7, 500, 20 }, { 8, 92, 100 } }) do r:reward(g[1], g[2], g[3]) end
      w.reputation = r
      return w
    end
    local json = require("hwc.json")
    local a = drive(one_guide({ { action = "R", name = "Go" } }), { G1 = completes(1) }, {}, world())
    local b = drive(one_guide({ { action = "R", name = "Go" } }), { G1 = completes(1) }, {}, world())
    assert.same({ 7, 7, 8 }, { a.reputation.changes[1].qid, a.reputation.changes[2].qid, a.reputation.changes[3].qid })
    assert.same({ "starting reputation for Gnome is inferred, not captured",
      "factions first met at an assumed Neutral 0: Alpha, Zeta",
      "reward scaling by level is unverified for Forever" }, a.reputation.assumptions)
    assert.equal(json.encode(a.reputation), json.encode(b.reputation))
    assert.equal(json.encode(a), json.encode(b))
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

  it("records the level the run passed a hidden accept at, not the level at close", function()
    local guides = one_guide({
      { action = "R", name = "a" },
      { action = "A", name = "Hidden", qids = { 55 }, why = "PRE not met", hidden = true },
      { action = "R", name = "b" },
      { action = "R", name = "c" },
    })
    local script = { G1 = { { complete = { 1 }, level = 4 }, nil, { complete = { 3 } }, { complete = { 4 }, level = 7 } } }
    local log = drive(guides, script)
    assert.equal(4, signals(log, "never-shown-accept")[1].level)
    assert.equal(1, log.guide_levels[1].enter)
    assert.equal(7, log.guide_levels[1].leave)
  end)

  it("records each guide's entry and exit levels", function()
    local guides = {
      G1 = { startlevel = 1, next_gid = "G2", file = "g1.lua", steps = { { action = "R", name = "a" } } },
      G2 = { startlevel = 5, next_gid = "G3", file = "g2.lua", steps = { { action = "R", name = "b" } } },
      G3 = { startlevel = 10, file = "g3.lua", steps = { { action = "R", name = "c" }, { action = "D", name = "Done" } } },
    }
    local script = {
      G1 = { { complete = { 1 }, done = true, switch = "G2", level = 5 } },
      G2 = { { complete = { 1 }, done = true, switch = "G3" } },
      G3 = completes(1),
    }
    local log = drive(guides, script)
    assert.same({ gid = "G1", file = "g1.lua", start_level = 1, enter = 1, leave = 5, finished = true, last_line = 101 },
      log.guide_levels[1])
    assert.equal("G2", log.guide_levels[2].gid)
    assert.equal(5, log.guide_levels[2].enter)
  end)

  it("marks a guide cut short as not finished", function()
    local steps = { { action = "C", name = "loop", qids = { 1 } } }
    local log = drive(one_guide(steps), { G1 = { { on_manual = { uncomplete = { 1 } } } } },
      { max_iterations = 3, stuck_limit = 100 })
    assert.equal(1, #log.guide_levels)
    assert.is_false(log.guide_levels[1].finished)
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
      assert.equal(1, j.level_after)
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

    it("raises the level with the XP table when the start guide is excluded", function()
      local world = fx.fake_world()
      local log = drive(chain(), SCRIPT, { included = set("G2", "G3") }, world)
      assert.equal(5, world.player.level)
      local xp = require("hwc.world.xp")
      local total = 0
      for l = 1, 4 do total = total + xp.to_next(l) end
      local recorded = 0
      for _, r in ipairs(world.xp_records) do recorded = recorded + r.n end
      assert.equal(total, recorded)
      assert.equal(5, log.jumps[1].level_after)
    end)

    it("a mid-chain jump keeps the level earned so far", function()
      local world = fx.fake_world()
      world.player.level = 3
      local log = drive(chain(), SCRIPT, { included = set("G1", "G3") }, world)
      assert.equal(3, log.jumps[1].level_before)
      assert.equal(3, log.jumps[1].level_after)
    end)

    it("raises the level past 25 to a later guide's start level", function()
      local guides = chain()
      guides.G3.startlevel = 40
      local log = drive(guides, SCRIPT, { included = set("G3") })
      assert.equal(40, log.jumps[1].level_after)
    end)

    it("stops the raise at the XP cap", function()
      local guides = chain()
      guides.G3.startlevel = 70
      local log = drive(guides, SCRIPT, { included = set("G3") })
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

  -- opts.on_progress: the driver reports guide, jump and level events and never prints.
  describe("progress events", function()
    local function collect(guides, script, opts, world)
      local events = {}
      opts = opts or {}
      opts.on_progress = function(e) events[#events + 1] = e end
      local log, E = drive(guides, script, opts, world)
      return events, log, E
    end

    local function of(events, kind)
      local out = {}
      for _, e in ipairs(events) do
        if e.kind == kind then out[#out + 1] = e end
      end
      return out
    end

    local function chain()
      return {
        G1 = { startlevel = 1, next_gid = "G2", file = "g1.lua", steps = { { action = "R", name = "a" } } },
        G2 = { startlevel = 1, next_gid = "G3", file = "g2.lua", steps = { { action = "R", name = "b" } } },
        G3 = { startlevel = 1, file = "g3.lua", steps = { { action = "R", name = "c" }, { action = "D", name = "Done" } } },
      }
    end
    local SCRIPT = {
      G1 = { { complete = { 1 }, done = true, switch = "G2" } },
      G2 = { { complete = { 1 }, done = true, switch = "G3" } },
      G3 = completes(1),
    }

    it("reports each opened guide with its file and index, in order", function()
      local events = collect(chain(), SCRIPT)
      local guides = of(events, "guide")
      assert.same({
        { kind = "guide", gid = "G1", file = "g1.lua", index = 1 },
        { kind = "guide", gid = "G2", file = "g2.lua", index = 2 },
        { kind = "guide", gid = "G3", file = "g3.lua", index = 3 },
      }, guides)
    end)

    it("reports one jump event naming the excluded guides", function()
      local events = collect(chain(), SCRIPT, { included = { G1 = true, G3 = true } })
      local jumps = of(events, "jump")
      assert.same({ { kind = "jump", from = "G2", to = "G3", passed = { "G2" } } }, jumps)
    end)

    it("reports a jump that ends the chain with no target", function()
      local events = collect(chain(), SCRIPT, { included = { G1 = true } })
      local jumps = of(events, "jump")
      assert.equal(1, #jumps)
      assert.is_nil(jumps[1].to)
      assert.same({ "G2", "G3" }, jumps[1].passed)
    end)

    it("reports one level event per level gained, not the starting level", function()
      local steps = { { action = "R", name = "a" }, { action = "R", name = "b" } }
      local events = collect(one_guide(steps), { G1 = {
        { complete = { 1 }, level = 2 }, { complete = { 2 }, level = 3 },
      } })
      assert.same({ { kind = "level", level = 2 }, { kind = "level", level = 3 } }, of(events, "level"))
    end)

    it("reports the level a jump at the start of a run raises", function()
      local guides = chain()
      guides.G2.startlevel = 5
      local events = collect(guides, SCRIPT, { included = { G2 = true } })
      assert.same({ { kind = "level", level = 5 } }, of(events, "level"))
    end)

    it("leaves the run log byte-identical with and without on_progress", function()
      local json = require("hwc.json")
      local plain = drive(chain(), SCRIPT, { included = { G1 = true, G3 = true } })
      local _, with = collect(chain(), SCRIPT, { included = { G1 = true, G3 = true } })
      assert.equal(json.encode(plain), json.encode(with))
    end)
  end)
end)
