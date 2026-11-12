local config = require("hwc.config")
local sandbox = require("hwc.sandbox")
local stubs = require("hwc.stubs.core")
local World = require("hwc.world")

-- In-spec catalog stub: no dependence on git-ignored local data.
local QUESTS = {
  [179] = { id = 179, name = "A Dwarven Outfitters", level = 1, required_level = 1, xp = 80,
    objectives = { { kind = "item", ids = { 750 }, count = 8, text = "Tough Wolf Meat" } },
    pre_single = {}, pre_group = {} },
  [180] = { id = 180, name = "Needs Four", level = 4, required_level = 4, xp = 100, objectives = {}, pre_single = {}, pre_group = {} },
  [181] = { id = 181, name = "Camping", level = 1, required_level = 1, xp = 10, objectives = {}, requires_skill = "First Aid",
    pre_single = {}, pre_group = {} },
  [182] = { id = 182, name = "Orc Only", level = 1, required_level = 1, xp = 10, objectives = {}, races = { "Orc" }, pre_single = {}, pre_group = {} },
  [183] = { id = 183, name = "Mage Only", level = 1, required_level = 1, xp = 10, objectives = {}, classes = { "MAGE" }, pre_single = {}, pre_group = {} },
  [184] = { id = 184, name = "Needs Any", level = 1, required_level = 1, xp = 10, objectives = {}, pre_single = { 179, 181 }, pre_group = {} },
  [185] = { id = 185, name = "Needs All", level = 1, required_level = 1, xp = 10, objectives = {}, pre_single = {}, pre_group = { 179, 181 } },
  [186] = { id = 186, name = "Mob", level = 1, required_level = 1, xp = 0,
    objectives = { { kind = "npc", ids = { 1 }, count = 2, text = "Wolf slain" }, { kind = "object", ids = { 2 }, count = 1, text = "Chest" } },
    pre_single = {}, pre_group = {} },
}
for i = 1, 45 do
  QUESTS[1000 + i] = { id = 1000 + i, name = "Filler " .. i, level = 1, required_level = 1, xp = 0, objectives = {}, pre_single = {}, pre_group = {} }
end
local catalog = {
  quest = function(_, id) return QUESTS[id] end,
  placeholder = function(_, id, n)
    local o = {}
    for i = 1, n do o[i] = { kind = "other", count = 1, text = "Objective " .. i } end
    return { id = id, required_level = 1, xp = 0, objectives = o, pre_single = {}, pre_group = {} }
  end,
}

local function setup()
  local cfg = config.load({ race = "Dwarf", class = "WARRIOR" })
  local sb = sandbox.new(cfg)
  sb.world = World.new(cfg, catalog, sb.clock)
  stubs.install(sb, cfg)
  return sb, sb.env, sb.world
end

describe("QuestLog", function()
  it("refuses the 41st accept and changes nothing", function()
    local _, _, w = setup()
    for i = 1, 40 do assert.is_true(w.log:accept(1000 + i)) end
    local nevents = #w.events
    assert.same({ false, "log-full" }, { w.log:accept(1041) })
    assert.equal(40, #w.log:entries())
    assert.equal(nevents, #w.events)
    assert.same({}, w.log.history)
  end)

  it("keeps GetInfo indices dense after an abandon", function()
    local _, env, w = setup()
    w.log:accept(1001); w.log:accept(1002); w.log:accept(1003)
    assert.is_true(w.log:abandon(1002))
    assert.equal("Filler 1", env.C_QuestLog.GetInfo(1).title)
    assert.equal(1003, env.C_QuestLog.GetInfo(2).questID)
    assert.is_nil(env.C_QuestLog.GetInfo(3))
    assert.same({ 2, 2 }, { env.C_QuestLog.GetNumQuestLogEntries() })
    assert.is_false(env.C_QuestLog.GetInfo(1).isHeader)
  end)

  it("refuses by level, race, class and prerequisite", function()
    local _, _, w = setup()
    assert.same({ false, "below-level" }, { w.log:accept(180) })
    assert.same({ false, "race" }, { w.log:accept(182) })
    assert.same({ false, "class" }, { w.log:accept(183) })
    assert.same({ false, "prerequisite" }, { w.log:accept(184) })
    assert.same({ false, "prerequisite" }, { w.log:accept(185) })
    assert.same({ false, "unknown-quest" }, { w.log:accept(9) })
    assert.is_true(w.log:accept(179))
    assert.same({ false, "already-in-log" }, { w.log:accept(179) })
  end)

  it("checks pre_single (any) and pre_group (all) against history", function()
    local _, _, w = setup()
    w.log.history[181] = true
    assert.is_true(w.log:accept(184))
    assert.same({ false, "prerequisite" }, { w.log:accept(185) })
    w.log.history[179] = true
    assert.is_true(w.log:accept(185))
  end)

  it("refuses an already completed quest", function()
    local _, _, w = setup()
    w.log.history[179] = true
    assert.same({ false, "already-completed" }, { w.log:accept(179) })
  end)

  it("accepts a placeholder for an unknown quest", function()
    local _, env, w = setup()
    assert.is_true(w.log:accept(9, { placeholder_qo = 2 }))
    assert.equal(2, #env.C_QuestLog.GetQuestObjectives(9))
  end)

  it("reports objective progress through the API and clamps at the count", function()
    local _, env, w = setup()
    w.log:accept(179)
    assert.is_false(env.C_QuestLog.IsComplete(179))
    w.log:progress(179, 1, 20)
    assert.same({ { text = "Tough Wolf Meat: 8/8", type = "item", finished = true, numFulfilled = 8, numRequired = 8 } },
      env.C_QuestLog.GetQuestObjectives(179))
    assert.is_true(env.C_QuestLog.IsComplete(179))
    assert.same({ "Tough Wolf Meat: 8/8", "item", true }, { env.GetQuestLogLeaderBoard(1, 1) })
    assert.equal(1, env.GetNumQuestLeaderBoards(1))
  end)

  it("maps objective kinds and completes selected objectives", function()
    local _, env, w = setup()
    w.log:accept(186)
    w.log:complete_objectives(186, { 2 })
    local o = env.C_QuestLog.GetQuestObjectives(186)
    assert.same({ "monster", "object" }, { o[1].type, o[2].type })
    assert.same({ false, true }, { o[1].finished, o[2].finished })
    assert.is_false(w.log:is_complete(186))
    w.log:complete_objectives(186)
    assert.is_true(w.log:is_complete(186))
  end)

  it("turns in a quest for XP and records history", function()
    local _, env, w = setup()
    w.log:accept(179)
    assert.same({ false, "incomplete" }, { w.log:turn_in(179) })
    w.log:progress(179, 1, 8)
    assert.same({ true, nil, 80, 0 }, { w.log:turn_in(179) })
    assert.is_true(env.C_QuestLog.IsQuestFlaggedCompleted(179))
    assert.equal(0, #w.log:entries())
    assert.equal(80, w.player.xp)
    assert.same({ false, "not-in-log" }, { w.log:turn_in(179) })
  end)

  it("takes the collected objective items from the bags on turn-in", function()
    local _, env, w = setup()
    w.log:accept(179)
    w.log:progress(179, 1, 8)
    w.player:add_item(750, 8)
    assert.equal(8, env.GetItemCount(750))
    assert.is_true((w.log:turn_in(179)))
    assert.equal(0, env.GetItemCount(750))
    local last
    for _, e in ipairs(w.events) do if e.kind == "remove_item" then last = e end end
    assert.same({ 750, 8 }, { last.id, last.n })
  end)

  it("gates Camping turn-ins on the skill", function()
    local _, _, w = setup()
    w.log:accept(181)
    assert.same({ false, "requires-skill" }, { w.log:turn_in(181) })
    assert.equal(1, #w.log:entries())
    w.player:learn_skill("First Aid", 1, 75)
    assert.same({ true, nil, 10, 0 }, { w.log:turn_in(181) })
  end)

  it("records every change as an event", function()
    local _, _, w = setup()
    w.log:accept(179); w.log:progress(179, 1, 8); w.log:turn_in(179)
    local kinds = {}
    for _, e in ipairs(w.events) do kinds[#kinds + 1] = e.kind end
    assert.same({ "quest_accept", "quest_progress", "xp", "quest_turn_in" }, kinds)
  end)
end)
