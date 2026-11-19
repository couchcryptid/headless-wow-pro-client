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
  it("names a capital node for every non-Skyborne race, and leaves Skyborne out", function()
    for key in pairs(Player.RACES) do
      if key:find("^Skyborne") then
        assert.is_nil(arrivals.start_nodes[key])
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
    assert.is_nil(arrivals.problem("crossing",
      { kind = "boat", zone = "Z", subzone = "S", map_id = 1, x = 1, y = 2, checked = "x" }))
    assert.is_string(arrivals.problem("crossing",
      { kind = "ferry", zone = "Z", subzone = "S", map_id = 1, x = 1, y = 2, checked = "x" }))
    assert.is_nil(arrivals.problem("start_bind",
      { bind = "B", zone = "Z", subzone = "S", map_id = 1, x = 1, y = 2, checked = "x" }))
    assert.is_string(arrivals.problem("nope", {}))
  end)
end)

describe("Catalog:arrival_problems", function()
  local good = { start_nodes = { Human = "Stormwind, Elwynn" }, inns = {} }

  it("is empty when everything agrees", function()
    local cat = cat_with({ [9001] = { name = "Innkeeper", npcFlags = 128 + 1, spawns = { [38] = { { 34, 51 } } } } })
    assert.same({}, cat:arrival_problems({ start_nodes = good.start_nodes, inns = { inn { npc = 9001 } } }))
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
