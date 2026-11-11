-- Load-time WoW client API for the Forever flavor (TOC 16001). These model
-- the client, never what the addon "should" see.
local M = {}

local function titlecase(s) return (s:sub(1, 1):upper() .. s:sub(2):lower()) end

function M.player_from(cfg)
  return {
    name = "Hwc", realm = "HwcRealm", race = cfg.race,
    race_token = (cfg.race:gsub("%s", "")), class = titlecase(cfg.class),
    class_token = cfg.class:upper(), faction = cfg.faction, sex = cfg.sex,
    level = 1, xp = 0, xp_max = 400, zone = "Dun Morogh", subzone = "",
    map_id = 1426, x = 0.3, y = 0.7,
  }
end

local function read_toc_field(cfg, name, field)
  local f = io.open(cfg.addon_path .. "/" .. name .. "/" .. name .. ".toc", "rb")
  if not f then return nil end
  local value
  for line in f:lines() do
    local k, v = line:match("^##%s*([^:]+):%s*(.-)%s*$")
    if k == field then value = v; break end
  end
  f:close()
  return value
end

-- Namespace tables record reads of unstubbed fields as "<ns>.<field>" misses.
local function trap(sb, ns, tbl)
  return setmetatable(tbl, { __index = function(_, field)
    local key = ns .. "." .. tostring(field)
    if not sb.missing[key] then
      sb.missing[key] = true
      sb.missing_order[#sb.missing_order + 1] = key
    end
    return nil
  end })
end

M.trap = trap

function M.install(sb, cfg, player)
  local env, clock, frames = sb.env, sb.clock, sb.frames
  player = player or M.player_from(cfg)

  -- AceTimer-3.0.lua:30 captures GetTime and C_Timer.After as upvalues at load, so install before any library
  env.GetTime = function() return clock:now() end
  -- The client reports a timer callback's error to the error handler and keeps running.
  local function fire(fn, ...) xpcall(fn, env.geterrorhandler(), ...) end
  local function new_timer(delay, fn)
    local t = { cancelled = false }
    function t:Cancel() self.cancelled = true end
    function t:IsCancelled() return self.cancelled end
    clock:after(delay, function() if not t.cancelled then fire(fn, t) end end)
    return t
  end
  env.C_Timer = trap(sb, "C_Timer", {
    After = function(d, f) clock:after(d, function() fire(f) end) end,
    NewTimer = new_timer,
    NewTicker = function(d, f, iterations)
      local t = { cancelled = false }
      local count = 0
      function t:Cancel() self.cancelled = true end
      function t:IsCancelled() return self.cancelled end
      local function arm()
        clock:after(d, function()
          if t.cancelled then return end
          count = count + 1
          fire(f, t)
          if iterations and count >= iterations then t.cancelled = true end
          if not t.cancelled then arm() end
        end)
      end
      arm()
      return t
    end,
  })

  -- Frames: WoW publishes named frames as globals. AceAddon-3.0.lua:38, AceEvent-3.0.lua:23, AceDB-3.0.lua:57 (CreateFrame); WoWPro.lua:56-58 (DEFAULT_CHAT_FRAME:AddMessage)
  env.CreateFrame = function(ftype, name, parent, template)
    local f = frames:create(ftype, name, parent, template)
    if name then env[name] = f end
    return f
  end
  env.UIParent = env.CreateFrame("Frame", "UIParent")
  env.ChatFrame1 = env.CreateFrame("Frame", "ChatFrame1")
  env.DEFAULT_CHAT_FRAME = env.ChatFrame1
  env.ChatFrame1.AddMessage = function(_, msg) sb.chat[#sb.chat + 1] = msg end

  -- WoWPro_Config.lua:1402 (GetBuildInfo); WoWPro.lua:12 and WoWPro_RowUpdate.lua:1306 (GetAddOnMetadata)
  env.GetBuildInfo = function() return "1.16.1", "0", "Nov 1 2026", sb.cfg and sb.cfg.toc_version or 16001 end
  local meta_cache = {}
  local function get_meta(name, field)
    meta_cache[name] = meta_cache[name] or {}
    local c = meta_cache[name]
    if c[field] == nil then c[field] = read_toc_field(cfg, name, field) or false end
    return c[field] or nil
  end
  env.GetAddOnMetadata = get_meta
  env.C_AddOns = trap(sb, "C_AddOns", { GetAddOnMetadata = get_meta })

  -- WoWPro_RowUpdate.lua:1302-1314 and WoWPro_Parser.lua:1075 (UnitName/UnitClass/UnitRace/GetRealmName; AceDB-3.0.lua:254-258 at load)
  -- WoWPro.lua:285 (UnitFactionGroup), :267 (UnitLevel/UnitXP), :979 (UnitXPMax); WoWPro_Broker.lua:3131 (UnitSex); WoWPro_RowUpdate.lua:1311 (GetRealmName)
  env.UnitName = function() return player.name end
  env.GetRealmName = function() return player.realm end
  env.UnitClass = function() return player.class, player.class_token end
  env.UnitRace = function() return player.race, player.race_token end
  env.UnitFactionGroup = function() return player.faction, player.faction end
  env.UnitSex = function() return player.sex end
  env.UnitLevel = function() return player.level end
  env.UnitXP = function() return player.xp end
  env.UnitXPMax = function() return player.xp_max end

  -- WoWPro_Localization.lua:8 (GetLocale); AceDB-3.0.lua:263 (GetCurrentRegion/GetCurrentRegionName)
  env.GetLocale = function() return "enUS" end
  env.GetCurrentRegion = function() return 1 end
  env.GetCurrentRegionName = function() return "US" end

  -- WoWPro_Events.lua:234 (InCombatLockdown), :418 (IsInGroup); CallbackHandler-1.0.lua:10 (securecallfunction, load-time upvalue); AceAddon-3.0.lua:623 (IsLoggedIn, read per call)
  env.securecallfunction = function(f, ...) return f(...) end
  env.IsLoggedIn = function() return false end
  env.InCombatLockdown = function() return false end
  env.IsInGroup = function() return false end

  -- WoWPro_ZoneData_Forever.lua:6 (Enum.UIMapType)
  env.Enum = { UIMapType = { Cosmic = 0, World = 1, Continent = 2, Zone = 3, Dungeon = 4, Micro = 5, Orphan = 6 } }
  -- WoWPro_Events.lua:415 (RegisterAddonMessagePrefix); WoWPro_Broker.lua:823 (StaticPopupDialogs)
  env.C_ChatInfo = trap(sb, "C_ChatInfo", { RegisterAddonMessagePrefix = function() return true end })
  env.StaticPopupDialogs = {}
  -- WoWPro_Broker.lua:4853 (WOWPRO_MISSING_ARROW when no TomTom), :4872. Records the dialog name in sb.popups.
  sb.popups = sb.popups or {}
  env.StaticPopup_Show = function(which)
    sb.popups[#sb.popups + 1] = which
    return nil
  end

  -- WoWPro_CurrentGuide.lua:251-257 (GetBestMapForUnit, GetPlayerMapPosition, GetRealZoneText); WoWPro_Command.lua:56 and WoWPro_AutoComplete.lua:489-490 (GetSubZoneText)
  env.GetZoneText = function() return player.zone end
  env.GetRealZoneText = function() return player.zone end
  env.GetSubZoneText = function() return player.subzone end
  -- WoWPro_Mapping.lua:624 (CheckHBDData via WoWPro_Events.lua:302). Client map facts for the starting
  -- maps only; any other id returns nil like an unknown map.
  local MAPS = {
    [1426] = { mapID = 1426, name = "Dun Morogh", mapType = 3, parentMapID = 1415 },
    [1415] = { mapID = 1415, name = "Eastern Kingdoms", mapType = 2, parentMapID = 947 },
  }
  env.C_Map = trap(sb, "C_Map", {
    GetMapInfo = function(id)
      local m = MAPS[id]
      if not m then return nil end
      return { mapID = m.mapID, name = m.name, mapType = m.mapType, parentMapID = m.parentMapID }
    end,
    GetBestMapForUnit = function() return player.map_id end,
    GetPlayerMapPosition = function()
      return { GetXY = function() return player.x, player.y end }
    end,
  })

  -- WoWPro.lua:606-611 (GetBindingKey, then SetBinding when unbound). Fresh client: no bindings.
  local bindings = {}
  env.GetBindingKey = function(command)
    for key, cmd in pairs(bindings) do
      if cmd == command then return key end
    end
    return nil
  end
  env.SetBinding = function(key, command)
    bindings[key] = command
    return true
  end
  -- WoWPro_RowUpdate.lua:1393 (ClearOverrideBindings), :670/:841/:919/:1074 (SetOverrideBindingClick). Per-owner overrides.
  sb.override_bindings = {}
  env.ClearOverrideBindings = function(owner) sb.override_bindings[owner] = nil end
  env.SetOverrideBindingClick = function(owner, _priority, key, button, click)
    sb.override_bindings[owner] = sb.override_bindings[owner] or {}
    sb.override_bindings[owner][key] = { button = button, click = click }
  end

  -- WoWPro_CompatUtil.lua:215 via WoWPro_Mapping.lua:453 (MapPoint). Records the super-tracked quest.
  env.C_SuperTrack = trap(sb, "C_SuperTrack", {
    SetSuperTrackedQuestID = function(id) sb.super_tracked = id end,
    GetSuperTrackedQuestID = function() return sb.super_tracked or 0 end,
  })

  -- WoWPro.lua:1110 (ShouldPvPHide) via WoWPro_Events.lua:280 on PLAYER_ENTERING_WORLD. Open world.
  env.IsInInstance = function() return false, "none" end
  -- WoWPro.lua:1120 (ShouldCombatHide). Out of combat.
  env.UnitAffectingCombat = function() return false end

  -- WoWPro_Trade.lua:439 and :458 (UpdateTradeSkills, Forever/Retail path) via WoWPro_Events.lua:282. Fresh character: no professions.
  env.C_TradeSkillUI = trap(sb, "C_TradeSkillUI", {
    GetAllProfessionTradeSkillLines = function() return {} end,
  })
  env.GetProfessions = function() return end

  -- FrameXML constant. WoWPro_Widgets.lua:510 (CreateScrollbar border colour)
  env.TOOLTIP_DEFAULT_COLOR = { r = 1, g = 1, b = 1 }
  -- FrameXML table. WoWPro_CurrentGuide.lua:44 (ESC-closable frames)
  env.UISpecialFrames = {}

  require("hwc.stubs.questlog").install(sb, player)
end

return M
