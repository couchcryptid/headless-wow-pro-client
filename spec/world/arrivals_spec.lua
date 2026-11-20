local arrivals = require("hwc.world.arrivals")
local catalog = require("hwc.catalog")
local Player = require("hwc.world.player")

local FOREVER = "spec/fixtures/forever/installed"

local function cat_with(npcs, over)
  local c = { questie_source = dofile("spec/fixtures/catalog/questie_source.lua"), forever_dir = FOREVER }
  for k, v in pairs(over or {}) do c[k] = v end
  local cat = catalog.load({ catalog = c, class = "WARRIOR", faction = "Alliance" })
  if npcs then
    local real = cat.questie
    cat.questie = setmetatable({ npc = function(_, id) return npcs[id] or real:npc(id) end },
      { __index = real })
  end
  return cat
end

local function inn(over)
  local e = { npc = 1572, bind = "Thelsamar", zone = "Loch Modan", subzone = "Thelsamar",
    map_id = 1432, x = 34, y = 51, checked = "user, 2026-11-19: in game" }
  for k, v in pairs(over or {}) do e[k] = v end
  return e
end

describe("arrivals data", function()
  -- false = known to start with no node (user, 2026-11-19: Skyborne's hub Valanaar has
  -- no flight master); nil would be unknown (start-node-unknown).
  it("names a capital node for every race but Skyborne, which start with none", function()
    for key in pairs(Player.RACES) do
      if key:find("^Skyborne") then
        assert.is_false(arrivals.start_nodes[key], key)
      else
        assert.is_string(arrivals.start_nodes[key], key)
      end
    end
    assert.are.equal("Stormwind, Elwynn", arrivals.start_nodes.Human)
  end)

  it("ships the other lists empty and a taxi_map note", function()
    assert.same({}, arrivals.subzones)
    assert.same({}, arrivals.inns)
    assert.same({}, arrivals.crossings)
    assert.same({}, arrivals.start_bind)
    assert.is_true(arrivals.taxi_map.lists_undiscovered)
    assert.are.equal("unverified", arrivals.taxi_map.checked)
  end)
end)

-- Every shipped first-party fact must pass arrivals.problem: an entry hwc would refuse at
-- run time must fail here first. The lists ship empty today, so this guards later captures.
describe("shipped arrival facts", function()
  it("every shipped subzone, inn, crossing and start_bind entry is usable", function()
    local bad = {}
    local function check(kind, key, entry)
      local why = arrivals.problem(kind, entry)
      if why then bad[#bad + 1] = kind .. " " .. tostring(key) .. ": " .. why end
    end
    for name, e in pairs(arrivals.subzones) do check("subzone", name, e) end
    for i, e in ipairs(arrivals.inns) do check("inn", i, e) end
    for i, e in ipairs(arrivals.crossings) do check("crossing", i, e) end
    for race, e in pairs(arrivals.start_bind) do check("start_bind", race, e) end
    assert.same({}, bad)
  end)
end)

describe("arrivals.problem", function()
  it("accepts a complete inn", function()
    assert.is_nil(arrivals.problem("inn", inn()))
  end)

  it("rejects an inn without checked", function()
    assert.is_string(arrivals.problem("inn", inn { checked = false }))
    assert.is_string(arrivals.problem("inn", inn { checked = "" }))
  end)

  it("rejects a missing or non-numeric field", function()
    assert.is_string(arrivals.problem("inn", inn { npc = false }))
    assert.is_string(arrivals.problem("inn", inn { x = "34" }))
    assert.is_string(arrivals.problem("inn", inn { zone = false }))
  end)

  it("validates the other kinds and rejects an unknown one", function()
    assert.is_nil(arrivals.problem("subzone", { subzone = "Thelsamar", checked = "x" }))
    assert.is_string(arrivals.problem("subzone", { subzone = "Thelsamar" }))
    local FROM = { map_id = 1, x = 1, y = 2 }
    assert.is_nil(arrivals.problem("crossing",
      { kind = "boat", from = FROM, zone = "Z", subzone = "S", map_id = 1, x = 1, y = 2, checked = "x" }))
    assert.is_string(arrivals.problem("crossing",
      { kind = "ferry", from = FROM, zone = "Z", subzone = "S", map_id = 1, x = 1, y = 2, checked = "x" }))
    assert.is_nil(arrivals.problem("start_bind",
      { bind = "B", zone = "Z", subzone = "S", map_id = 1, x = 1, y = 2, checked = "x" }))
    assert.is_string(arrivals.problem("nope", {}))
  end)

  -- Spec section 6: a boat or portal is found by its departure, a teleport by its spell.
  it("needs from for a boat or portal and spell for a teleport", function()
    local function crossing(over)
      local e = { kind = "boat", zone = "Z", subzone = "S", map_id = 1, x = 1, y = 2, checked = "x" }
      for k, v in pairs(over) do e[k] = v end
      return e
    end
    assert.is_string(arrivals.problem("crossing", crossing({})))
    assert.is_string(arrivals.problem("crossing", crossing({ kind = "portal" })))
    assert.is_string(arrivals.problem("crossing", crossing({ from = { map_id = 1, x = "1", y = 2 } })))
    assert.is_nil(arrivals.problem("crossing", crossing({ kind = "portal", from = { map_id = 1, x = 1, y = 2 } })))
    assert.is_string(arrivals.problem("crossing", crossing({ kind = "teleport" })))
    assert.is_nil(arrivals.problem("crossing", crossing({ kind = "teleport", spell = 3561 })))
  end)

  -- GetSubZoneText() legitimately returns "" where no subzone applies.
  it("accepts an empty subzone but not a missing one", function()
    assert.is_nil(arrivals.problem("subzone", { subzone = "", checked = "x" }))
    assert.is_string(arrivals.problem("subzone", { checked = "x" }))
    assert.is_nil(arrivals.problem("inn", inn { subzone = "" }))
    assert.is_string(arrivals.problem("inn", inn { subzone = false }))
    assert.is_nil(arrivals.problem("start_bind",
      { bind = "B", zone = "Z", subzone = "", map_id = 1, x = 1, y = 2, checked = "x" }))
  end)
end)

describe("Catalog:arrival_problems", function()
  local good = { start_nodes = { Human = "Stormwind, Elwynn" }, inns = {} }

  it("is empty when everything agrees", function()
    local cat = cat_with({ [9001] = { name = "Innkeeper", npcFlags = 128 + 1, spawns = { [38] = { { 34, 51 } } } } })
    assert.same({}, cat:arrival_problems({ start_nodes = good.start_nodes, inns = { inn { npc = 9001 } } }))
  end)

  it("skips a race that starts with no node (false)", function()
    assert.same({}, cat_with():arrival_problems({ start_nodes = { SkyborneHorde = false, Human = "Stormwind, Elwynn" }, inns = {} }))
  end)

  it("flags an unknown start node", function()
    local probs = cat_with():arrival_problems({ start_nodes = { Human = "Nowhere, Elwynn" }, inns = {} })
    assert.are.equal(1, #probs)
    assert.is_truthy(probs[1].key:find("start_nodes", 1, true))
    assert.is_truthy(probs[1].detail:find("Nowhere, Elwynn", 1, true))
  end)

  it("flags a mislabelled innkeeper", function()
    local probs = cat_with():arrival_problems({ start_nodes = good.start_nodes, inns = { inn() } })
    assert.are.equal(1, #probs)
    assert.is_truthy(probs[1].detail:find("innkeeper", 1, true))
  end)

  it("flags an inn npc QuestieDB doesn't know", function()
    local probs = cat_with():arrival_problems({ start_nodes = good.start_nodes, inns = { inn { npc = 987654 } } })
    assert.are.equal(1, #probs)
    assert.are.equal("inns[1]", probs[1].key)
    assert.is_truthy(probs[1].detail:find("not in QuestieDB", 1, true))
  end)

  it("flags an inn whose QuestieDB map differs", function()
    local cat = cat_with({ [9001] = { name = "Innkeeper", npcFlags = 128, spawns = { [38] = { { 34, 51 } } } } })
    local probs = cat:arrival_problems({ start_nodes = good.start_nodes, inns = { inn { npc = 9001, map_id = 1429 } } })
    assert.are.equal(1, #probs)
    assert.is_truthy(probs[1].detail:find("map", 1, true))
  end)

  it("is empty without QuestieDB or without the tables", function()
    local bad = { start_nodes = { Human = "Nowhere, Elwynn" }, inns = { inn() } }
    assert.same({}, cat_with(nil, { forever_dir = "spec/fixtures/forever/nope" }):arrival_problems(bad))
    local no_q = cat_with()
    no_q.questie = nil
    assert.same({}, no_q:arrival_problems(bad))
  end)

  it("defaults to the shipped arrivals table", function()
    assert.is_table(cat_with():arrival_problems())
  end)
end)
