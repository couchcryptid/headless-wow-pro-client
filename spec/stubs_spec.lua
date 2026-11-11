local sandbox = require("hwc.sandbox")
local config = require("hwc.config")
local stubs = require("hwc.stubs.core")
local standins = require("hwc.stubs.standins")
local hbd = require("hwc.stubs.hbd")

describe("stubs", function()
  local sb, env
  before_each(function()
    local cfg = config.load({ race = "Dwarf", class = "WARRIOR" })
    sb = sandbox.new(cfg)
    env = sb.env
    stubs.install(sb, cfg, stubs.player_from(cfg))
  end)

  it("reports the Forever build and player identity", function()
    assert.equal(16001, select(4, env.GetBuildInfo()))
    assert.same({ "Dwarf", "Dwarf" }, { env.UnitRace("player") })
    assert.same({ "Warrior", "WARRIOR" }, { env.UnitClass("player") })
  end)

  it("reads the addon version from its TOC", function()
    assert.is_string(env.GetAddOnMetadata("WoWPro", "Version"))
    assert.equal(env.GetAddOnMetadata("WoWPro", "Version"), env.C_AddOns.GetAddOnMetadata("WoWPro", "Version"))
    assert.is_nil(env.GetAddOnMetadata("WoWPro", "NoSuchField"))
  end)

  it("runs C_Timer.After through the virtual clock", function()
    local hit = 0
    env.C_Timer.After(0.1, function() hit = hit + 1 end)
    sb.clock:settle()
    assert.equal(1, hit)
  end)

  it("cancels timers and bounds tickers", function()
    local a, n = 0, 0
    local t = env.C_Timer.NewTimer(1, function() a = a + 1 end)
    t:Cancel()
    assert.is_true(t:IsCancelled())
    env.C_Timer.NewTicker(1, function() n = n + 1 end, 3)
    sb.clock:settle()
    assert.equal(0, a); assert.equal(3, n)
  end)

  it("publishes named frames as globals and captures chat", function()
    local f = env.CreateFrame("Frame", "HwcTest")
    assert.equal(f, env.HwcTest)
    env.DEFAULT_CHAT_FRAME:AddMessage("hi")
    assert.same({ "hi" }, sb.chat)
  end)

  it("returns strings for zone text and a map position", function()
    assert.is_string(env.GetSubZoneText())
    assert.is_string(env.GetZoneText())
    assert.same({ 0.3, 0.7 }, { env.C_Map.GetPlayerMapPosition(1426, "player"):GetXY() })
  end)

  it("models an empty quest log", function()
    assert.same({ 0, 0 }, { env.C_QuestLog.GetNumQuestLogEntries() })
    assert.is_nil(env.C_QuestLog.GetInfo(1))
    assert.is_false(env.C_QuestLog.IsQuestFlaggedCompleted(1))
    assert.is_false(env.C_QuestLog.IsQuestFlaggedCompletedOnAccount(1))
  end)
end)

describe("hbd.register", function()
  it("errors clearly without LibStub", function()
    local sb = sandbox.new({})
    assert.has_error(function() hbd.register(sb) end, "hwc: LibStub must load before the HBD stub")
  end)

  it("registers both libraries on LibStub", function()
    local sb = sandbox.new({})
    sb.env.LibStub = { NewLibrary = function(self, name) self.libs = self.libs or {}
      local t = {}; self.libs[name] = t; return t end }
    sb.env.LibStub.__call = nil
    hbd.register(sb)
    local h = sb.env.LibStub.libs["HereBeDragons-2.0"]
    local a, b = h:GetZoneSize(1426)
    assert.same({ 1000, 1000 }, { a, b })
    assert.same({ 0, 0, 0 }, { h:GetZoneDistance(1, 0, 0, 1, 1, 1) })
    assert.equal(77, sb.env.LibStub.libs["HereBeDragons-Migrate"]:GetUIMapIDFromMapAreaId(77))
  end)
end)

describe("standins", function()
  it("keeps existing addon functions and logs the rest", function()
    local sb = sandbox.new({})
    local keep = function() return "real" end
    sb.env.WoWPro = { RefreshConfig = keep }
    standins.install(sb)
    assert.equal(keep, sb.env.WoWPro.RefreshConfig)
    sb.env.WoWPro.SetDefaults()
    assert.same({ "SetDefaults" }, sb.standin_calls)
  end)
end)
