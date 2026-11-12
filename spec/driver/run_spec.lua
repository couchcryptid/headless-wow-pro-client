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
    local m = signals(log, "manual-completion")
    assert.is_false(m[1].expected)
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
    local left = signals(log, "leftover-quests")
    assert.equal("G1", left[1].gid)
    assert.equal(77, left[1].qid)
    assert.same({ "G1:1", "G1:3", "G2:1", "G2:2" }, E.acted)
    assert.equal("no-next-guide", log.stop.reason)
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
    assert.equal("G1", signals(log, "leftover-quests")[1].gid)
    assert.equal("Onwards", signals(log, "manual-completion")[1].name)
  end)

  it("tags an engine-completed unshown DUNGEON accept engine-dungeon-skip", function()
    local steps = {
      { action = "R", name = "a" },
      { action = "A", name = "Deadmines", qids = { 3 }, tags = { dungeon = "1581" }, hidden = true },
    }
    local log = drive(one_guide(steps), { G1 = { { complete = { 1, 2 } } } })
    local hidden = signals(log, "never-shown-accept")
    assert.equal(1, #hidden)
    assert.equal("engine-dungeon-skip", hidden[1].reason)
  end)

  it("stops with chain-range when the next guide starts at level 25", function()
    local guides = {
      G1 = { startlevel = 1, next_gid = "G2", steps = { { action = "R", name = "a" } } },
      G2 = { startlevel = 25, steps = { { action = "R", name = "b" } } },
    }
    local log, E = drive(guides, { G1 = { { complete = { 1 }, done = true, switch = "G2" } } })
    assert.equal("chain-range", log.stop.reason)
    assert.equal("G2", log.stop.gid)
    assert.same({ "G1", "G2" }, log.guides)
    assert.same({ "G1:1" }, E.acted)
    assert.same({}, signals(log, "never-shown-accept"))
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

  it("stops with level when the player reaches stop_level", function()
    local world = fx.fake_world()
    local steps = { { action = "R", name = "a" }, { action = "A", name = "b", qids = { 2 }, hidden = true } }
    local log, E = drive(one_guide(steps), { G1 = { { complete = { 1 }, level = 25 } } }, {}, world)
    assert.equal("level", log.stop.reason)
    assert.equal(25, log.stop.level)
    assert.same({ "G1:1" }, E.acted)
    -- the unreached rest of the guide is not reported as hidden
    assert.same({}, signals(log, "never-shown-accept"))
  end)

  it("turns refusals into log-full, accept-refused, orphan-turnin and below-level", function()
    local steps = {
      { action = "A", name = "Full", qids = { 1 }, outcome = { kind = "refused", reason = "log-full" } },
      { action = "A", name = "Class", qids = { 2 }, outcome = { kind = "refused", reason = "class" } },
      { action = "T", name = "Orphan", qids = { 3, 4 }, outcome = { kind = "refused", reason = "not-in-log" } },
      { action = "A", name = "Low", qids = { 5 }, outcome = { kind = "acted", grind = { kills = 9, to = 4 } } },
    }
    local script = { G1 = { nil, nil, nil, { complete = { 4 } } } }
    local log = drive(one_guide(steps), script)
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
    assert.equal(3, #signals(log, "did-not-advance"))
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
    for _, r in ipairs({ "level", "chain-range", "no-next-guide", "stuck", "iterations", "errors", "no-step", "max-guides" }) do
      assert.is_true(run.STOP[r], r)
    end
  end)
end)
