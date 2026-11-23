-- Travel, item, use, level and training steps (design spec §5.2) and the
-- EXPECTED_MANUAL split, against the shared fake engine and a real World.
local actions = require("hwc.driver.actions")
local F = dofile("spec/helpers/driver_fixtures.lua")
local step, setup, names = F.step, F.setup, F.names
local core = require("hwc.stubs.core")

-- b and P land at first-party crossing facts (spec section 6), passed through the world
-- (cfg.arrivals), not hwc.world.arrivals. Positions in the facts are percent.
local function facts(crossings)
  return { start_nodes = { Dwarf = "Ironforge, Dun Morogh" }, start_bind = {}, subzones = {}, crossings = crossings }
end
local DOCK = { map_id = 1432, x = 50, y = 50 }
local ARRIVALS = facts({
  { kind = "boat", from = DOCK, zone = "The Barrens", subzone = "Ratchet", map_id = 1413, x = 63.2, y = 37.1, checked = "spec" },
})

describe("actions.perform: travel", function()
  it("R moves the player (zone, map, x/y from M / 100) and fires the zone events", function()
    local ctx, E, w = setup()
    local o = actions.perform(ctx, step("R", {}, { zone = "1426; Dun Morogh", map = "46.74,53.87" }, "Kharanos"))
    assert.are.equal("acted", o.kind)
    local p = w.player
    assert.are.same({ "Dun Morogh", "", 1426 }, { p.zone, p.subzone, p.map_id })
    assert.are.equal(0.4674, p.x)
    assert.are.equal(0.5387, p.y)
    assert.are.same({ "ZONE_CHANGED_NEW_AREA", "ZONE_CHANGED" }, names(E))
    assert.are.same(names(E), o.events)
    assert.are.equal(1, E.settles)
  end)

  it("takes the first coordinate of a multi-point M and accepts a bare map id Z", function()
    local ctx, E, w = setup()
    actions.perform(ctx, step("R", {}, { zone = "1455", map = "10.5, 20;30,40" }))
    assert.are.equal(1455, w.player.map_id)
    assert.are.equal(ctx.world.catalog.forever:zone_of_map(1455), w.player.zone)
    assert.are.equal(0.105, w.player.x)
    assert.are.equal(0.2, w.player.y)
  end)

  it("R without M (or M|PLAYER|) keeps the previous x/y", function()
    local ctx, E, w = setup()
    local x, y = w.player.x, w.player.y
    actions.perform(ctx, step("R", {}, { zone = "1426; Dun Morogh" }))
    assert.are.same({ x, y }, { w.player.x, w.player.y })
    actions.perform(ctx, step("R", {}, { zone = "1426; Dun Morogh", map = "PLAYER" }))
    assert.are.same({ x, y }, { w.player.x, w.player.y })
  end)

  it("b and P fire only the zone events", function()
    local ctx, E = setup("Dwarf", nil, { arrivals = ARRIVALS })
    actions.perform(ctx, step("b", {}, { zone = "1455; Ironforge", map = "10,10" }, "Darkshore"))
    assert.are.same({ "ZONE_CHANGED_NEW_AREA", "ZONE_CHANGED" }, names(E)) -- the departure only: no candidate
    E.fired = {}
    actions.perform(ctx, step("b", {}, { zone = "1432; Loch Modan", map = "50,50" }, "Wetlands"))
    assert.are.same({ "ZONE_CHANGED_NEW_AREA", "ZONE_CHANGED", "ZONE_CHANGED_NEW_AREA", "ZONE_CHANGED" }, names(E))
  end)
end)

local function has_event(list, v)
  for _, x in ipairs(list) do if x == v then return true end end
  return false
end
local INN = { npc = 1, bind = "Kharanos", zone = "Dun Morogh", subzone = "Thunderbrew Distillery", map_id = 1426, x = 46.8, y = 53.9, checked = "spec" }
local FAR_INN = { npc = 2, bind = "Ironforge", zone = "Ironforge", subzone = "The Commons", map_id = 1455, x = 18, y = 51, checked = "spec" }
local function inn_facts(inns)
  local f = facts({})
  f.inns = inns
  return f
end

describe("actions.perform: h and H", function()
  it("h binds at the nearest inn: GetBindLocation is the captured bind, not the step name", function()
    local ctx, E, w = setup("Dwarf", nil, { arrivals = inn_facts({ FAR_INN, INN }) })
    local o = actions.perform(ctx, step("h", {}, { zone = "1426; Dun Morogh", map = "47,54" }, "Some Inn Step"))
    assert.are.equal("acted", o.kind)
    assert.are.equal(INN, w.player.bind.entry)
    assert.are.equal("Kharanos", w.player.bind.name)
    assert.is_nil(o.data_gap)
    assert.are.same({ "ZONE_CHANGED_NEW_AREA", "ZONE_CHANGED", "HEARTHSTONE_BOUND" }, names(E)) -- departure, then the bind
  end)

  it("h with no inn within reach is inn-unknown and binds nothing", function()
    local ctx, E, w = setup("Dwarf", nil, { arrivals = inn_facts({ FAR_INN }) })
    local o = actions.perform(ctx, step("h", {}, { zone = "1426; Dun Morogh", map = "47,54" }, "Kharanos"))
    assert.are.equal("inn-unknown", o.data_gap.reason)
    assert.is_nil(w.player.bind)
    assert.is_false(has_event(names(E), "HEARTHSTONE_BOUND"))
  end)

  it("H lands at the bound inn", function()
    local ctx, E, w = setup("Dwarf", nil, { arrivals = inn_facts({ INN }) })
    w.player:set_bind(INN)
    w.player:set_zone("Ironforge", "", 1455, 0.2, 0.5)
    local o = actions.perform(ctx, step("H", {}, {}, "Kharanos"))
    assert.are.equal("acted", o.kind)
    local p = w.player
    assert.are.same({ "Dun Morogh", "Thunderbrew Distillery", 1426 }, { p.zone, p.subzone, p.map_id })
    assert.are.near(0.468, p.x, 1e-9)
    assert.are.near(0.539, p.y, 1e-9)
    assert.are.same({ zone = "Dun Morogh", subzone = "Thunderbrew Distillery", map_id = 1426 }, o.arrived)
    assert.are.same({ "ZONE_CHANGED_NEW_AREA", "ZONE_CHANGED" }, names(E))
  end)

  it("H with no inn entry is inn-unknown, keyed by the step when there is no bind", function()
    local ctx, E, w = setup("Dwarf", nil, { arrivals = inn_facts({}) })
    w.player:set_zone("Ironforge", "", 1455, 0.2, 0.5)
    local s = step("H", {}, { zone = "1426; Dun Morogh" }, "Kharanos")
    s.gid, s.line = "G1", 9
    local o = actions.perform(ctx, s)
    assert.are.same({ reason = "inn-unknown", key = "G1:9" }, o.data_gap)
    assert.are.same({ "Ironforge", 1455 }, { w.player.zone, w.player.map_id })
    assert.are.same({}, names(E))
  end)
end)

describe("actions.perform: R arrival", function()
  it("R no longer sets the subzone to the step name", function()
    local ctx, _, w = setup()
    actions.perform(ctx, step("R", {}, { zone = "1426; Dun Morogh", map = "46.74,53.87" }, "Kharanos"))
    assert.are.equal("", w.player.subzone)
    -- same zone and map: the subzone is kept
    w.player:set_zone("Dun Morogh", "Anvilmar", 1426, 0.1, 0.1)
    local o = actions.perform(ctx, step("R", {}, { zone = "1426; Dun Morogh" }, "Kharanos"))
    assert.are.equal("Anvilmar", w.player.subzone)
    -- The kept subzone is a previous landing's, not this step's: never reported as arrived.
    assert.are.same({ zone = "Dun Morogh", map_id = 1426 }, o.arrived)
  end)

  -- Spec section 7: a stalled R is name-not-an-area or subzone-unknown, never a mismatch
  -- judged against a subzone some earlier step left behind.
  it("R that keeps a stale subzone classifies subzone-unknown, never subzone-known", function()
    local ctx, _, w = setup()
    w.player:set_zone("Dun Morogh", "Anvilmar", 1426, 0.1, 0.1)
    local o = actions.perform(ctx, step("R", {}, { zone = "1426; Dun Morogh" }, "Ironforge"))
    assert.are.equal("Anvilmar", w.player.subzone) -- the addon still sees the kept subzone
    assert.is_nil(o.arrived.subzone)
    assert.are.equal("subzone-unknown", o.classify)
  end)

  -- Ruling: the Z name is the guide's text (the step being judged); the map id names the
  -- zone through the Forever tables when they are installed.
  it("R and a walked-to step take the zone name from the map id, not the Z text, with the tables", function()
    local ctx, _, w = setup()
    actions.perform(ctx, step("R", {}, { zone = "1453; Stormwind" }, "x"))
    assert.are.equal("Stormwind City", w.player.zone)
    ctx, _, w = setup()
    actions.perform(ctx, step("N", {}, { zone = "1453; Stormwind", map = "50,50" }))
    assert.are.equal("Stormwind City", w.player.zone)
    -- A map the tables don't name falls back to the Z text.
    ctx, _, w = setup()
    actions.perform(ctx, step("R", {}, { zone = "1431; Duskwood" }, "x"))
    assert.are.same({ "Duskwood", 1431 }, { w.player.zone, w.player.map_id })
  end)

  it("R and a walked-to step use the Z text without the tables", function()
    local ctx, _, w = setup("Dwarf", nil, { forever = false })
    actions.perform(ctx, step("R", {}, { zone = "1453; Stormwind" }, "x"))
    assert.are.equal("Stormwind", w.player.zone)
    ctx, _, w = setup("Dwarf", nil, { forever = false })
    actions.perform(ctx, step("N", {}, { zone = "1453; Stormwind", map = "50,50" }))
    assert.are.equal("Stormwind", w.player.zone)
  end)

  it("R with a numeric-only Z takes the zone name from the map", function()
    local ctx, _, w = setup()
    actions.perform(ctx, step("R", {}, { zone = "1455" }, "x"))
    assert.are.equal(ctx.world.catalog.forever:zone_of_map(1455), w.player.zone)
  end)

  it("R with CC carries waypoint-arrival-not-emulated", function()
    local ctx = setup()
    local s = step("R", {}, { zone = "1426; Dun Morogh", waypcomplete = 1 }, "Kharanos")
    s.gid, s.line = "G", 7
    local o = actions.perform(ctx, s)
    assert.are.same({ reason = "waypoint-arrival-not-emulated", key = "G:7" }, o.data_gap)
    local o0 = actions.perform(ctx, step("R", {}, { zone = "1426; Dun Morogh", waypcomplete = 0 }, "Kharanos"))
    assert.is_nil(o0.data_gap)
  end)

  it("R named after a non-area classifies name-not-an-area", function()
    local ctx = setup()
    local o = actions.perform(ctx, step("R", {}, { zone = "1426; Dun Morogh" }, "Walk to the cave quickly"))
    assert.are.equal("name-not-an-area", o.classify)
  end)
end)

-- A run-to step that names a quest objective (01_12_Dun_Morogh.lua:158, R Secure the
-- Mountain|ACTIVE|98319|QO|1|): in game, reaching the place credits the objective.
-- Progress only, no kill XP: the NPC objective is a body or person to find. Most
-- `R ...|QO|n` steps instead mean "head there; stay up until objective n is done", with
-- later steps doing the work (01_12_Dun_Morogh.lua:209 Shimmer Ridge before the C step
-- that loots Shimmerweed; :214 Frostmane Hold before the C steps that kill
-- Headhunters). So arrival credits an objective only when it is not an item objective
-- and no other step of the loaded guide works on it.
describe("actions.perform: R credits its QO objectives", function()
  it("credits the named NPC objective of a quest in the log, with no XP", function()
    local ctx, E, w = setup()
    actions.perform(ctx, step("A", { 92011 }))
    local xp, level = w.player.xp, w.player.level
    E.fired = {}
    local o = actions.perform(ctx, step("R", { 92011 }, { zone = "1426; Dun Morogh", questtext = "1" }, "Body"))
    assert.are.equal("acted", o.kind)
    assert.are.same({ 1 }, w.log:haves(92011))
    assert.is_true(w.log:is_complete(92011))
    assert.are.same({ xp, level }, { w.player.xp, w.player.level })
    assert.are.equal(0, o.levels)
    assert.are.same({ 1 }, o.arrivals)
    assert.are.same({ "ZONE_CHANGED_NEW_AREA", "ZONE_CHANGED", "QUEST_LOG_UPDATE" }, names(E))
  end)

  it("credits Mountaineer Cornelius (npc 278166, quest 98319) when no other step covers it", function()
    -- 01_12_Dun_Morogh.lua:153/158/161: A, R ...|ACTIVE|98319|QO|1|, T; nothing else works on 98319.
    local guide = {
      { index = 1, action = "A", name = "Secure the Mountain", qids = { 98319 }, tags = {} },
      { index = 2, action = "C", name = "Flintfire's Shipment", qids = { 98321 }, tags = {} },
      { index = 3, action = "R", name = "Secure the Mountain", qids = { 98319 },
        tags = { active = "98319", questtext = "1" } },
      { index = 4, action = "T", name = "Secure the Mountain", qids = { 98319 }, tags = {} },
    }
    local ctx, _, w = setup(nil, guide)
    actions.perform(ctx, guide[1])
    local o = actions.perform(ctx, guide[3])
    assert.are.same({ 1 }, w.log:haves(98319))
    assert.are.same({ 1 }, o.arrivals)
  end)

  it("progresses only up to what the QO part asks", function()
    local ctx, _, w = setup()
    actions.perform(ctx, step("A", { 92003 }))
    actions.perform(ctx, step("R", { 92003 }, { questtext = "2>3" }))
    assert.are.same({ 0, 3 }, w.log:haves(92003))
  end)

  it("does not credit an item objective: arrival loots nothing", function()
    local ctx, E, w = setup()
    actions.perform(ctx, step("A", { 92008 }))
    E.fired = {}
    local o = actions.perform(ctx, step("R", { 92008 }, { questtext = "1>3" }))
    assert.are.same({ 0 }, w.log:haves(92008))
    assert.is_nil(w.player.bags[5002])
    assert.are.same({}, o.arrivals)
    assert.are.same({ "ZONE_CHANGED_NEW_AREA", "ZONE_CHANGED" }, names(E))
  end)

  -- The R step under test is index 1 of the loaded guide; `other` is index 2.
  local function covered(other, qid, qo)
    local r = { index = 1, action = "R", name = "There", qids = { qid },
      tags = { active = tostring(qid), questtext = qo or "1" } }
    other.index = 2
    other.tags = other.tags or {}
    local ctx, _, w = setup(nil, { r, other })
    actions.perform(ctx, step("A", { qid }))
    local o = actions.perform(ctx, r)
    return w.log:haves(qid), o
  end

  for _, action in ipairs({ "C", "K", "U", "l", "B" }) do
    it("does not credit an objective when a " .. action .. " step of the guide has that QID, whatever its QO", function()
      local haves, o = covered({ action = action, name = "Work", qids = { 92011 }, tags = { questtext = "2" } }, 92011)
      assert.are.same({ 0 }, haves)
      assert.are.same({}, o.arrivals)
    end)
  end

  it("does not credit an objective another ACTIVE step names by QO", function()
    local haves = covered({ action = "L", name = "Grind", qids = { 92011 },
      tags = { active = "92011", questtext = "1" } }, 92011)
    assert.are.same({ 0 }, haves)
  end)

  it("does not credit an objective of a quest another step is ACTIVE on without a QO", function()
    -- 01_12_Dun_Morogh.lua:219 L Level 10|ACTIVE|319|: an ACTIVE-only step stays up for the whole quest.
    local haves = covered({ action = "L", name = "Grind", qids = {}, tags = { active = "92011" } }, 92011)
    assert.are.same({ 0 }, haves)
  end)

  it("still credits an objective when another ACTIVE step names only other objectives", function()
    local haves, o = covered({ action = "L", name = "Grind", qids = { 92003 },
      tags = { active = "92003", questtext = "1" } }, 92003, "2")
    assert.are.same({ 0, 6 }, haves)
    assert.are.same({ 2 }, o.arrivals)
  end)

  it("credits nothing without a QO", function()
    local ctx, E, w = setup()
    actions.perform(ctx, step("A", { 92011 }))
    E.fired = {}
    actions.perform(ctx, step("R", { 92011 }, { zone = "1426; Dun Morogh" }, "Body"))
    assert.are.same({ 0 }, w.log:haves(92011))
    assert.are.same({ "ZONE_CHANGED_NEW_AREA", "ZONE_CHANGED" }, names(E))
  end)

  it("credits nothing, without error, for a quest not in the log", function()
    local ctx, E, w = setup()
    local o = actions.perform(ctx, step("R", { 92011 }, { zone = "1426; Dun Morogh", questtext = "1" }, "Body"))
    assert.are.equal("acted", o.kind)
    assert.is_nil(w.log:get(92011))
    assert.are.same({ "ZONE_CHANGED_NEW_AREA", "ZONE_CHANGED" }, names(E))
  end)
end)

-- Travel-location fix (spec §5.1 "position = the step's M coordinate when it has
-- one"): a player walks to every step's Z/M, so a non-travel step with a Z or M
-- moves the player there before acting. Without this a later travel step to the
-- same place completes on the engine's "already there" check without being acted on.
describe("actions.perform: walking to each step", function()
  it("an A step with Z/M moves the player there, subzone cleared, before accepting", function()
    local ctx, E, w = setup()
    w.player:set_zone("Stormwind City", "Stormwind", 1453, 0.5, 0.5)
    local o = actions.perform(ctx, step("A", { 179 }, { zone = "1426; Dun Morogh", map = "46.74,53.87" }))
    assert.are.equal("acted", o.kind)
    local p = w.player
    assert.are.same({ "Dun Morogh", "", 1426, 0.4674, 0.5387 }, { p.zone, p.subzone, p.map_id, p.x, p.y })
    assert.are.same({ "ZONE_CHANGED_NEW_AREA", "ZONE_CHANGED", "QUEST_ACCEPTED", "QUEST_LOG_UPDATE" }, names(E))
  end)

  it("a later b to the same place is not already there after walking elsewhere", function()
    local ctx, E, w = setup("Dwarf", nil, { arrivals = ARRIVALS })
    actions.perform(ctx, step("b", {}, { zone = "1432; Loch Modan", map = "50,50" }, "Ratchet"))
    assert.are.equal("Ratchet", w.player.subzone)
    actions.perform(ctx, step("N", {}, { zone = "1426; Dun Morogh", map = "30,70" }))
    -- AutoCompleteZone matches the step name or TZ against zone/subzone text, or TZ's map id
    -- (WoWPro_AutoComplete.lua:513-526): none of them matches the b step any more.
    local p = w.player
    assert.are_not.equal("Ratchet", p.subzone)
    assert.are_not.equal("The Barrens", p.zone)
    assert.are_not.equal(1413, p.map_id)
  end)

  it("a step with only M moves x/y within the current zone and keeps the subzone", function()
    local ctx, E, w = setup()
    w.player:set_zone("Dun Morogh", "Kharanos", 1426, 0.1, 0.1)
    actions.perform(ctx, step("N", {}, { map = "47.3,52.5" }))
    assert.are.same({ "Dun Morogh", "Kharanos", 1426, 0.473, 0.525 }, { w.player.zone, w.player.subzone, w.player.map_id, w.player.x, w.player.y })
  end)

  it("no Z/M, M|PLAYER| or the current spot: no move and no zone events", function()
    local ctx, E, w = setup()
    w.player:set_zone("Dun Morogh", "Kharanos", 1426, 0.4674, 0.5387)
    actions.perform(ctx, step("N", {}, {}))
    actions.perform(ctx, step("N", {}, { map = "PLAYER" }))
    actions.perform(ctx, step("N", {}, { zone = "1426; Dun Morogh", map = "46.74,53.87" }))
    assert.are.equal("Kharanos", w.player.subzone)
    assert.are.same({}, E.fired)
  end)
end)

describe("actions.perform: items", function()
  it("l adds the L item with its count and fires BAG_UPDATE(0)", function()
    local ctx, E, w = setup()
    local o = actions.perform(ctx, step("l", {}, { lootitem = { [2894] = 2 } }))
    assert.are.equal("acted", o.kind)
    assert.are.equal(2, w.player:item_count(2894))
    assert.are.same({ "BAG_UPDATE", 0 }, E.fired[1])
    assert.are.equal(1, #E.fired)
  end)

  it("parses the raw string form 'id count' and defaults the count to 1", function()
    local ctx, E, w = setup()
    actions.perform(ctx, step("B", {}, { lootitem = "2894 2;750" }))
    assert.are.equal(2, w.player:item_count(2894))
    assert.are.equal(1, w.player:item_count(750))
    assert.are.equal(1, #E.fired)
  end)

  it("adds the L item of a C step even when it is no catalog objective, after the step's rule", function()
    local ctx, E, w = setup()
    actions.perform(ctx, step("A", { 92005 }))
    E.fired = {}
    local o = actions.perform(ctx, step("C", { 92005 }, { lootitem = { [7777] = 1 } }))
    assert.are.equal("acted", o.kind)
    assert.are.equal(1, w.player:item_count(7777))
    assert.are.same({ "QUEST_LOG_UPDATE", "BAG_UPDATE" }, names(E))
  end)

  it("U adds a missing use item, completes QO and consumes the item", function()
    local ctx, E, w = setup()
    actions.perform(ctx, step("A", { 92005 }))
    E.fired = {}
    local o = actions.perform(ctx, step("U", { 92005 }, { use = "9999", questtext = "1" }))
    assert.are.equal("acted", o.kind)
    assert.is_true(w.log:is_complete(92005))
    assert.are.equal(0, w.player:item_count(9999))
    assert.are.same({ "BAG_UPDATE", 0 }, E.fired[1])
    assert.are.same({ "BAG_UPDATE", "QUEST_LOG_UPDATE", "BAG_UPDATE" }, o.events)
  end)

  it("U keeps the use item when it is also the L item", function()
    local ctx, E, w = setup()
    actions.perform(ctx, step("A", { 92005 }))
    actions.perform(ctx, step("U", { 92005 }, { use = "9999", questtext = "1", lootitem = { [9999] = 1 } }))
    assert.are.equal(1, w.player:item_count(9999))
  end)

  it("U without a quest in the log only ensures the item", function()
    local ctx, E, w = setup()
    local o = actions.perform(ctx, step("U", {}, { use = "9999" }))
    assert.are.equal("acted", o.kind)
    assert.are.equal(1, w.player:item_count(9999))
    assert.are.same({ { "BAG_UPDATE", 0 } }, E.fired)
  end)
end)

describe("actions.perform: L tag top-up (Ruling L)", function()
  it("a C step on an item-objective quest with the same L item gives exactly the count, one BAG_UPDATE", function()
    local ctx, E, w = setup()
    actions.perform(ctx, step("A", { 179 }))
    E.fired = {}
    local o = actions.perform(ctx, step("C", { 179 }, { lootitem = { [5001] = 2 } }))
    assert.are.equal(2, w.player:item_count(5001))
    local bags = 0
    for _, e in ipairs(names(E)) do if e == "BAG_UPDATE" then bags = bags + 1 end end
    assert.are.equal(1, bags)
    assert.are.equal("acted", o.kind)
  end)

  it("a repeated l step with the item already held adds nothing and fires nothing", function()
    local ctx, E, w = setup()
    actions.perform(ctx, step("l", {}, { lootitem = { [2894] = 2 } }))
    E.fired = {}
    local o = actions.perform(ctx, step("l", {}, { lootitem = { [2894] = 2 } }))
    assert.are.equal(2, w.player:item_count(2894))
    assert.are.same({}, E.fired)
    assert.are.equal("noop", o.kind)
  end)
end)

describe("actions.perform: level and training", function()
  it("L with LVL|4 grinds to 4 and updates the guide", function()
    local ctx, E, w = setup()
    local o = actions.perform(ctx, step("L", {}, { level = "4" }))
    assert.are.equal("acted", o.kind)
    assert.are.equal(4, w.player.level)
    assert.are.equal(3, o.levels)
    assert.is_true(E.updates >= 1)
    assert.are.equal(4, o.level_grind.to)
  end)

  it("any step with LVL|n above the player's level grinds; at or above is a noop", function()
    local ctx, E, w = setup()
    actions.perform(ctx, step("N", {}, { level = "3" }))
    assert.are.equal(3, w.player.level)
    E.updates = 0
    local o = actions.perform(ctx, step("N", {}, { level = "3" }))
    assert.are.equal("noop", o.kind)
    assert.are.equal(0, E.updates)
  end)

  it("LVL|2;-650 at level 2 with 900 to go grinds to within 650 of the next level", function()
    local ctx, _, w = setup()
    w.player.level, w.player.xp = 2, 0
    local o = actions.perform(ctx, step("L", {}, { level = "2;-650" }))
    assert.are.equal("acted", o.kind)
    assert.is_true(o.level_grind.kills > 0)
    assert.are.equal(2, o.level_grind.to)
    assert.are.equal(2, w.player.level)
    assert.is_true(w.player:xp_max() - w.player.xp <= 650)
  end)

  it("records the gap in levels, from the real XP before the grind, on a level-check grind", function()
    local ctx, _, w = setup()
    w.player.level, w.player.xp = 1, 324 -- level 1.81
    local o = actions.perform(ctx, step("L", {}, { level = "2;-650" }))
    -- The check point is level 2 + 250/900 (900 to go minus 650); the gap is 0.47 from 1.81.
    assert.are.equal(0.5, o.level_grind.short)
    assert.are.equal(-650, o.level_grind.offset)
    local ctx2, _, w2 = setup()
    local o2 = actions.perform(ctx2, step("L", {}, { level = "4" }))
    assert.are.equal(3.0, o2.level_grind.short)
    assert.are.equal(0, o2.level_grind.offset)
    assert.are.equal(4, w2.player.level)
  end)

  it("LVL|2;-650 with 400 to go does not grind", function()
    local ctx, _, w = setup()
    w.player.level = 2
    w.player.xp = w.player:xp_max() - 400
    local o = actions.perform(ctx, step("L", {}, { level = "2;-650" }))
    assert.is_nil(o.level_grind)
    assert.are.equal("noop", o.kind)
  end)

  it("LVL|2;-650 at level 3 does not grind", function()
    local ctx, _, w = setup()
    w.player.level, w.player.xp = 3, 0
    local o = actions.perform(ctx, step("L", {}, { level = "2;-650" }))
    assert.is_nil(o.level_grind)
    assert.are.equal(3, w.player.level)
  end)

  it("LVL|5;300 at level 5 with 100 XP grinds to at least 300 XP", function()
    local ctx, E, w = setup()
    w.player.level, w.player.xp = 5, 100
    local o = actions.perform(ctx, step("L", {}, { level = "5;300" }))
    assert.is_true(o.level_grind.kills > 0)
    assert.is_true(w.player.level > 5 or w.player.xp >= 300)
    assert.is_true(E.updates >= 1)
  end)

  it("a non-L step with an offset LVL tag never grinds (WoWPro completes it at the point)", function()
    local ctx, _, w = setup()
    w.player.level, w.player.xp = 2, 0
    local o = actions.perform(ctx, step("R", {}, { level = "5;-495" }))
    assert.is_nil(o.level_grind)
    assert.are.equal(2, w.player.level)
    assert.are.equal(0, w.player.xp)
    o = actions.perform(ctx, step("N", {}, { level = "2;-650" }))
    assert.is_nil(o.level_grind)
    assert.are.equal(0, w.player.xp)
  end)

  it("LVL|60;-500 at the cap does not error and grinds nothing", function()
    local ctx, _, w = setup()
    w.player.level, w.player.xp = 60, 0
    local o
    assert.has_no.errors(function() o = actions.perform(ctx, step("L", {}, { level = "60;-500" })) end)
    assert.is_nil(o.level_grind)
    assert.are.equal("noop", o.kind)
  end)

  it("LVL|60;-500 below the cap grinds to the cap without error", function()
    local ctx, _, w = setup()
    w.player.level, w.player.xp = 59, 0
    local o
    assert.has_no.errors(function() o = actions.perform(ctx, step("L", {}, { level = "60;-500" })) end)
    assert.are.equal(60, w.player.level)
    assert.are.equal(0, o.level_grind.point)
  end)

  it("= with a P tag trains the profession, firing SKILL_LINES_CHANGED and SPELLS_CHANGED", function()
    local ctx, E, w = setup()
    local o = actions.perform(ctx, step("=", {}, { prof = "Engineering;202" }))
    assert.are.equal("acted", o.kind)
    assert.is_true(w.player:knows_skill("Engineering"))
    assert.are.same({ "TRAINER_SHOW", "TRAINER_CLOSED", "SKILL_LINES_CHANGED", "SPELLS_CHANGED" }, names(E))
  end)

  it("a SPELL tag learns the spell id; a known one is a noop", function()
    local ctx, E, w = setup()
    -- Flip (third field) only picks the engine's skip direction (Broker.lua:3332); the driver ignores it.
    local t = { spell = "First Aid; 3273" }
    local o = actions.perform(ctx, step("A", {}, t))
    assert.are.equal("acted", o.kind)
    assert.is_true(w.player.spells[3273])
    local cfg = require("hwc.config").load({ race = "Dwarf", class = "WARRIOR" })
    local sb = require("hwc.sandbox").new(cfg)
    core.install(sb, cfg)
    sb.world = w
    assert.is_true(sb.env.IsPlayerSpell("3273"))
    assert.are.same({ "SKILL_LINES_CHANGED", "SPELLS_CHANGED" }, names(E))
    E.fired = {}
    -- A tag-only step (an A with no QID does nothing itself) shows that the SPELL tag
    -- teaches nothing once the spell is known; = can't show it, it always opens the trainer.
    assert.are.equal("noop", actions.perform(ctx, step("A", {}, t)).kind)
    assert.are.same({}, E.fired)
  end)

  -- A player at a trainer opens the trainer window; the engine completes the first
  -- visible = row on TRAINER_SHOW (WoWPro_Events.lua:809-811, AutoCompleteTrain at
  -- WoWPro_AutoComplete.lua:199-210). Class training teaches no tracked skill.
  it("= (class training) opens and closes the trainer window and learns nothing", function()
    local ctx, E, w = setup()
    local o = actions.perform(ctx, step("=", {}, { note = "Manually check this step off." }, "Level 2 Training"))
    assert.are.equal("acted", o.kind)
    assert.are.same({ "TRAINER_SHOW", "TRAINER_CLOSED" }, names(E))
    assert.are.same({}, w.player.skills)
  end)
end)

describe("actions.perform: noops and EXPECTED_MANUAL", function()
  it("N, D, r, t and unknown actions are noops", function()
    local ctx, E = setup()
    for _, a in ipairs({ "N", "D", "r", "t", "Q" }) do
      assert.are.equal("noop", actions.perform(ctx, step(a, {})).kind)
    end
    assert.are.same({}, E.fired)
  end)

  -- Final review minor 3: `*` steps trash an item.
  it("a * step is expected manual and drops the item it names from the bags", function()
    assert.is_true(actions.EXPECTED_MANUAL["*"])
    local ctx, E, w = setup()
    w.player:add_item(5001, 3)
    local o = actions.perform(ctx, step("*", {}, {}, "Fixture Pelt"))
    assert.are.equal("acted", o.kind)
    assert.are.equal(0, w.player:item_count(5001))
    assert.are.same({ "BAG_UPDATE" }, names(E))
    E.fired = {}
    assert.are.equal("noop", actions.perform(ctx, step("*", {}, {}, "Nothing Held")).kind)
    assert.are.same({}, names(E))
  end)

  it("EXPECTED_MANUAL names N, D and r; = is not (opening the trainer completes it)", function()
    assert.is_true(actions.EXPECTED_MANUAL["N"])
    assert.is_true(actions.EXPECTED_MANUAL["D"])
    assert.is_nil(actions.EXPECTED_MANUAL["="])
    assert.is_true(actions.EXPECTED_MANUAL["r"])
    assert.is_nil(actions.EXPECTED_MANUAL["C"])
  end)

  it("expects_manual also matches a note saying 'Manually check this step off'", function()
    assert.is_true(actions.expects_manual(step("C", {}, { note = "Do it.\n...Manually check this step off." })))
    assert.is_true(actions.expects_manual(step("N", {})))
    assert.is_false(actions.expects_manual(step("C", {}, { note = "Kill things" })))
  end)
end)

describe("actions.perform: multi-QID A (Ruling J)", function()
  it("is a noop when any listed id is already in the log, never accepting an alternative", function()
    local ctx, E, w = setup()
    actions.perform(ctx, step("A", { 179 }))
    E.fired = {}
    local o = actions.perform(ctx, step("A", { 179, 180 }))
    assert.are.equal("noop", o.kind)
    assert.are.equal("already-in-log", o.reason)
    assert.is_nil(w.log:get(180))
    assert.are.same({}, E.fired)
  end)

  it("is a noop already-completed when any listed id is completed", function()
    local ctx, E, w = setup()
    actions.perform(ctx, step("A", { 92004 }))
    actions.perform(ctx, step("T", { 92004 }))
    E.fired = {}
    local o = actions.perform(ctx, step("A", { 92004, 180 }))
    assert.are.equal("noop", o.kind)
    assert.are.equal("already-completed", o.reason)
    assert.is_nil(w.log:get(180))
  end)
end)

-- F and f on the Forever tables (arrival emulation spec sections 4, 5, 8, 9). The fixture
-- tables put Stormwind (1453), Ironforge (1455) and Thelsamar (1432) on Eastern Kingdoms;
-- a Dwarf starts knowing Ironforge.
describe("actions.perform: flights", function()
  local IRONFORGE = { zone = "1455; Ironforge", map = "55.9,47.9" }

  -- The fake engine runs no addon: on TAXIMAP_OPENED, take the node AutoSelect would, as
  -- WoWPro.TakeTaxiClassic does (WoWPro_AutoComplete.lua:32-53): the first listed node
  -- whose location (text before the comma) contains the step name, or whose name equals it.
  -- It also notes UnitOnTaxi at each event.
  local function autoselect(E, w, dest)
    local fire = E.fire
    E.on_taxi = {}
    function E:fire(event, ...)
      fire(self, event, ...)
      E.on_taxi[#E.on_taxi + 1] = w.player.on_taxi
      if event ~= "TAXIMAP_OPENED" then return end
      local db, p = w.catalog.forever, w.player
      for _, n in ipairs(db:taxi_nodes(db:continent_of(p.map_id), p.faction)) do
        local location = n.name:match("^([^,]*)")
        if location:find(dest, 1, true) or n.name == dest then
          self.sb.taxi_taken[#self.sb.taxi_taken + 1] = n.name
          return
        end
      end
    end
  end

  local function fly(dest, tags, opts)
    local ctx, E, w = setup("Dwarf", nil, opts)
    if not (opts and opts.forever == false) then autoselect(E, w, dest) end
    local t = {}
    for k, v in pairs(IRONFORGE) do t[k] = v end
    for k, v in pairs(tags or {}) do t[k] = v end
    return ctx, E, w, t
  end

  it("F Stormwind with a learned node flies: control lost, on taxi, lands in Stormwind City, control gained; subzone is not 'Stormwind'", function()
    local ctx, E, w, tags = fly("Stormwind")
    local p = w.player
    p:learn_flight_point("Stormwind, Elwynn")
    local node = w.catalog.forever:node("Stormwind, Elwynn")
    local o = actions.perform(ctx, step("F", {}, tags, "Stormwind"))
    assert.are.equal("acted", o.kind)
    assert.are.same({ "ZONE_CHANGED_NEW_AREA", "ZONE_CHANGED", -- the departure (spec section 8)
      "TAXIMAP_OPENED", "PLAYER_CONTROL_LOST",
      "ZONE_CHANGED_NEW_AREA", "ZONE_CHANGED", "PLAYER_CONTROL_GAINED" }, names(E))
    assert.are.same(names(E), o.events)
    -- On the taxi from the control loss until the landing.
    assert.are.same({ false, false, false, true, false, false, false }, E.on_taxi)
    assert.are.same({ "Stormwind City", "", 1453, node.x, node.y }, { p.zone, p.subzone, p.map_id, p.x, p.y })
    assert.is_false(p.on_taxi)
    assert.are.same({ name = "Stormwind", tz = nil }, o.named)
    assert.are.same({ zone = "Stormwind City", map_id = 1453 }, o.arrived) -- subzone not captured
    assert.are.equal("name-not-an-area", o.classify)
    assert.is_nil(o.reason)
    assert.is_nil(o.data_gap)
    assert.is_nil(o.resolved_by)
    -- TAXIMAP_OPENED, past PLAYER_CONTROL_LOST, then the end of perform.
    assert.are.equal(3, E.settles)
  end)

  it("F lands in the node's captured subzone, and out.settle ORs hit_limit across settles", function()
    local arrivals = { start_nodes = { Dwarf = "Ironforge, Dun Morogh" }, start_bind = {}, subzones = {
      ["Stormwind, Elwynn"] = { subzone = "Trade District", checked = "spec" } } }
    local ctx, E, w, tags = fly("Stormwind", { targetzone = "Trade District" }, { arrivals = arrivals })
    w.player:learn_flight_point("Stormwind, Elwynn")
    local n = 0
    function E:settle()
      n = n + 1
      self.settles = n
      return { ran = 0, now = n, hit_limit = n == 1 }
    end
    local o = actions.perform(ctx, step("F", {}, tags, "Stormwind"))
    assert.are.equal("Trade District", w.player.subzone)
    assert.are.same({ zone = "Stormwind City", subzone = "Trade District", map_id = 1453 }, o.arrived)
    assert.are.equal("advances", o.classify)
    assert.are.same({ ran = 0, now = 3, hit_limit = true }, o.settle)
  end)

  it("F to an undiscovered node is flight-point-undiscovered and lands by the loose match without learning it", function()
    local ctx, E, w, tags = fly("Thelsamar")
    local p = w.player
    local o = actions.perform(ctx, step("F", {}, tags, "Thelsamar"))
    assert.are.equal("acted", o.kind)
    assert.are.equal("flight-point-undiscovered", o.reason)
    assert.is_nil(o.data_gap)
    assert.are.same({ "Thelsamar, Loch Modan" }, E.sb.taxi_taken)
    assert.are.same({ "ZONE_CHANGED_NEW_AREA", "ZONE_CHANGED", "TAXIMAP_OPENED",
      "ZONE_CHANGED_NEW_AREA", "ZONE_CHANGED" }, names(E))
    assert.are.same({ "Loch Modan", "", 1432 }, { p.zone, p.subzone, p.map_id })
    assert.is_nil(p.flight_points["Thelsamar, Loch Modan"])
    assert.are.equal("loose", o.resolved_by)
    assert.are.same({ zone = "Loch Modan", map_id = 1432 }, o.arrived)
    assert.are.equal("subzone-unknown", o.classify) -- Thelsamar is an area; the subzone isn't captured
    assert.are.equal(2, E.settles)
  end)

  it("F to an undiscovered node is a notice when hwc's knowledge is incomplete", function()
    local ctx, _, w, tags = fly("Thelsamar")
    w.start_node_unknown = true
    w.fp_unknown[1415] = true
    local o = actions.perform(ctx, step("F", {}, tags, "Thelsamar"))
    assert.are.same({ reason = "start-node-unknown", key = "Dwarf" }, o.data_gap)
    ctx, _, w, tags = fly("Thelsamar")
    w.fp_unknown[1415] = true
    o = actions.perform(ctx, step("F", {}, tags, "Thelsamar"))
    assert.are.same({ reason = "fp-unknown", key = "1415" }, o.data_gap)
    assert.are.equal("flight-point-undiscovered", o.reason)
    assert.are.equal("Loch Modan", w.player.zone) -- still arrives (spec section 9)
  end)

  it("F naming no node is no-taxi-node", function()
    -- The loose match still finds the zone: the player arrives there.
    local ctx, E, w, tags = fly("Loch Modan")
    local o = actions.perform(ctx, step("F", {}, tags, "Loch Modan"))
    assert.are.equal("no-taxi-node", o.reason)
    assert.are.same({}, E.sb.taxi_taken)
    assert.are.equal("loose", o.resolved_by)
    assert.are.same({ "Loch Modan", 1432 }, { w.player.zone, w.player.map_id })
    assert.are.equal("advances", o.classify)
    -- Nothing matches: destination-unresolved, and the player stays at the departure.
    ctx, E, w, tags = fly("Darnassus")
    o = actions.perform(ctx, step("F", {}, tags, "Darnassus"))
    assert.are.equal("no-taxi-node", o.reason)
    assert.are.same({}, E.sb.taxi_taken)
    assert.are.same({ reason = "destination-unresolved", key = "Darnassus" }, o.data_gap)
    assert.are.same({ "Ironforge", 1455 }, { w.player.zone, w.player.map_id })
    assert.is_nil(o.arrived)
    assert.is_nil(o.classify)
    assert.are.same({ name = "Darnassus" }, o.named)
  end)

  -- Ruling R12: a listed node whose location contains the step name is one the addon's
  -- TakeTaxiClassic would have taken; nothing taken means the addon never tried (the row
  -- wasn't active, or AutoSelect is off), which is no guide finding.
  it("F with a matching listed node that nothing took is taxi-not-taken, not no-taxi-node", function()
    local ctx, E, w, tags = fly("Thelsamar")
    E.fire = function(self, event, ...) self.fired[#self.fired + 1] = { event, ... } end -- no AutoSelect
    local s = step("F", {}, tags, "Thelsamar")
    s.gid, s.line = "G1", 42
    local o = actions.perform(ctx, s)
    assert.is_nil(o.reason)
    assert.are.same({ reason = "taxi-not-taken", key = "G1:42" }, o.data_gap)
    assert.are.same({}, E.sb.taxi_taken)
    assert.are.equal("Loch Modan", w.player.zone) -- still arrives (spec section 9)
  end)

  it("F with a matching node the taxi map doesn't list is no-taxi-node", function()
    local arrivals = { start_nodes = { Dwarf = "Ironforge, Dun Morogh" }, start_bind = {}, subzones = {},
      taxi_map = { lists_undiscovered = false } }
    local ctx, E, w, tags = fly("Thelsamar", nil, { arrivals = arrivals })
    E.fire = function(self, event, ...) self.fired[#self.fired + 1] = { event, ... } end
    local o = actions.perform(ctx, step("F", {}, tags, "Thelsamar"))
    assert.are.equal("no-taxi-node", o.reason)
    assert.is_nil(o.data_gap)
  end)

  it("F with no tables is tables-missing and fires no taxi events", function()
    local ctx, E, w, tags = fly("Stormwind", nil, { forever = false })
    local o = actions.perform(ctx, step("F", {}, tags, "Stormwind"))
    assert.are.same({ reason = "tables-missing", key = "no-tables" }, o.data_gap)
    assert.are.same({ "ZONE_CHANGED_NEW_AREA", "ZONE_CHANGED" }, names(E)) -- the departure only
    assert.are.same({ "Ironforge", 1455 }, { w.player.zone, w.player.map_id })
    assert.are.same({ name = "Stormwind" }, o.named)
    assert.are.equal(1, E.settles)
  end)

  it("f learns the real node name nearest the departure and fires the discovery once", function()
    local ctx, E, w = setup("Dwarf")
    local o = actions.perform(ctx, step("f", {}, { zone = "1432; Loch Modan", map = "33.5,51" }, "Thelsamar"))
    assert.are.equal("acted", o.kind)
    assert.is_true(w.player.flight_points["Thelsamar, Loch Modan"])
    assert.is_nil(w.player.flight_points["Thelsamar"])
    -- Talking to the flight master discovers the node; the map is never opened (user,
    -- 2026-11-20: opening it is a separate choice from the flight master's screen).
    assert.are.same({ "ZONE_CHANGED_NEW_AREA", "ZONE_CHANGED", "UI_INFO_MESSAGE" }, names(E))
    assert.are.same({ "UI_INFO_MESSAGE", 0, core.ERR_NEWTAXIPATH }, E.fired[3])
    assert.is_nil(o.data_gap)
    assert.is_nil(o.reason)
  end)

  it("f for a known node fires nothing past the departure and is flight-point-already-known", function()
    local ctx, E, w = setup("Dwarf")
    local o = actions.perform(ctx, step("f", {}, IRONFORGE, "Ironforge"))
    assert.are.equal("acted", o.kind)
    assert.are.same({ "ZONE_CHANGED_NEW_AREA", "ZONE_CHANGED" }, names(E))
    assert.are.equal("flight-point-already-known", o.reason)
    assert.are.same({ name = "Ironforge, Dun Morogh" }, o.named)
    assert.is_nil(o.data_gap)
    assert.is_true(w.player.flight_points["Ironforge, Dun Morogh"])
  end)

  it("f with no node nearby is fp-unknown", function()
    local ctx, E, w = setup("Dwarf")
    local o = actions.perform(ctx, step("f", {}, { zone = "1432; Loch Modan", map = "80,80" }, "Thelsamar"))
    assert.are.same({ reason = "fp-unknown", key = "1432:80.0,80.0" }, o.data_gap)
    assert.is_true(w.fp_unknown[1415])
    assert.are.same({ "ZONE_CHANGED_NEW_AREA", "ZONE_CHANGED" }, names(E))
    assert.is_nil(w.player.flight_points["Thelsamar, Loch Modan"])
  end)

  -- A departure map the tables place on no continent (1431 isn't in the fixture tables):
  -- hwc can't list the taxi map, so nothing is the guide's fault but a name that is no
  -- area anywhere (spec section 3).
  it("F departing a map with no continent is arrival-unknown, with no guide reason", function()
    local ctx, E, w = setup("Dwarf")
    local s = step("F", {}, { zone = "1431; Duskwood", map = "77.5,44.3" }, "Ironforge")
    s.gid, s.line = "G1", 5
    local o = actions.perform(ctx, s)
    assert.is_nil(o.reason)
    assert.are.same({ reason = "arrival-unknown", key = "map:1431" }, o.data_gap)
    assert.are.same({ "ZONE_CHANGED_NEW_AREA", "ZONE_CHANGED" }, names(E)) -- the departure only
    assert.are.same({ 1431 }, { w.player.map_id })
    assert.is_nil(o.arrived)
    assert.are.same({}, E.sb.taxi_taken)
  end)

  it("F departing a map with no continent, named after no area, is name-not-an-area", function()
    local ctx = setup("Dwarf")
    local o = actions.perform(ctx, step("F", {}, { zone = "1431; Duskwood", map = "77.5,44.3" }, "Stormwind"))
    assert.is_nil(o.reason)
    assert.is_nil(o.data_gap)
    assert.are.equal("name-not-an-area", o.classify)
  end)

  it("f on a map with no continent is fp-unknown keyed by the map, and marks no continent", function()
    local ctx, _, w = setup("Dwarf")
    local o = actions.perform(ctx, step("f", {}, { zone = "1431; Duskwood", map = "77.5,44.3" }, "Darkshire"))
    assert.are.same({ reason = "fp-unknown", key = "map:1431" }, o.data_gap)
    assert.is_nil(next(w.fp_unknown))
  end)

  it("f with no tables is tables-missing and learns nothing", function()
    local ctx, E, w = setup("Dwarf", nil, { forever = false })
    local o = actions.perform(ctx, step("f", {}, { zone = "1432; Loch Modan", map = "33.5,51" }, "Thelsamar"))
    assert.are.same({ reason = "tables-missing", key = "no-tables" }, o.data_gap)
    assert.are.same({}, w.player.flight_points)
    assert.are.same({ "ZONE_CHANGED_NEW_AREA", "ZONE_CHANGED" }, names(E))
  end)
end)

describe("actions.perform: b and P", function()
  local DOCK_TAGS = { zone = "1432; Loch Modan", map = "50,50" }
  local TWO = facts({
    { kind = "boat", from = DOCK, zone = "Dun Morogh", subzone = "Kharanos", map_id = 1426, x = 30, y = 40, checked = "spec" },
    { kind = "boat", from = DOCK, zone = "The Barrens", subzone = "Ratchet", map_id = 1413, x = 63.2, y = 37.1, checked = "spec" },
  })

  it("b from a one-route dock lands at its real arrival", function()
    local ctx, E, w = setup("Dwarf", nil, { arrivals = ARRIVALS })
    local o = actions.perform(ctx, step("b", {}, DOCK_TAGS, "Ratchet"))
    local p = w.player
    assert.are.equal("acted", o.kind)
    assert.are.same({ "The Barrens", "Ratchet", 1413, 0.632, 0.371 }, { p.zone, p.subzone, p.map_id, p.x, p.y })
    assert.are.same({ "ZONE_CHANGED_NEW_AREA", "ZONE_CHANGED", "ZONE_CHANGED_NEW_AREA", "ZONE_CHANGED" }, names(E))
    assert.are.same({ zone = "The Barrens", subzone = "Ratchet", map_id = 1413 }, o.arrived)
    assert.are.same({ name = "Ratchet" }, o.named)
    assert.is_nil(o.data_gap)
    assert.is_nil(o.resolved_by)
  end)

  it("b from a two-route dock takes the route the step names exactly", function()
    local ctx, _, w = setup("Dwarf", nil, { arrivals = TWO })
    local o = actions.perform(ctx, step("b", {}, DOCK_TAGS, "Ratchet"))
    assert.are.same({ "The Barrens", "Ratchet" }, { w.player.zone, w.player.subzone })
    assert.is_nil(o.resolved_by)
    ctx, _, w = setup("Dwarf", nil, { arrivals = TWO })
    actions.perform(ctx, step("b", {}, { zone = "1432; Loch Modan", map = "50,50", targetzone = "1426" }, "Whatever"))
    assert.are.equal(1426, w.player.map_id)
  end)

  it("b matches the TZ's first part exactly, and sees every route within reach of the departure", function()
    local ctx, _, w = setup("Dwarf", nil, { arrivals = TWO })
    local o = actions.perform(ctx, step("b", {}, { zone = "1432; Loch Modan", map = "50,50", targetzone = "1413; The Barrens" }, "Whatever"))
    assert.are.equal(1413, w.player.map_id)
    assert.is_nil(o.resolved_by)
    assert.are.same({ name = "Whatever", tz = "1413; The Barrens" }, o.named)
    local near = facts({
      { kind = "boat", from = { map_id = 1432, x = 50, y = 50 }, zone = "Dun Morogh", subzone = "Kharanos", map_id = 1426, x = 30, y = 40, checked = "spec" },
      { kind = "boat", from = { map_id = 1432, x = 51, y = 50.5 }, zone = "The Barrens", subzone = "Ratchet", map_id = 1413, x = 63.2, y = 37.1, checked = "spec" },
    })
    ctx, _, w = setup("Dwarf", nil, { arrivals = near })
    o = actions.perform(ctx, step("b", {}, DOCK_TAGS, "Ratchet"))
    assert.are.equal(1413, w.player.map_id)
    assert.is_nil(o.resolved_by)
    ctx, _, w = setup("Dwarf", nil, { arrivals = near })
    actions.perform(ctx, step("b", {}, DOCK_TAGS, "Kharanos"))
    assert.are.equal(1426, w.player.map_id)
  end)

  it("b naming neither route lands by the loose match", function()
    local ctx, _, w = setup("Dwarf", nil, { arrivals = TWO })
    local o = actions.perform(ctx, step("b", {}, DOCK_TAGS, "Rat"))
    assert.are.equal("Ratchet", w.player.subzone)
    assert.are.equal("loose", o.resolved_by)
    ctx, _, w = setup("Dwarf", nil, { arrivals = TWO })
    o = actions.perform(ctx, step("b", {}, DOCK_TAGS, "Nowhere"))
    assert.are.same({ reason = "destination-unresolved", key = "Nowhere" }, o.data_gap)
    assert.are.equal(1432, w.player.map_id)
    assert.is_nil(o.arrived)
  end)

  it("b to another continent changes the continent the next F lists", function()
    local ctx, E, w = setup("Dwarf", nil, { arrivals = ARRIVALS })
    local p = w.player
    p.faction = "Horde"
    local db = w.catalog.forever
    -- The taxi map lists the player's continent (stubs.core taxi_nodes): Eastern Kingdoms first.
    assert.are_not.equal(1414, db:continent_of(1432))
    function E:fire(event, ...)
      self.fired[#self.fired + 1] = { event, ... }
      if event == "TAXIMAP_OPENED" then
        for _, n in ipairs(db:taxi_nodes(db:continent_of(p.map_id), p.faction)) do
          if n.name:find("Crossroads", 1, true) then self.sb.taxi_taken[#self.sb.taxi_taken + 1] = n.name end
        end
      end
    end
    actions.perform(ctx, step("b", {}, DOCK_TAGS, "Ratchet"))
    local o = actions.perform(ctx, step("F", {}, { zone = "1413; The Barrens", map = "63.2,37.1" }, "Crossroads"))
    assert.are.same({ "Crossroads, The Barrens" }, E.sb.taxi_taken)
    assert.are.equal("flight-point-undiscovered", o.reason) -- a real node, listed on Kalimdor
  end)

  it("P teleport lands at the known spell's destination", function()
    local arrivals = facts({
      { kind = "teleport", spell = 3561, zone = "Stormwind City", subzone = "Trade District", map_id = 1453, x = 49.5, y = 87.3, checked = "spec" },
      { kind = "teleport", spell = 3562, zone = "Ironforge", subzone = "The Great Forge", map_id = 1455, x = 27, y = 71, checked = "spec" },
    })
    local ctx, _, w = setup("Dwarf", nil, { arrivals = arrivals })
    w.player:learn_spell(3561)
    local o = actions.perform(ctx, step("P", {}, { zone = "1432; Loch Modan" }, "Stormwind City"))
    assert.are.same({ "Stormwind City", "Trade District", 1453, 0.495, 0.873 },
      { w.player.zone, w.player.subzone, w.player.map_id, w.player.x, w.player.y })
    assert.are.same({ zone = "Stormwind City", subzone = "Trade District", map_id = 1453 }, o.arrived)
    assert.are.equal("advances", o.classify)
    -- A spell the step names (SPELL tag) counts too.
    ctx, _, w = setup("Dwarf", nil, { arrivals = arrivals })
    actions.perform(ctx, step("P", {}, { zone = "1432; Loch Modan", spell = "Teleport: Ironforge; 3562" }, "Ironforge"))
    assert.are.equal(1455, w.player.map_id)
  end)

  it("b with no dock nearby is arrival-unknown, and the player stays", function()
    local ctx, _, w = setup("Dwarf", nil, { arrivals = ARRIVALS })
    local o = actions.perform(ctx, step("b", {}, { zone = "1455; Ironforge", map = "10,10" }, "Ratchet"))
    assert.are.same({ reason = "arrival-unknown", key = "b:1455:10.0,10.0" }, o.data_gap)
    assert.are.equal(1455, w.player.map_id)
    assert.is_nil(o.arrived)
    o = actions.perform(setup("Dwarf", nil, { arrivals = facts({}) }), step("P", {}, { zone = "1455; Ironforge", map = "10,10" }, "X"))
    assert.are.equal("P:1455:10.0,10.0", o.data_gap.key)
  end)

  it("lands without the Forever tables, unclassified", function()
    local ctx, _, w = setup("Dwarf", nil, { arrivals = ARRIVALS, forever = false })
    local o = actions.perform(ctx, step("b", {}, DOCK_TAGS, "Ratchet"))
    assert.are.equal(1413, w.player.map_id)
    assert.is_nil(o.classify)
    assert.is_nil(o.data_gap)
  end)
end)
