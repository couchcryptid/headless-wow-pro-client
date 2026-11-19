local config = require("hwc.config")
local sandbox = require("hwc.sandbox")
local stubs = require("hwc.stubs.core")
local World = require("hwc.world")

local catalog = { item_id = function(_, name) if name == "Tough Wolf Meat" then return 750 end end }

local function setup(tbl, cat)
  local cfg = config.load(tbl or { race = "Dwarf", class = "WARRIOR" })
  local sb = sandbox.new(cfg)
  sb.world = World.new(cfg, cat, sb.clock)
  stubs.install(sb, cfg)
  return sb, sb.env, sb.world.player
end

describe("Player behind the stubs", function()
  it("reads zone changes on every call", function()
    local sb, env, p = setup()
    p:set_zone("Ironforge", "", 1455, 0.5, 0.5)
    assert.equal("Ironforge", env.GetZoneText())
    assert.equal("Ironforge", env.GetRealZoneText())
    assert.equal(1455, env.C_Map.GetBestMapForUnit("player"))
    assert.same({ 0.5, 0.5 }, { env.C_Map.GetPlayerMapPosition(1455, "player"):GetXY() })
    assert.equal("zone", sb.world.events[1].kind)
  end)

  it("counts items by id, numeric string and name", function()
    local _, env, p = setup(nil, catalog)
    p:add_item(750, 8)
    assert.equal(8, env.GetItemCount(750))
    assert.equal(8, env.GetItemCount("750"))
    assert.equal(8, env.GetItemCount("Tough Wolf Meat"))
    assert.equal(8, env.C_Item.GetItemCount(750))
    assert.equal(0, env.GetItemCount("Unknown Thing"))
  end)

  it("gives 0 for names without a catalog", function()
    local _, env, p = setup()
    p:add_item(750, 8)
    assert.equal(0, env.GetItemCount("Tough Wolf Meat"))
  end)

  it("removes items only when enough are held", function()
    local _, _, p = setup()
    p:add_item(750, 3)
    assert.is_false(p:remove_item(750, 4))
    assert.equal(3, p:item_count(750))
    assert.is_true(p:remove_item(750, 3))
    assert.equal(0, p:item_count(750))
  end)

  it("tracks spells, bind, flight points and level/xp", function()
    local _, env, p = setup()
    assert.is_false(env.IsPlayerSpell(2550))
    p:learn_spell(2550)
    assert.is_true(env.IsPlayerSpell(2550))
    assert.is_nil(env.GetBindLocation())
    local inn = { npc = 1, bind = "Kharanos", zone = "Dun Morogh", subzone = "Thunderbrew Distillery", map_id = 1426, x = 46, y = 53 }
    p:set_bind(inn)
    assert.equal("Kharanos", env.GetBindLocation())
    assert.same({ name = "Kharanos", map_id = 1426, entry = inn }, p.bind)
    p:learn_flight_point("Thelsamar, Loch Modan")
    assert.is_true(p.flight_points["Thelsamar, Loch Modan"])
    p.level, p.xp = 5, 12
    assert.same({ 5, 12, 2800 }, { env.UnitLevel(), env.UnitXP(), env.UnitXPMax() })
  end)

  it("records an xp world event with the resulting level and xp", function()
    local _, _, p = setup()
    local events = {}
    p._record = function(kind, f) events[#events + 1] = { kind = kind, f = f } end
    assert.equal(1, p:add_xp(400 + 1))
    assert.equal("xp", events[1].kind)
    assert.same({ n = 401, level = p.level, xp = p.xp, levels = 1 }, events[1].f)
  end)

  it("reports Night Elf identity from the Alliance table", function()
    local _, env = setup({ race = "NightElf", class = "DRUID" })
    assert.same({ "Night Elf", "NightElf" }, { env.UnitRace() })
  end)

  it("stamps world events with the clock", function()
    local sb, _, p = setup()
    p:learn_spell(1)
    assert.same({ t = sb.clock:now(), kind = "learn_spell", id = 1 }, sb.world.events[1])
  end)

  it("applies configured professions to the Trade stubs", function()
    local _, env, p = setup({ race = "Human", class = "WARRIOR",
      professions = { { name = "First Aid", rank = 1, max = 75 } } })
    assert.is_true(p:knows_skill("First Aid"))
    assert.same({ 129 }, env.C_TradeSkillUI.GetAllProfessionTradeSkillLines())
    local info = env.C_TradeSkillUI.GetProfessionInfoBySkillLineID(129)
    assert.same({ "First Aid", 1, 75 }, { info.professionName, info.skillLevel, info.maxSkillLevel })
    assert.same({ 1 }, { env.GetProfessions() })
    assert.same({ "First Aid", 0, 1, 75, 0, 0, 129, 0 }, { env.GetProfessionInfo(1) })
  end)
end)

describe("config race scope", function()
  it("rejects races outside Player.RACES", function()
    assert.has_error(function() config.load({ race = "Goblin" }) end, "hwc: race not in scope: Goblin")
  end)
end)

-- Learning a profession teaches its spell (a "Learn Skill (<profession>)" effect),
-- which the guides' SPELL|...; Flip tags test.
describe("professions teach their spell", function()
  local Player = require("hwc.world.player")
  it("learn_skill on a profession also learns its spell", function()
    local p = Player.new({ race = "Dwarf", class = "WARRIOR", faction = "Alliance", sex = 2 })
    p:learn_skill("First Aid", 1, 75)
    assert.is_true(p.spells[3273])
    p:learn_skill("Cooking", 1, 75)
    assert.is_true(p.spells[2550])
  end)

  it("a skill with no profession spell learns no spell", function()
    local p = Player.new({ race = "Dwarf", class = "WARRIOR", faction = "Alliance", sex = 2 })
    p:learn_skill("Lockpicking", 1, 75)
    assert.are.same({}, p.spells)
  end)

  it("World.new professions start with their spells known", function()
    local cfg = config.load({ race = "Dwarf", class = "WARRIOR", professions = { { name = "Fishing", rank = 1, max = 75 } } })
    local w = World.new(cfg, nil)
    assert.is_true(w.player.spells[7620])
  end)
end)

-- Starting flight point and bind (arrival emulation spec section 2): learned from
-- hwc.world.arrivals (or cfg.arrivals) only when the Forever tables know the node.
describe("World.new start node", function()
  local forever_db = require("hwc.forever.db")
  local DB = forever_db.open("spec/fixtures/forever/installed")
  local function world(race, arrivals, db)
    local cfg = { race = race, class = "WARRIOR", sex = 2, arrivals = arrivals }
    return World.new(cfg, { forever = db == nil and DB or db or nil })
  end

  it("a new Dwarf knows its capital node", function()
    local w = world("Dwarf")
    assert.is_true(w.player.flight_points["Ironforge, Dun Morogh"])
    assert.is_nil(w.start_node_unknown)
    assert.same({}, w.events) -- the starting state, not a world change
  end)

  it("a Skyborne world learns no node and does not set start_node_unknown", function()
    for _, race in ipairs({ "SkyborneAlliance", "SkyborneHorde" }) do
      local w = world(race)
      assert.same({}, w.player.flight_points)
      assert.is_nil(w.start_node_unknown, race)
    end
  end)

  it("a race with no start node, or one the tables don't know, sets start_node_unknown", function()
    local w = world("Dwarf", { start_nodes = {}, start_bind = {} })
    assert.same({}, w.player.flight_points)
    assert.is_true(w.start_node_unknown)
    w = world("Orc") -- Orgrimmar is not in the fixture tables
    assert.same({}, w.player.flight_points)
    assert.is_true(w.start_node_unknown)
  end)

  it("without the tables learns nothing and flags nothing", function()
    local w = world("Dwarf", nil, false)
    assert.same({}, w.player.flight_points)
    assert.is_nil(w.start_node_unknown)
    assert.same({}, w.fp_unknown)
  end)

  it("applies start_bind when present", function()
    local w = world("Dwarf", { start_nodes = {}, start_bind = { Dwarf = { bind = "Kharanos", map_id = 1426 } } })
    assert.same({ name = "Kharanos", map_id = 1426 }, { name = w.player.bind.name, map_id = w.player.bind.map_id })
    assert.equal(w.arrivals.start_bind.Dwarf, w.player.bind.entry)
    assert.same({}, w.events)
  end)

  it("set_on_taxi sets the flag UnitOnTaxi reads and records a taxi event", function()
    local w = world("Dwarf")
    assert.is_false(w.player.on_taxi)
    w.player:set_on_taxi(true)
    assert.is_true(w.player.on_taxi)
    assert.same({ t = 0, kind = "taxi", on = true }, w.events[1])
  end)
end)
