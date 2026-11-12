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
    stubs.install(sb, cfg)
  end)

  it("reports the Forever build and player identity", function()
    assert.equal(16001, select(4, env.GetBuildInfo()))
    assert.same({ "Dwarf", "Dwarf" }, { env.UnitRace("player") })
    assert.same({ "Warrior", "WARRIOR" }, { env.UnitClass("player") })
  end)

  it("defines ERR_NEWTAXIPATH as the client string AutoCompleteGetFP compares against", function()
    assert.equal("New flight path discovered!", env.ERR_NEWTAXIPATH)
  end)

  it("IsPlayerSpell coerces the string spell id the engine passes (Broker.lua:3332-3340)", function()
    sb.world.player:learn_spell(3273)
    assert.is_true(env.IsPlayerSpell("3273"))
    assert.is_true(env.IsPlayerSpell(3273))
    assert.is_false(env.IsPlayerSpell("1"))
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
    assert.equal(env.ChatFrame1, env.DEFAULT_CHAT_FRAME)
    assert.equal(env.ChatFrame1, sb.frames:get("ChatFrame1"))
    env.DEFAULT_CHAT_FRAME:AddMessage("hi")
    assert.same({ "hi" }, sb.chat)
  end)

  it("plays sounds silently and has no quest dialog title", function()
    assert.is_true(env.PlaySoundFile("Sound/Interface/MapPing.ogg"))
    assert.equal("", env.GetTitleText())
  end)

  it("GetTitleText follows the open dialog", function()
    sb.world.catalog = { quest = function(_, id) return id == 179 and { name = "Dwarven Outfitters" } or nil end }
    assert.equal("", env.GetTitleText())
    sb.world.dialog = { qid = 179, kind = "detail" }
    assert.equal("Dwarven Outfitters", env.GetTitleText())
    sb.world.dialog = nil
    assert.equal("", env.GetTitleText())
  end)

  it("answers GetItemInfo from the catalog by id, numeric string or name", function()
    sb.world.catalog = {
      item = function(_, id) return tonumber(id) == 750 and { id = 750, name = "Tough Wolf Meat" } or nil end,
      item_id = function(_, name) return name == "Tough Wolf Meat" and 750 or nil end,
    }
    local name, link, _, _, _, _, _, _, _, texture = env.GetItemInfo(750)
    assert.equal("Tough Wolf Meat", name)
    assert.matches("|Hitem:750:", link, 1, true)
    assert.matches("[Tough Wolf Meat]", link, 1, true)
    assert.is_not_nil(texture)
    assert.equal("Tough Wolf Meat", (env.GetItemInfo("750")))
    assert.equal("Tough Wolf Meat", (env.GetItemInfo("Tough Wolf Meat")))
    assert.is_nil(env.GetItemInfo(1))
  end)

  it("returns nil from GetItemInfo without a catalog", function()
    assert.is_nil(env.GetItemInfo(750))
  end)

  it("returns strings for zone text and a map position", function()
    assert.is_string(env.GetSubZoneText())
    assert.is_string(env.GetZoneText())
    assert.same({ 0.3, 0.7 }, { env.C_Map.GetPlayerMapPosition(1426, "player"):GetXY() })
  end)

  it("records unstubbed namespaced reads as misses", function()
    assert.is_nil(env.C_QuestLog.GetQuestLogRewardXP)
    assert.is_nil(env.C_QuestLog.GetQuestLogRewardXP)
    assert.is_true(sb.missing["C_QuestLog.GetQuestLogRewardXP"])
    local n = 0
    for _, k in ipairs(sb.missing_order) do if k == "C_QuestLog.GetQuestLogRewardXP" then n = n + 1 end end
    assert.equal(1, n)
  end)

  it("models an empty quest log", function()
    assert.same({ 0, 0 }, { env.C_QuestLog.GetNumQuestLogEntries() })
    assert.is_nil(env.C_QuestLog.GetInfo(1))
    assert.is_false(env.C_QuestLog.IsQuestFlaggedCompleted(1))
    assert.is_false(env.C_QuestLog.IsQuestFlaggedCompletedOnAccount(1))
    assert.same({}, env.C_QuestLog.GetQuestObjectives(1))
    assert.is_false(env.C_QuestLog.IsFailed(1))
    assert.equal(0, env.GetNumQuestLeaderBoards(1))
    assert.equal(0, env.GetQuestProgressBarPercent(1))
    assert.equal(1, env.LE_QUEST_FREQUENCY_DAILY)
    assert.same({ Default = 0, Daily = 1, Weekly = 2 }, env.Enum.QuestFrequency)
  end)

  it("routes a timer callback's error to the error handler and keeps running", function()
    local after = false
    env.C_Timer.After(0.1, function() error("timer-boom") end)
    env.C_Timer.After(0.2, function() after = true end)
    sb.clock:settle()
    assert.is_true(after)
    assert.matches("timer%-boom", sb.errors[1].msg)
  end)

  it("keeps key bindings and per-owner override bindings", function()
    assert.is_nil(env.GetBindingKey("CLICK X:LeftButton"))
    assert.is_true(env.SetBinding("CTRL-SHIFT-I", "CLICK X:LeftButton"))
    assert.equal("CTRL-SHIFT-I", env.GetBindingKey("CLICK X:LeftButton"))
    local owner = env.CreateFrame("Frame")
    env.SetOverrideBindingClick(owner, false, "K", "Btn", "LeftButton")
    assert.same({ button = "Btn", click = "LeftButton" }, sb.override_bindings[owner].K)
    env.ClearOverrideBindings(owner)
    assert.is_nil(sb.override_bindings[owner])
  end)

  it("models the open world out of combat with no professions", function()
    assert.same({ false, "none" }, { env.IsInInstance() })
    assert.is_false(env.UnitAffectingCombat("player"))
    assert.same({}, env.C_TradeSkillUI.GetAllProfessionTradeSkillLines())
    assert.equal(0, select("#", env.GetProfessions()))
  end)

  it("knows the starting maps and records popups and super-tracking", function()
    assert.same({ mapID = 1426, name = "Dun Morogh", mapType = 3, parentMapID = 1415 }, env.C_Map.GetMapInfo(1426))
    assert.is_nil(env.C_Map.GetMapInfo(99999))
    env.StaticPopup_Show("WOWPRO_MISSING_ARROW")
    assert.same({ "WOWPRO_MISSING_ARROW" }, sb.popups)
    env.C_SuperTrack.SetSuperTrackedQuestID(179)
    assert.equal(179, env.C_SuperTrack.GetSuperTrackedQuestID())
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

  it("overrides only the listed UI calls the harness cannot run, and logs them", function()
    local sb = sandbox.new({})
    local real = function() return "real" end
    sb.env.WoWPro = { CreateMiniMapButton = real, LoadGuide = real }
    standins.override(sb)
    assert.equal(real, sb.env.WoWPro.LoadGuide)
    assert.is_nil(sb.env.WoWPro.CreateMiniMapButton())
    assert.same({ "CreateMiniMapButton" }, sb.standin_calls)
  end)
end)
