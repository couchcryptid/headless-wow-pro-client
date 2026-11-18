local ReputationState = require("hwc.world.reputation_state")

local NAMES = { [72] = "Stormwind", [92] = "Gelkis Clan Centaur", [93] = "Magram Clan Centaur" }

describe("ReputationState", function()
  it("starts a Dwarf from the captured table; unmet factions are unknown", function()
    local s = ReputationState.new("Dwarf", "Alliance", NAMES)
    assert.equal(4000, s:points(47))
    assert.equal(3100, s:points(72))
    assert.is_false(s:known(92))
    assert.is_nil(s:points(92))
    assert.same({}, s.changes)
    assert.same({}, s.lookups)
  end)

  it("compares an unmet faction at its met-at value", function()
    local s = ReputationState.new("Dwarf", "Alliance", NAMES)
    assert.equal(2000, s:value_for_gate(92))
    assert.equal(0, s:value_for_gate(91))
    assert.equal(3100, s:value_for_gate(72))
  end)

  it("creates an unmet faction at its met-at value before adding a gain", function()
    local s = ReputationState.new("Dwarf", "Alliance", NAMES)
    assert.equal(2100, s:gain(92, 100))
    assert.is_true(s:known(92))
    assert.equal(2100, s:points(92))
  end)

  -- Review Focus 2: 1382 rewards Gelkis +100 and Magram -500, both unmet.
  it("applies a known and an unknown faction's reward in one go", function()
    local s = ReputationState.new("Dwarf", "Alliance", NAMES)
    assert.equal(2100, s:gain(92, 100))
    assert.equal(1500, s:gain(93, -500))
    assert.equal(3600, s:gain(72, 500))
  end)

  it("clamps a gain to the scale", function()
    local s = ReputationState.new("Dwarf", "Alliance", NAMES)
    assert.equal(-42000, s:gain(93, -100000))
    assert.equal(42999, s:gain(47, 100000))
  end)

  -- Review Focus 3: Skyborne has no home faction.
  it("starts Skyborne with its side's capitals and no home, and still gains", function()
    local s = ReputationState.new("SkyborneAlliance", "Alliance", NAMES)
    assert.equal(3100, s:points(72))
    assert.equal(3100, s:points(47))
    assert.equal(3100, s:points(54))
    assert.equal(3100, s:points(69))
    assert.equal(3350, s:gain(72, 250))
  end)

  it("records a quest's reward as a change, flagging an assumed start", function()
    local s = ReputationState.new("Dwarf", "Alliance", NAMES)
    assert.equal(2100, s:reward(1382, 92, 100))
    s:reward(1382, 91, 5)
    s:reward(1383, 72, 50)
    assert.same({
      { qid = 1382, faction = 92, value = 100, total = 2100, assumed_start = false },
      { qid = 1382, faction = 91, value = 5, total = 5, assumed_start = true },
      { qid = 1383, faction = 72, value = 50, total = 3150, assumed_start = false },
    }, s.changes)
    assert.same({ "factions first met at an assumed Neutral 0: Faction 91",
      "reward scaling by level is unverified for Forever" }, s:assumptions())
  end)

  it("lists no assumption for a fresh Dwarf", function()
    assert.same({}, ReputationState.new("Dwarf", "Alliance", NAMES):assumptions())
  end)

  it("names an inferred start table and the factions met at an assumed 0", function()
    local s = ReputationState.new("Gnome", "Alliance", NAMES)
    s:gain(92, 100) -- met at 2000, not assumed
    s:gain(91, 1)
    local a = s:assumptions()
    assert.equal("starting reputation for Gnome is inferred, not captured", a[1])
    assert.equal("factions first met at an assumed Neutral 0: Faction 91", a[2])
  end)

  it("sorts the assumed factions by name", function()
    local s = ReputationState.new("Dwarf", "Alliance", { [600] = "Alpha", [500] = "Zeta" })
    s:gain(500, 1)
    s:gain(600, 1)
    assert.truthy(s:assumptions()[1]:find(": Alpha, Zeta$"))
  end)

  it("takes a names function as well as a table", function()
    local s = ReputationState.new("Dwarf", "Alliance", function(id) return "N" .. id end)
    s:gain(91, 1)
    assert.truthy(s:assumptions()[1]:find(": N91$"))
  end)

  it("reports the gate a quest fails, or nil", function()
    local s = ReputationState.new("Dwarf", "Alliance", NAMES)
    assert.is_nil(s:gate({}))
    assert.same({ faction = 72, bound = "min", value = 9000, points = 3100 },
      s:gate({ min_rep = { faction = 72, value = 9000 } }))
    assert.is_nil(s:gate({ min_rep = { faction = 72, value = 3100 } }))
    assert.is_nil(s:gate({ max_rep = { faction = 92, value = 3000 } }))
    assert.same({ faction = 92, bound = "max", value = 2000, points = 2000 },
      s:gate({ max_rep = { faction = 92, value = 2000 } }))
    -- A negative min_rep passes an unmet faction at 0, as in game.
    assert.is_nil(s:gate({ min_rep = { faction = 91, value = -3000 } }))
  end)
end)
