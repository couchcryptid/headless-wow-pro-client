-- TomTom stub (design 2026-11-23): WoW-Pro's waypoints and the distance callback that
-- completes CC/CS steps (WoWPro_Mapping.lua:103-170, 440-600).
local sandbox = require("hwc.sandbox")
local config = require("hwc.config")
local stubs = require("hwc.stubs.core")
local tomtom = require("hwc.stubs.tomtom")
local forever_db = require("hwc.forever.db")

describe("TomTom stub", function()
  local sb, env, p, TT, calls, fn
  before_each(function()
    local cfg = config.load({ race = "Dwarf", class = "WARRIOR" })
    sb = sandbox.new(cfg)
    env = sb.env
    stubs.install(sb, cfg)
    sb.world.catalog = sb.world.catalog or {}
    sb.world.catalog.forever = assert(forever_db.open("spec/fixtures/forever/installed"))
    tomtom.install(sb)
    TT = env.TomTom
    p = sb.world.player
    p.map_id, p.x, p.y = 1426, 0.5, 0.5
    calls = {}
    fn = function(...) calls[#calls + 1] = { ... } end
  end)
  local function opts() return { callbacks = { distance = { [10] = fn } } } end

  it("has TomTom's default settings", function()
    assert.equal(10, TT.db.profile.persistence.cleardistance)
    assert.is_false(TT.db.profile.arrow.setclosest)
    assert.equal(15, TT.db.profile.arrow.arrival)
  end)

  it("fires once for a player already on the waypoint", function()
    local uid = TT:AddWaypoint(1426, 0.5, 0.5, opts())
    assert.equal("table", type(uid))
    tomtom.tick(sb)
    assert.equal(1, #calls)
    assert.same({ "distance", uid, 10 }, { calls[1][1], calls[1][2], calls[1][3] })
    assert.equal(0, calls[1][4])
    tomtom.tick(sb)
    assert.equal(1, #calls)
  end)

  it("fires when the player walks in, and again after leaving and coming back", function()
    TT:AddWaypoint(1426, 0.6, 0.6, opts())
    tomtom.tick(sb)
    assert.equal(0, #calls)
    p.x, p.y = 0.6, 0.6
    tomtom.tick(sb)
    assert.equal(1, #calls)
    p.x, p.y = 0.5, 0.5
    tomtom.tick(sb)
    p.x, p.y = 0.6, 0.6
    tomtom.tick(sb)
    assert.equal(2, #calls)
  end)

  it("never fires across maps or on a map with no region", function()
    TT:AddWaypoint(1427, 0.5, 0.5, opts())
    p.map_id = 999999
    TT:AddWaypoint(999999, 0.5, 0.5, opts())
    tomtom.tick(sb)
    assert.equal(0, #calls)
  end)

  it("stops firing for a removed waypoint; removing an unknown uid is fine", function()
    local uid = TT:AddWaypoint(1426, 0.5, 0.5, opts())
    TT:RemoveWaypoint(uid)
    TT:RemoveWaypoint(uid)
    TT:RemoveWaypoint({})
    tomtom.tick(sb)
    assert.equal(0, #calls)
  end)

  it("GetClosestWaypoint returns the nearer same-map waypoint, nil with none", function()
    assert.is_nil(TT:GetClosestWaypoint())
    local far = TT:AddWaypoint(1426, 0.9, 0.9, opts())
    local near = TT:AddWaypoint(1426, 0.52, 0.5, opts())
    assert.equal(near, TT:GetClosestWaypoint())
    TT:RemoveWaypoint(near)
    assert.equal(far, TT:GetClosestWaypoint())
  end)

  it("SetCrazyArrow records the arrow target", function()
    local uid = TT:AddWaypoint(1426, 0.5, 0.5, opts())
    TT:SetCrazyArrow(uid, 15, "t")
    assert.same({ uid, 15, "t" }, tomtom.state(sb).arrow)
  end)

  it("measurable: nil with no waypoints, false when none can be measured, true otherwise", function()
    assert.is_nil(tomtom.measurable(sb.world))
    TT:AddWaypoint(1427, 0.5, 0.5, opts())
    assert.is_false(tomtom.measurable(sb.world))
    TT:AddWaypoint(1426, 0.9, 0.9, opts())
    assert.is_true(tomtom.measurable(sb.world))
  end)

  it("is pending after a move or an add until a tick has looked", function()
    tomtom.tick(sb)
    assert.is_false(tomtom.pending(sb))
    TT:AddWaypoint(1426, 0.6, 0.6, opts())
    assert.is_true(tomtom.pending(sb))
    tomtom.tick(sb)
    assert.is_false(tomtom.pending(sb))
    p.x = 0.55
    assert.is_true(tomtom.pending(sb))
  end)

  it("ticks from a frame OnUpdate while a settle waits on pending", function()
    TT:AddWaypoint(1426, 0.5, 0.5, opts())
    sb.clock:settle({ busy = function() return tomtom.pending(sb) end })
    assert.equal(1, #calls)
  end)
end)
