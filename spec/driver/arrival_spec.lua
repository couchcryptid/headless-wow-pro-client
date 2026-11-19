-- Pure matching helpers for arrival emulation (design spec §3, §9).
local arrival = require("hwc.driver.arrival")

local function fake_db(...)
  local set = {}
  for _, n in ipairs({ ... }) do set[n] = true end
  return { is_area_name = function(_, s) return set[s] == true end }
end

describe("arrival.nearest", function()
  local function pos_of(it) return it.map, it.x, it.y end
  it("picks the closest, ignores other maps and out-of-radius items", function()
    local list = {
      { id = "far", map = 1, x = 0.30, y = 0.30 },
      { id = "other", map = 2, x = 0.50, y = 0.50 },
      { id = "near", map = 1, x = 0.51, y = 0.50 },
      { id = "nearer", map = 1, x = 0.505, y = 0.50 },
    }
    assert.equals("nearer", arrival.nearest(list, 1, 0.50, 0.50, pos_of).id)
  end)
  it("returns nil when nothing is within the radius", function()
    assert.is_nil(arrival.nearest({ { map = 1, x = 0.9, y = 0.9 } }, 1, 0.1, 0.1, pos_of))
  end)
  it("breaks a tie toward the earlier item", function()
    local list = { { id = "a", map = 1, x = 0.52, y = 0.5 }, { id = "b", map = 1, x = 0.48, y = 0.5 } }
    assert.equals("a", arrival.nearest(list, 1, 0.5, 0.5, pos_of).id)
  end)
end)

describe("arrival.exact", function()
  local landing = { zone = "Stormwind City", subzone = "Trade District", map_id = 1453 }
  it("matches zone, subzone and map id", function()
    assert.is_true(arrival.exact(landing, "Stormwind City"))
    assert.is_true(arrival.exact(landing, "Trade District"))
    assert.is_true(arrival.exact(landing, "1453"))
  end)
  it("does not match partials", function()
    assert.is_false(arrival.exact(landing, "Stormwind"))
    assert.is_false(arrival.exact(landing, "1454"))
  end)
  it("ignores a nil subzone", function()
    assert.is_false(arrival.exact({ zone = "A", map_id = 1 }, "B"))
  end)
end)

describe("arrival.location", function()
  it("takes the text before the first comma, trimmed", function()
    assert.equals("Stormwind", arrival.location("Stormwind , Elwynn"))
    assert.equals("Ratchet", arrival.location("Ratchet"))
  end)
end)

describe("arrival.loose", function()
  local nodes = {
    { name = "Stormwind, Elwynn", zone = "Elwynn Forest", subzone = "" },
    { name = "Ironforge, Dun Morogh", zone = "Dun Morogh", subzone = "" },
    { name = "Port Alpha, X", zone = "Z1", subzone = "" },
    { name = "Port Beta, Y", zone = "Z2", subzone = "" },
  }
  it("finds a prefix hit", function()
    assert.equals(nodes[1], (arrival.loose(nodes, "Stormwind", nil)))
  end)
  it("reports none", function()
    local r, why = arrival.loose(nodes, "Gadgetzem", nil)
    assert.is_nil(r)
    assert.equals("none", why)
  end)
  it("reports ambiguous", function()
    local r, why = arrival.loose(nodes, "port", nil)
    assert.is_nil(r)
    assert.equals("ambiguous", why)
  end)
  it("falls back to the first TZ part", function()
    assert.equals(nodes[2], (arrival.loose(nodes, "Nowhere", " dun morogh ; extra")))
  end)
  it("prefers a higher tier", function()
    local c = { { name = "Port, A", zone = "", subzone = "" }, { name = "Portal Hub, B", zone = "", subzone = "" } }
    assert.equals(c[1], (arrival.loose(c, "port", nil)))
  end)
  it("matches zone and subzone", function()
    local c = { { name = "N, A", zone = "Loch Modan", subzone = "Thelsamar" } }
    assert.equals(c[1], (arrival.loose(c, "thelsamar", nil)))
  end)
end)

describe("arrival.classify", function()
  local db = fake_db("Thelsamar", "Loch Modan", "Teldrassil")
  local landing = { zone = "Loch Modan", map_id = 48 }
  it("flags a name that is not an area", function()
    assert.equals("name-not-an-area", arrival.classify(db, landing, "Stormwind", nil))
  end)
  it("advances on exact zone", function()
    assert.equals("advances", arrival.classify(db, landing, "Loch Modan", nil))
  end)
  it("advances on a numeric TZ equal to the map id", function()
    assert.equals("advances", arrival.classify(db, landing, "Stormwind", "48"))
  end)
  it("advances on exact known subzone", function()
    assert.equals("advances", arrival.classify(db, { zone = "Loch Modan", subzone = "Thelsamar", map_id = 48 }, "Thelsamar", nil))
  end)
  it("is subzone-unknown when the subzone is nil", function()
    assert.equals("subzone-unknown", arrival.classify(db, landing, "Thelsamar", nil))
  end)
  it("is subzone-known when the subzone is known but differs", function()
    assert.equals("subzone-known", arrival.classify(db, { zone = "Loch Modan", subzone = "", map_id = 48 }, "Thelsamar", nil))
  end)
  it("does not call a Kalimdor area name not-an-area", function()
    assert.equals("subzone-unknown", arrival.classify(db, landing, "Teldrassil", nil))
  end)
  it("accepts an area-name TZ when the name is not an area", function()
    assert.equals("subzone-unknown", arrival.classify(db, landing, "Stormwind", "Thelsamar;x"))
  end)
end)
