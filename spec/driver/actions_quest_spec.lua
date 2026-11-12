-- Quest step actions (design spec §5.2): A, C/K, T, refusals, grind-to-level and
-- the Camping 101 abstraction, against a fake engine and a real World on the
-- fixture catalog.
local catalog = require("hwc.catalog")
local World = require("hwc.world")
local actions = require("hwc.driver.actions")

local FIX = "spec/fixtures/catalog"

local function new_catalog()
  return catalog.load({ catalog = {
    questie_dir = FIX .. "/questie",
    wh_json = FIX .. "/wh.json",
    objs_json = FIX .. "/objs.json",
    rate_overrides = FIX .. "/rate_overrides.json",
    supplement = FIX .. "/actions_supplement.json",
  } })
end

-- Fake engine: fire records { event, args... }, settle reports no limit hit,
-- step/num_steps serve a scripted guide, update_guide counts calls.
local function fake_engine(steps)
  local E = { fired = {}, settles = 0, updates = 0, steps = steps or {} }
  function E:fire(event, ...) self.fired[#self.fired + 1] = { event, ... } end
  function E:settle() self.settles = self.settles + 1; return { ran = 0, now = 0, hit_limit = false } end
  function E:step(i) return self.steps[i] end
  function E:num_steps() return #self.steps end
  function E:update_guide() self.updates = self.updates + 1; return true end
  return E
end

local function step(action, qids, tags, name)
  return { index = 1, action = action, name = name or "x", qids = qids, tags = tags or {} }
end

local function setup(race, steps)
  local w = World.new({ race = race or "Dwarf", class = "WARRIOR", faction = "Alliance", sex = 2 }, new_catalog())
  local E = fake_engine(steps)
  return { engine = E, world = w, cfg = {} }, E, w
end

local function names(E)
  local out = {}
  for i, f in ipairs(E.fired) do out[i] = f[1] end
  return out
end

local function has_event(w, kind)
  for _, e in ipairs(w.events) do
    if e.kind == kind then return e end
  end
  return nil
end

describe("actions.perform: A", function()
  it("accepts and fires QUEST_ACCEPTED(1, 179), QUEST_LOG_UPDATE, then settles", function()
    local ctx, E, w = setup()
    local o = actions.perform(ctx, step("A", { 179 }))
    assert.are.equal("acted", o.kind)
    assert.are.equal(179, o.qid)
    assert.are.same({ "QUEST_ACCEPTED", "QUEST_LOG_UPDATE" }, names(E))
    assert.are.same({ "QUEST_ACCEPTED", 1, 179 }, E.fired[1])
    assert.are.same({ "QUEST_ACCEPTED", "QUEST_LOG_UPDATE" }, o.events)
    assert.are.equal(1, E.settles)
    assert.are.equal(0, o.levels)
    assert.is_nil(o.grind)
    assert.is_truthy(w.log:get(179))
    assert.is_nil(w.dialog)
  end)

  it("holds world.dialog = {qid, detail} while the accept events fire", function()
    local ctx, E, w = setup()
    local seen
    function E:fire(event) if event == "QUEST_ACCEPTED" then seen = w.dialog end end
    actions.perform(ctx, step("A", { 179 }))
    assert.are.same({ qid = 179, kind = "detail" }, seen)
    assert.is_nil(w.dialog)
  end)

  it("refuses the 41st quest with log-full, firing nothing", function()
    local ctx, E, w = setup()
    for i = 1, 40 do assert.is_true(w.log:accept(800000 + i, { placeholder_qo = 0 })) end
    local o = actions.perform(ctx, step("A", { 179 }))
    assert.are.equal("refused", o.kind)
    assert.are.equal("log-full", o.reason)
    assert.are.same({}, E.fired)
    assert.are.same({}, o.events)
    assert.are.equal(40, #w.log:entries())
    assert.are.equal(1, E.settles)
  end)

  it("refuses a Human-only quest for a Dwarf (race) and leaves the world unchanged", function()
    local ctx, E, w = setup("Dwarf")
    local before = #w.events
    local o = actions.perform(ctx, step("A", { 92001 }))
    assert.are.equal("refused", o.kind)
    assert.are.equal("race", o.reason)
    assert.are.same({}, E.fired)
    assert.is_nil(w.log:get(92001))
    assert.are.equal(before, #w.events)
  end)

  it("passes class, prerequisite, already-completed and unknown-quest refusals through", function()
    local ctx = setup()
    assert.are.equal("class", actions.perform(ctx, step("A", { 92006 })).reason)
    assert.are.equal("prerequisite", actions.perform(ctx, step("A", { 92007 })).reason)
    actions.perform(ctx, step("A", { 92004 }))
    actions.perform(ctx, step("T", { 92004 }))
    local o = actions.perform(ctx, step("A", { 92004 }))
    assert.are.equal("refused", o.kind)
    assert.are.equal("already-completed", o.reason)
  end)

  it("refuses unknown-quest only when there is no catalog to shape a placeholder", function()
    local ctx, E, w = setup()
    w.catalog = nil
    local o = actions.perform(ctx, step("A", { 999999 }))
    assert.are.equal("refused", o.kind)
    assert.are.equal("unknown-quest", o.reason)
    assert.are.same({}, E.fired)
  end)

  it("accepts an unknown quest as a placeholder shaped from the step's QO", function()
    local ctx, E, w = setup()
    local o = actions.perform(ctx, step("A", { 999999 }, { questtext = "1;3" }))
    assert.are.equal("acted", o.kind)
    assert.are.equal(3, #w.log:get(999999).quest.objectives)
  end)

  it("grinds to the required level when below it, updates the guide, then accepts", function()
    local ctx, E, w = setup()
    local fired_before_ding
    function E:update_guide()
      self.updates = self.updates + 1
      fired_before_ding = fired_before_ding or #self.fired
      return true
    end
    local o = actions.perform(ctx, step("A", { 92002 }))
    assert.are.equal("acted", o.kind)
    assert.are.equal(3, o.grind.to)
    assert.is_true(o.grind.kills > 0)
    assert.are.equal(2, o.levels)
    assert.are.equal(3, w.player.level)
    assert.is_truthy(w.log:get(92002))
    assert.is_true(E.updates >= 1)
    assert.are.equal(0, fired_before_ding)
    assert.are.same({ "QUEST_ACCEPTED", "QUEST_LOG_UPDATE" }, names(E))
    assert.is_truthy(has_event(w, "grind"))
  end)

  it("does not grind for an under-levelled quest the character can't take anyway", function()
    local ctx, E, w = setup("Dwarf")
    local o = actions.perform(ctx, step("A", { 92009 }))
    assert.are.equal("refused", o.kind)
    assert.are.equal("race", o.reason)
    assert.is_nil(o.grind)
    assert.are.equal(1, w.player.level)
    assert.are.equal(0, E.updates)
  end)

  it("acts on the first id of a multi-QID step (QID|179^180)", function()
    local ctx, E, w = setup()
    local o = actions.perform(ctx, step("A", { 179, 180 }))
    assert.are.equal(179, o.qid)
    assert.is_truthy(w.log:get(179))
    assert.is_nil(w.log:get(180))
    assert.are.same({ "QUEST_ACCEPTED", 1, 179 }, E.fired[1])
  end)

  it("accepts the first allowed id of a multi-QID step (QID|Human-only^any for a Dwarf)", function()
    local ctx, E, w = setup("Dwarf")
    local o = actions.perform(ctx, step("A", { 92001, 180 }))
    assert.are.equal("acted", o.kind)
    assert.is_nil(o.reason)
    assert.are.equal(180, o.qid)
    assert.is_nil(w.log:get(92001))
    assert.are.same({ "QUEST_ACCEPTED", 1, 180 }, E.fired[1])
  end)

  it("returns the first id's reason when every listed id is refused", function()
    local ctx, E, w = setup("Dwarf")
    local o = actions.perform(ctx, step("A", { 92001, 92006 }))
    assert.are.equal("refused", o.kind)
    assert.are.equal("race", o.reason)
    assert.are.equal(92001, o.qid)
    assert.are.same({}, E.fired)
  end)

  it("prefers an id acceptable now over one that needs a grind", function()
    local ctx, E, w = setup("Dwarf")
    local o = actions.perform(ctx, step("A", { 92002, 180 }))
    assert.are.equal(180, o.qid)
    assert.is_nil(o.grind)
    assert.are.equal(1, w.player.level)
  end)

  it("grinds for the first id refused only for level when no id is acceptable now", function()
    local ctx, E, w = setup("Dwarf")
    local o = actions.perform(ctx, step("A", { 92009, 92002 }))
    assert.are.equal("acted", o.kind)
    assert.are.equal(92002, o.qid)
    assert.are.equal(3, o.grind.to)
    assert.is_truthy(w.log:get(92002))
  end)

  it("is a noop for an already-held quest", function()
    local ctx, E = setup()
    actions.perform(ctx, step("A", { 179 }))
    E.fired = {}
    local o = actions.perform(ctx, step("A", { 179 }))
    assert.are.equal("noop", o.kind)
    assert.are.equal("already-in-log", o.reason)
    assert.are.same({}, E.fired)
  end)
end)

describe("actions.perform: C/K", function()
  it("completes only the QO objective (QO|2|) and credits its kill XP", function()
    local ctx, E, w = setup()
    actions.perform(ctx, step("A", { 92003 }))
    E.fired = {}
    local o = actions.perform(ctx, step("C", { 92003 }, { questtext = "2" }))
    assert.are.equal("acted", o.kind)
    local e = w.log:get(92003)
    assert.are.same({ 0, 6 }, e.have)
    assert.is_true(w.player.xp > 0 or w.player.level > 1)
    assert.are.same({ "QUEST_LOG_UPDATE" }, names(E))
  end)

  it("progresses a QO|1>k| objective only to the target", function()
    local ctx, E, w = setup()
    actions.perform(ctx, step("A", { 92008 }))
    actions.perform(ctx, step("C", { 92008 }, { questtext = "1>3" }))
    assert.are.same({ 3 }, w.log:get(92008).have)
    assert.are.equal(3, w.player.bags[5002])
  end)

  it("completes every objective without QO", function()
    local ctx, E, w = setup()
    actions.perform(ctx, step("A", { 92003 }))
    actions.perform(ctx, step("K", { 92003 }))
    assert.is_true(w.log:is_complete(92003))
  end)

  it("adds the items of an item objective, credits drop-kill XP and fires BAG_UPDATE(0)", function()
    local ctx, E, w = setup()
    actions.perform(ctx, step("A", { 179 }))
    E.fired, E.updates = {}, 0
    local o = actions.perform(ctx, step("C", { 179 }))
    assert.are.equal(2, w.player.bags[5001])
    assert.is_true(w.log:is_complete(179))
    assert.is_true(w.player.level > 1 or w.player.xp > 0)
    assert.are.same({ "QUEST_LOG_UPDATE", "BAG_UPDATE" }, names(E))
    assert.are.same({ "BAG_UPDATE", 0 }, E.fired[2])
    -- 2 pelts at a 0.5 drop rate from a level 5 mob: enough kills (60 XP each) to ding
    assert.is_true(o.levels > 0)
    assert.is_true(E.updates >= 1)
  end)

  it("flags a step tagged ELITE, and not an ordinary one", function()
    local ctx = setup()
    actions.perform(ctx, step("A", { 92003 }))
    assert.is_true(actions.perform(ctx, step("C", { 92003 }, { questtext = "1", elite = true })).elite)
    assert.is_false(actions.perform(ctx, step("C", { 92003 }, { questtext = "2" })).elite)
  end)

  it("refuses not-in-log and fires nothing", function()
    local ctx, E = setup()
    local o = actions.perform(ctx, step("C", { 92003 }))
    assert.are.equal("refused", o.kind)
    assert.are.equal("not-in-log", o.reason)
    assert.are.same({}, E.fired)
  end)

  it("credits levels from kill XP with an update_guide call", function()
    local ctx, E, w = setup()
    actions.perform(ctx, step("A", { 92003 }))
    E.updates = 0
    local o = actions.perform(ctx, step("C", { 92003 }))
    -- 8 kills of level 5-6 mobs at 60 XP each at level 1 is more than 400 XP
    assert.is_true(o.levels > 0)
    assert.is_true(E.updates >= 1)
  end)
end)

describe("actions.perform: T", function()
  it("refuses an incomplete turn-in and fires nothing", function()
    local ctx, E, w = setup()
    actions.perform(ctx, step("A", { 92005 }))
    E.fired = {}
    local o = actions.perform(ctx, step("T", { 92005 }))
    assert.are.equal("refused", o.kind)
    assert.are.equal("incomplete", o.reason)
    assert.are.same({}, E.fired)
    assert.is_truthy(w.log:get(92005))
  end)

  it("refuses a turn-in of a quest not in the log", function()
    local ctx, E = setup()
    local o = actions.perform(ctx, step("T", { 92005 }))
    assert.are.equal("not-in-log", o.reason)
    assert.are.same({}, E.fired)
  end)

  it("turns in with QUEST_TURNED_IN(qid, xp, 0), QUEST_LOG_UPDATE under a complete dialog", function()
    local ctx, E, w = setup()
    actions.perform(ctx, step("A", { 180 }))
    E.fired = {}
    local seen
    local fire = E.fire
    function E:fire(event, ...) if event == "QUEST_TURNED_IN" then seen = w.dialog end; fire(self, event, ...) end
    local o = actions.perform(ctx, step("T", { 180 }))
    assert.are.equal("acted", o.kind)
    assert.are.same({ "QUEST_TURNED_IN", "QUEST_LOG_UPDATE" }, names(E))
    assert.are.same({ "QUEST_TURNED_IN", 180, 80, 0 }, E.fired[1])
    assert.are.same({ qid = 180, kind = "complete" }, seen)
    assert.is_nil(w.dialog)
    assert.is_nil(w.log:get(180))
  end)

  it("calls update_guide when the turn-in gains a level", function()
    local ctx, E, w = setup()
    actions.perform(ctx, step("A", { 92004 }))
    E.updates = 0
    local o = actions.perform(ctx, step("T", { 92004 }))
    assert.is_true(o.levels > 0)
    assert.is_true(w.player.level > 1)
    assert.is_true(E.updates >= 1)
  end)

  it("acts on the listed id that is in the log for a multi-QID turn-in", function()
    local ctx, E, w = setup()
    actions.perform(ctx, step("A", { 180 }))
    local o = actions.perform(ctx, step("T", { 179, 180 }))
    assert.are.equal("acted", o.kind)
    assert.are.equal(180, o.qid)
  end)
end)

describe("actions.perform: Camping 101", function()
  it("leaves Camping 101: First Aid in the log without First Aid", function()
    local ctx, E, w = setup()
    local o = actions.perform(ctx, step("A", { 1002 }))
    assert.are.equal("acted", o.kind)
    assert.is_truthy(w.log:get(1002))
    assert.is_nil(has_event(w, "abstracted-turnin"))
    assert.are.same({ "QUEST_ACCEPTED", "QUEST_LOG_UPDATE" }, names(E))
  end)

  it("turns Camping 101: First Aid in at once with First Aid, as an abstracted-turnin", function()
    local ctx, E, w = setup()
    w.player:learn_skill("First Aid", 1, 75)
    local o = actions.perform(ctx, step("A", { 1002 }))
    assert.are.equal("acted", o.kind)
    assert.is_nil(w.log:get(1002))
    assert.is_true(w.log.history[1002])
    assert.are.equal(1002, has_event(w, "abstracted-turnin").id)
    assert.are.same({ "QUEST_ACCEPTED", "QUEST_LOG_UPDATE", "QUEST_TURNED_IN", "QUEST_LOG_UPDATE" }, names(E))
    assert.are.same(names(E), o.events)
    assert.are.equal(1, E.settles)
  end)

  it("keeps it in the log when the guide has a T step for its QID", function()
    local guide = { step("A", { 1002 }), step("T", { 1002 }) }
    local ctx, E, w = setup(nil, guide)
    w.player:learn_skill("First Aid", 1, 75)
    actions.perform(ctx, guide[1])
    assert.is_truthy(w.log:get(1002))
    assert.is_nil(has_event(w, "abstracted-turnin"))
  end)

  it("turns Camping 101: Cooking in at once without a T step, training nothing", function()
    local ctx, E, w = setup()
    local o = actions.perform(ctx, step("A", { 1009 }))
    assert.are.equal("acted", o.kind)
    assert.is_true(w.log.history[1009])
    assert.is_false(w.player:knows_skill("Cooking"))
    assert.is_nil(has_event(w, "learn_skill"))
    assert.are.equal(1009, has_event(w, "abstracted-turnin").id)
    assert.are.same({ "QUEST_ACCEPTED", "QUEST_LOG_UPDATE", "QUEST_TURNED_IN", "QUEST_LOG_UPDATE" }, names(E))
  end)

  it("records no abstracted-turnin when the turn-in is refused, leaving the quest in the log", function()
    local ctx, E, w = setup()
    w.player:learn_skill("First Aid", 1, 75)
    function w.log.turn_in() return false, "requires-skill" end
    local o = actions.perform(ctx, step("A", { 1002 }))
    assert.are.equal("acted", o.kind)
    assert.are.equal("requires-skill", o.reason)
    assert.is_truthy(w.log:get(1002))
    assert.is_nil(has_event(w, "abstracted-turnin"))
    assert.are.same({ "QUEST_ACCEPTED", "QUEST_LOG_UPDATE" }, names(E))
    assert.is_nil(w.dialog)
  end)

  it("learns Cooking and completes Camping 101: Cooking on its C step", function()
    local guide = { step("A", { 1009 }), step("C", { 1009 }), step("T", { 1009 }) }
    local ctx, E, w = setup(nil, guide)
    actions.perform(ctx, guide[1])
    assert.is_truthy(w.log:get(1009))
    E.fired = {}
    local o = actions.perform(ctx, guide[2])
    assert.are.equal("acted", o.kind)
    assert.is_true(w.player:knows_skill("Cooking"))
    assert.is_true(w.log:is_complete(1009))
    assert.are.same({ "SKILL_LINES_CHANGED", "QUEST_LOG_UPDATE" }, names(E))
    assert.are.equal("acted", actions.perform(ctx, guide[3]).kind)
  end)
end)

describe("actions.perform: other actions", function()
  it("is a noop for a non-quest action, settling once", function()
    local ctx, E = setup()
    local o = actions.perform(ctx, step("N", {}))
    assert.are.equal("noop", o.kind)
    assert.are.same({}, E.fired)
    assert.are.equal(1, E.settles)
  end)
end)
