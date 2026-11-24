local db = require("hwc.forever.db")
local catalog = require("hwc.catalog")

local FIX = "spec/fixtures/forever/installed"

local function near(expected, actual) assert.is_true(math.abs(expected - actual) < 0.001, actual) end

describe("forever db", function()
  local d = assert(db.open(FIX))

  it("reports the installed build", function()
    assert.are.equal("1.60.1.70959", d.build)
  end)

  it("returns nil, 'none installed' for a missing dir", function()
    assert.same({ nil, "none installed" }, { db.open("spec/fixtures/forever/nope") })
    assert.same({ nil, "none installed" }, { db.open(nil) })
  end)

  it("derives a node's map, zone and position from the region holding it", function()
    local n = d:node("Thelsamar, Loch Modan")
    assert.are.equal(8, n.id)
    assert.are.equal(1432, n.map_id)
    assert.are.equal("Loch Modan", n.zone)
    assert.are.equal(1415, n.continent)
    assert.are.equal(1, n.faction_bits)
    near(0.3394, n.x)
    near(0.5079, n.y)
  end)

  it("prefers the zone over the continent when both hold a node", function()
    assert.are.equal(1413, d:node("Crossroads, The Barrens").map_id)
    assert.is_nil(d:node("Nowhere"))
  end)

  it("lists a continent's nodes in ID order, by faction", function()
    local names = {}
    for _, n in ipairs(d:taxi_nodes(1415, "Alliance")) do names[#names + 1] = n.name end
    assert.same({ "Stormwind, Elwynn", "Ironforge, Dun Morogh", "Thelsamar, Loch Modan" }, names)
    local horde = d:taxi_nodes(1415, "Horde")
    assert.are.equal(1, #horde)
    assert.are.equal("Undercity, Tirisfal", horde[1].name)
    assert.has_error(function() d:taxi_nodes(1415, "Elf") end)
  end)

  it("walks UiMap parents to the continent", function()
    assert.are.equal(1415, d:continent_of(1453))
    assert.are.equal(1415, d:continent_of(1415))
    assert.are.equal(1414, d:continent_of(1413))
    assert.is_nil(d:continent_of(947))
    assert.is_nil(d:continent_of(99999))
  end)

  it("names a map's zone from AreaTable, else the UiMap name", function()
    assert.are.equal("Loch Modan", d:zone_of_map(1432))
    assert.are.equal("Eastern Kingdoms", d:zone_of_map(1415))
    assert.is_nil(d:zone_of_map(99999))
  end)

  it("maps an area to its UI map", function()
    assert.are.equal(1432, d:ui_map_of_area(38))
    assert.is_nil(d:ui_map_of_area(144))
  end)

  it("knows area names exactly", function()
    assert.is_false(d:is_area_name("Stormwind"))
    assert.is_false(d:is_area_name("stormwind city"))
    assert.is_true(d:is_area_name("Stormwind City"))
    assert.is_true(d:is_area_name("Trade District"))
    assert.is_true(d:is_area_name("Loch Modan"))
  end)
end)

-- TomTom stub design (2026-11-23): arrival distance in yards needs each map's size.
describe("forever db map_yards", function()
  local d = assert(db.open(FIX))
  -- The installed JSON keeps no UiMin/UiMax, so a region is taken as the whole map, as the
  -- node placement does; the largest region assigned to the map wins.
  it("sizes a map from its largest UiMapAssignment region", function()
    local row
    for line in io.lines("spec/fixtures/forever/UiMapAssignment.csv") do
      local f = {}
      for v in line:gmatch("[^,]+") do f[#f + 1] = v end
      if f[12] == "1426" then row = f break end
    end
    assert.is_truthy(row, "fixture has no 1426 row")
    local n = function(i) return tonumber(row[i]) end
    local w, h = d:map_yards(1426)
    assert.near(math.abs(n(9) - n(6)), w, 1e-6)
    assert.near(math.abs(n(8) - n(5)), h, 1e-6)
    assert.is_true(w > 0 and h > 0)
  end)
  it("is nil for a map with no region", function()
    assert.is_nil(d:map_yards(999999))
  end)
end)

describe("catalog forever", function()
  local function cfg(over)
    local c = { questie_source = dofile("spec/fixtures/catalog/questie_source.lua") }
    for k, v in pairs(over or {}) do c[k] = v end
    return { catalog = c, class = "WARRIOR", faction = "Alliance" }
  end

  it("opens the DB from forever_dir and records the source", function()
    local cat = catalog.load(cfg { forever_dir = FIX })
    assert.is_true(cat.sources.forever.present)
    assert.are.equal("1.60.1.70959", cat.sources.forever.build)
    assert.are.equal(FIX, cat.sources.forever.path)
    local map_id, x, y = cat:npc_position(1572)
    assert.are.equal(1432, map_id)
    near(0.3394, x)
    near(0.5095, y)
  end)

  it("records an absent DB and gives no position", function()
    local cat = catalog.load(cfg { forever_dir = "spec/fixtures/forever/nope" })
    assert.is_false(cat.sources.forever.present)
    assert.is_nil(cat.forever)
    assert.is_nil(cat:npc_position(1572))
  end)

  it("gives no position for an npc without spawns or without QuestieDB", function()
    local cat = catalog.load(cfg { forever_dir = FIX })
    assert.is_nil(cat:npc_position(2002))
    local no_questie = catalog.load(cfg { forever_dir = FIX, questie_source = false })
    no_questie.questie = nil
    assert.is_nil(no_questie:npc_position(1572))
  end)

  it("accepts a ready DB for specs", function()
    local cat = catalog.load(cfg { forever_db = assert(db.open(FIX)) })
    assert.is_true(cat.sources.forever.present)
    assert.is_not_nil(cat.forever)
  end)
end)
