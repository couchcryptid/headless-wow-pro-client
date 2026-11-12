local config = require("hwc.config")
local Player = require("hwc.world.player")
local xp = require("hwc.world.xp")
local kills = require("hwc.world.kills")

local function new_player()
  local events = {}
  local p = Player.new(config.load({ race = "Dwarf", class = "WARRIOR" }),
    function(kind, fields) events[#events + 1] = { kind = kind, fields = fields } end)
  return p, events
end

local function comb(n, k)
  local r = 1
  for i = 1, k do r = r * (n - k + i) / i end
  return r
end
local function p_at_least(n, k, p)
  local q = 0
  for i = 0, k - 1 do q = q + comb(n, i) * p ^ i * (1 - p) ^ (n - i) end
  return 1 - q
end

local npcs = {
  [10] = { id = 10, level_min = 5, level_max = 7, rank = 0, spawns = { [1] = { { 1, 1 }, { 2, 2 }, { 3, 3 }, { 4, 4 } } } },
  [11] = { id = 11, level_min = 8, level_max = 8, rank = 1, spawns = { [1] = { { 1, 1 } } } },
  [12] = { id = 12, level_min = 8, level_max = 8, rank = 1, spawns = { [1] = { { 1, 1 }, { 2, 2 }, { 3, 3 } } } },
  [13] = { id = 13, level_min = 30, level_max = 30, rank = 0, flags = 19, spawns = {} }, -- trainer: gossip+questgiver+trainer
  [14] = { id = 14, rank = 0, spawns = {} },                                              -- no level range
}
local items = {
  [100] = { drops = { { npc = 10, rate = 0.5 } } },
  [101] = { drops = { { npc = 11, rate = 0.1 }, { npc = 10, rate = 0.2 } } },  -- ordinary wins over elite
  [102] = { drops = { { npc = 11, rate = 0.3 } } },                              -- named elite: always drops
  [103] = { drops = { { npc = 12 } } },                                          -- unknown rate: count * 3
  [104] = { drops = {} },
  [105] = { drops = { { npc = 10, rate = 0.1 }, { npc = 10, rate = 0.4 } } },    -- highest rate
}
local catalog = {
  npc = function(_, id) return npcs[id] end,
  item = function(_, id) return items[id] end,
}

describe("kills.for_drop", function()
  it("returns needed for a certain drop", function()
    assert.equal(8, kills.for_drop(1, 8))
    assert.equal(8, kills.for_drop(0.9995, 8))
  end)
  it("finds the smallest n at 90% confidence", function()
    -- 1-0.5^3 = 0.875 < 0.9; 1-0.5^4 = 0.9375 >= 0.9
    assert.equal(4, kills.for_drop(0.5, 1))
    local n = kills.for_drop(0.35, 8)
    assert.is_true(p_at_least(n, 8, 0.35) >= 0.9)
    assert.is_true(p_at_least(n - 1, 8, 0.35) < 0.9)
  end)
end)

describe("kills.mob_level", function()
  it("floors the midpoint", function()
    assert.equal(6, kills.mob_level({ level_min = 5, level_max = 7 }))
    assert.equal(5, kills.mob_level({ level_min = 5, level_max = 6 }))
  end)
end)

describe("kills.objective_kills", function()
  it("npc objective: count kills of the first id", function()
    local k = kills.objective_kills(catalog, { kind = "npc", ids = { 10 }, count = 6 })
    assert.same({ npc_id = 10, level = 6, elite = false, count = 6 }, k)
  end)
  it("item objective uses for_drop on the source rate", function()
    local k = kills.objective_kills(catalog, { kind = "item", ids = { 100 }, count = 3 })
    assert.equal(10, k.npc_id)
    assert.equal(kills.for_drop(0.5, 3), k.count)
  end)
  it("prefers an ordinary mob over an elite", function()
    local k = kills.objective_kills(catalog, { kind = "item", ids = { 101 }, count = 1 })
    assert.equal(10, k.npc_id)
    assert.equal(kills.for_drop(0.2, 1), k.count)
  end)
  it("picks the highest known rate", function()
    local k = kills.objective_kills(catalog, { kind = "item", ids = { 105 }, count = 1 })
    assert.equal(kills.for_drop(0.4, 1), k.count)
  end)
  it("a named elite always drops and is flagged elite", function()
    local k = kills.objective_kills(catalog, { kind = "item", ids = { 102 }, count = 2 })
    assert.same({ npc_id = 11, level = 8, elite = true, count = 2 }, k)
  end)
  it("unknown rate gives count * 3", function()
    local k = kills.objective_kills(catalog, { kind = "item", ids = { 103 }, count = 2 })
    assert.equal(6, k.count)
  end)
  it("is nil for objects, missing items and no drop source", function()
    assert.is_nil(kills.objective_kills(catalog, { kind = "object", ids = { 1 }, count = 1 }))
    assert.is_nil(kills.objective_kills(catalog, { kind = "item", ids = { 104 }, count = 1 }))
    assert.is_nil(kills.objective_kills(catalog, { kind = "item", ids = { 999 }, count = 1 }))
    assert.is_nil(kills.objective_kills(catalog, { kind = "npc", ids = { 999 }, count = 1 }))
  end)
end)

-- Ruling AC: a talk-to NPC objective earns no kill XP. QuestieDB's objective groups
-- do not tell a talk-to from a kill for these quests (Forever's talk-to objectives
-- come from the Wowhead objectives file), so the heuristic applies.
describe("kills.objective_kills: talk-to NPCs", function()
  local quest = { starter = 15, ender = 16, starter_kind = "npc", ender_kind = "npc" }
  it("credits no kills for the quest's starter or ender NPC", function()
    local q = { starter = 10, starter_kind = "npc", ender = 11, ender_kind = "npc" }
    assert.is_nil(kills.objective_kills(catalog, { kind = "npc", ids = { 10 }, count = 1 }, q))
    assert.is_nil(kills.objective_kills(catalog, { kind = "npc", ids = { 11 }, count = 1 }, q))
  end)
  it("credits no kills for an NPC with no level range", function()
    assert.is_nil(kills.objective_kills(catalog, { kind = "npc", ids = { 14 }, count = 1 }, quest))
  end)
  it("credits no kills for a service NPC (QuestieDB npcFlags set: trainer, vendor, questgiver)", function()
    assert.is_nil(kills.objective_kills(catalog, { kind = "npc", ids = { 13 }, count = 1 }, quest))
  end)
  it("still credits an ordinary mob", function()
    assert.same({ npc_id = 10, level = 6, elite = false, count = 2 },
      kills.objective_kills(catalog, { kind = "npc", ids = { 10 }, count = 2 }, quest))
  end)
end)

describe("kills.credit", function()
  it("10 level-1 kills at level 1: 8 x 50 levels up, then 2 x 44 (brief said 500/100, which ignores the recompute)", function()
    local p = new_player()
    local gained_xp, levels = kills.credit(p, { level = 1, elite = false, count = 10 }, 1)
    assert.equal(488, gained_xp)  -- 400 + 2 x floor(55 * 4/5)
    assert.equal(1, levels)
    assert.equal(2, p.level)
    assert.equal(88, p.xp)
  end)
  it("doubles elites at party size 1", function()
    local p = new_player()
    local gained_xp = kills.credit(p, { level = 1, elite = true, count = 2 }, 1)
    assert.equal(200, gained_xp)  -- 2 x floor(50 * 2)
  end)
  it("recomputes per kill after a level-up", function()
    local p = new_player()
    p.xp = 350
    -- kill 1: 50 -> level 2 (xp 0). kill 2 at level 2 vs mob 1: 55 * (5-1)/5 = 44
    local gained_xp = kills.credit(p, { level = 1, elite = false, count = 2 }, 1)
    assert.equal(94, gained_xp)
    assert.equal(44, p.xp)
  end)
end)

describe("kills.grind_to", function()
  it("grinds level 1 to 3 with exact carry and minimal kills", function()
    local p, events = new_player()
    -- L1: 8 x 50 = 400 -> L2. L2: 55/kill, 900 needed -> 17 kills = 935, carry 35.
    local n, gained_xp, levels = kills.grind_to(p, 3)
    assert.equal(25, n)
    assert.equal(1335, gained_xp)
    assert.equal(2, levels)
    assert.equal(3, p.level)
    assert.equal(35, p.xp)
    local last = events[#events]
    assert.equal("grind", last.kind)
    assert.same({ to = 3, kills = 25 }, last.fields)
  end)
  it("does nothing when already at the target", function()
    local p = new_player()
    p.level = 5
    local n = kills.grind_to(p, 3)
    assert.equal(0, n)
  end)
  it("clamps an unreachable target to the cap", function()
    local p = new_player()
    p.level = xp.CAP_LEVEL - 1
    local n = kills.grind_to(p, 99)
    assert.is_true(n > 0)
    assert.equal(xp.CAP_LEVEL, p.level)
  end)
end)
